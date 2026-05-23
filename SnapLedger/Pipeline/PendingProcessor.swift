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

    func drain(in context: ModelContext) async {
        guard extractionService.isAvailable else {
            log.info("drain skipped: extraction service unavailable")
            return
        }
        reconcileInbox(in: context)
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
        defer { try? FileManager.default.removeItem(at: imageURL) }

        do {
            let ocrText = try await ocrService.recognize(imageURL: imageURL)
            // 풍경 등 결제 신호가 전혀 없는 이미지는 LLM에 보내지 않고
            // 빈 추출 결과로 처리 — FM이 환각으로 가짜 거래를 만들어내는 것을 막는다.
            let extraction: PaymentExtraction
            if CandidateHeuristics.hasPaymentSignal(ocrText) {
                extraction = try await extractionService.extract(from: ocrText)
            } else {
                log.info("skipping extraction: no payment signal in OCR text")
                extraction = PaymentExtraction(transactions: [])
            }
            let enriched = CandidateHeuristics.enrich(extraction, ocrText: ocrText)
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

    static let noPaymentSignalReason = "이미지에서 결제 정보를 찾지 못했어요. 영수증·결제 알림 스크린샷이 맞는지 확인해 주세요."

    func makeEntries(
        from enriched: [EnrichedTransaction],
        sourceFilename: String,
        in context: ModelContext
    ) -> [ParsedEntry] {
        guard !enriched.isEmpty else {
            return [
                ParsedEntry(
                    date: .now,
                    amount: 0,
                    merchant: "",
                    category: nil,
                    sourceImagePath: sourceFilename,
                    failureReason: Self.noPaymentSignalReason
                ),
            ]
        }
        return enriched.flatMap { et in
            entries(for: et, sourceFilename: sourceFilename, in: context)
        }
    }

    private func entries(
        for enriched: EnrichedTransaction,
        sourceFilename: String,
        in context: ModelContext
    ) -> [ParsedEntry] {
        let txn = enriched.base
        let parsedDate = Self.parseDate(txn.date) ?? .now
        let learnedCategory = (try? categoryLearner.category(for: txn.merchant, in: context)).flatMap { $0 }
        let trimmedExtractionCategory: String? = {
            let v = txn.category.trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : v
        }()
        let categoryForRow = learnedCategory ?? trimmedExtractionCategory

        if txn.items.isEmpty {
            return [
                ParsedEntry(
                    date: parsedDate,
                    amount: txn.amount,
                    merchant: txn.merchant,
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
