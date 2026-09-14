import Foundation
import OSLog
import SwiftData

private let log = Logger(subsystem: "com.youngkyu.snapledger", category: "pending")

@MainActor
struct PendingProcessor {
    let inboxURL: URL
    let ocrService: OCRService
    let extractionService: ExtractionService
    let categoryLearner: CategoryLearner

    static func make(in context: ModelContext) -> PendingProcessor {
        PendingProcessor(
            inboxURL: AppGroup.inboxURL,
            ocrService: VisionKitOCRService(),
            extractionService: FoundationModelsExtractionService(
                customGuide: AppSettings.currentGuide(in: context),
                categories: AppSettings.currentCategories(in: context)
            ),
            categoryLearner: CategoryLearner()
        )
    }

    /// Prevents concurrent drain executions.
    private static var isDraining = false

    func drain(in context: ModelContext) async {
        guard extractionService.isAvailable else {
            log.info("drain skipped: extraction service unavailable")
            return
        }
        guard !Self.isDraining else {
            log.info("drain skipped: already running")
            return
        }
        Self.isDraining = true
        defer { Self.isDraining = false }

        reconcileInbox(in: context)
        requeueStaleProcessing(in: context)
        let all: [PendingImage]
        do {
            all = try context.fetch(FetchDescriptor<PendingImage>())
        } catch {
            log.error("drain fetch failed: \(String(describing: error))")
            return
        }
        for pending in all where pending.state == .queued {
            await process(pending, in: context)
        }
        cleanupResolvedImages(in: context)
    }

    /// Requeues stale processing images to queued state.
    func requeueStaleProcessing(in context: ModelContext) {
        let stale: [PendingImage]
        do {
            stale = try context.fetch(FetchDescriptor<PendingImage>())
                .filter { $0.state == .processing }
        } catch {
            log.error("requeue fetch failed: \(String(describing: error))")
            return
        }
        guard !stale.isEmpty else { return }
        for pending in stale {
            pending.state = .queued
            pending.failureMessage = nil
        }
        try? context.save()
    }

    /// Removes completed inbox images no longer referenced by pending entries.
    func cleanupResolvedImages(in context: ModelContext) {
        let parsedEntries: [ParsedEntry]
        let dones: [PendingImage]
        do {
            parsedEntries = try context.fetch(FetchDescriptor<ParsedEntry>())
            dones = try context.fetch(FetchDescriptor<PendingImage>()).filter { $0.state == .done }
        } catch {
            log.error("cleanup fetch failed: \(String(describing: error))")
            return
        }
        let referenced = Set(
            parsedEntries
                .filter { $0.status == .pending }
                .compactMap(\.sourceImagePath)
        )
        var changed = false
        for done in dones where !referenced.contains(done.filename) {
            let url = inboxURL.appendingPathComponent(done.filename)
            try? FileManager.default.removeItem(at: url)
            context.delete(done)
            changed = true
        }
        if changed {
            try? context.save()
        }
    }

    func reconcileInbox(in context: ModelContext) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return
        }
        let existingNames: [String]
        do {
            existingNames = try context.fetch(FetchDescriptor<PendingImage>()).map(\.filename)
        } catch {
            log.error("reconcile fetch failed: \(String(describing: error))")
            existingNames = []
        }
        let existing = Set(existingNames)
        var inserted = false
        for url in entries {
            let isRegularFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            guard isRegularFile else { continue }
            let name = url.lastPathComponent
            guard !existing.contains(name) else { continue }
            context.insert(PendingImage(filename: name))
            inserted = true
        }
        if inserted {
            try? context.save()
        }
    }

    func process(_ pending: PendingImage, in context: ModelContext) async {
        pending.state = .processing
        try? context.save()

        let imageURL = inboxURL.appendingPathComponent(pending.filename)
        do {
            let ocrText = try await ocrService.recognize(imageURL: imageURL)
            // Skip extraction if no payment signals are detected in OCR text
            let extraction: PaymentExtraction
            if CandidateHeuristics.hasPaymentSignal(ocrText) {
                extraction = try await extractionService.extract(from: ocrText)
            } else {
                log.info("skipping extraction: no payment signal in OCR text")
                extraction = PaymentExtraction(transactions: [])
            }
            let enriched = CandidateHeuristics.enrich(extraction, ocrText: ocrText)
            if enriched.isEmpty {
                // Mark as failed if no transactions were extracted
                pending.state = .failed
                pending.failureMessage = Self.noPaymentSignalReason
                try context.save()
                return
            }
            let entries = makeEntries(
                from: enriched, sourceFilename: pending.filename, in: context
            )
            for entry in entries {
                context.insert(entry)
            }
            pending.state = .done
            try context.save()
        } catch {
            pending.state = .failed
            pending.failureMessage = String(describing: error)
            try? context.save()
        }
    }

    nonisolated static let noPaymentSignalReason = "이미지에서 결제 정보를 찾지 못했어요."

    /// Checks whether failed image is eligible for retry.
    nonisolated static func isRetryable(failureMessage: String?) -> Bool {
        failureMessage != noPaymentSignalReason
    }

    func makeEntries(
        from enriched: [EnrichedTransaction],
        sourceFilename: String,
        in context: ModelContext
    ) -> [ParsedEntry] {
        let presets = AppSettings.currentCategories(in: context)
        return enriched.flatMap { et in
            entries(for: et, sourceFilename: sourceFilename, presets: presets, in: context)
        }
    }

    private func entries(
        for enriched: EnrichedTransaction,
        sourceFilename: String,
        presets: [String],
        in context: ModelContext
    ) -> [ParsedEntry] {
        let txn = enriched.base
        let parsedDate = Self.parseDate(txn.date) ?? .now
        let learnedCategory = (try? categoryLearner.category(for: txn.merchant, in: context)).flatMap { $0 }
        let trimmedExtractionCategory: String? = {
            let v = txn.category.trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : v
        }()
        // Resolve category restricted to current presets
        let categoryForRow = CandidateAutoFill.category(
            learned: learnedCategory, extracted: trimmedExtractionCategory, presets: presets
        )

        if txn.items.isEmpty {
            // Auto-fill empty fields from candidates
            let filledMerchant = CandidateAutoFill.merchant(
                current: txn.merchant, candidates: enriched.merchantCandidates
            )
            let filledAmount = CandidateAutoFill.amount(
                current: txn.amount, candidates: enriched.amountCandidates
            )
            return [
                ParsedEntry(
                    date: parsedDate,
                    amount: filledAmount,
                    merchant: filledMerchant,
                    category: categoryForRow,
                    sourceImagePath: sourceFilename,
                    merchantCandidates: enriched.merchantCandidates,
                    amountCandidates: enriched.amountCandidates
                ),
            ]
        }
        return txn.items.map { item in
            ParsedEntry(
                date: parsedDate,
                amount: item.amount,
                merchant: "\(txn.merchant) - \(item.name)",
                category: categoryForRow,
                sourceImagePath: sourceFilename,
                merchantCandidates: enriched.merchantCandidates,
                amountCandidates: enriched.amountCandidates
            )
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return dateFormatter.date(from: trimmed)
    }
}
