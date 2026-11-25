import Foundation
import OSLog
import SwiftData

private let log = Logger(subsystem: "com.youngkyu.snapledger", category: "intent")

/// How an intent's inbox file came out.
enum InboxIntentOutcome: Equatable {
    /// Entries now waiting in review, as "<merchant> <amount>원" joined by commas.
    case added(String)
    /// Intent text without a payment; its row and file are gone.
    case skipped
    /// No payment found; the failed row stays in review.
    case nothingFound
    /// Extraction failed; review can retry it.
    case failed
    /// Not processed yet; the app picks it up later.
    case queued

    var message: String {
        switch self {
        case .added(let summary): summary
        case .skipped: "결제 내용이 없어 건너뛰었어요."
        case .nothingFound: "처리할 결제 내역을 찾지 못했어요."
        case .failed: "처리하지 못했어요. 검토 목록에서 다시 시도할 수 있어요."
        case .queued: "검토 목록에 추가했어요. 앱에서 처리할게요."
        }
    }
}

/// Queues an intent's file, starts a drain, and waits for that file's outcome.
@MainActor
struct InboxIntentRunner {
    let container: ModelContainer
    let processor: PendingProcessor
    /// Kept under the system's 30-second intent limit; a file still waiting stays queued for the app.
    var deadline: Duration = .seconds(20)
    var pollInterval: Duration = .milliseconds(250)

    func run(
        writing data: Data,
        fileExtension: String,
        discardsWhenNothingFound: Bool = false
    ) async throws -> InboxIntentOutcome {
        let filename = "\(UUID().uuidString).\(fileExtension)"
        let url = processor.inboxURL.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        let context = ModelContext(container)
        context.insert(PendingImage(filename: filename, discardsWhenNothingFound: discardsWhenNothingFound))
        do {
            try context.save()
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }

        guard processor.extractionService.isAvailable else { return .queued }
        // Not tied to this intent's task, so its time limit cannot cut off files queued by others.
        Task { [processor, container] in
            await processor.drain(in: ModelContext(container))
        }
        return await outcome(of: filename)
    }

    private func outcome(of filename: String) async -> InboxIntentOutcome {
        let end = ContinuousClock.now.advanced(by: deadline)
        while ContinuousClock.now < end {
            if let settled = settledOutcome(of: filename) { return settled }
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                break
            }
        }
        return settledOutcome(of: filename) ?? .queued
    }

    /// Reads by filename in a fresh context: the drain may have changed or deleted the row in another one.
    private func settledOutcome(of filename: String) -> InboxIntentOutcome? {
        let context = ModelContext(container)
        do {
            let entries = try context.fetch(FetchDescriptor<ParsedEntry>(
                predicate: #Predicate { $0.sourceImagePath == filename }
            ))
            if !entries.isEmpty {
                return .added(entries.map { "\($0.merchant) \($0.amount.formatted(.number))원" }.joined(separator: ", "))
            }
            let rows = try context.fetch(FetchDescriptor<PendingImage>(
                predicate: #Predicate { $0.filename == filename }
            ))
            guard let row = rows.first else { return .skipped }
            switch row.state {
            case .queued, .processing:
                return nil
            case .done:
                return .nothingFound
            case .failed:
                return PendingProcessor.isRetryable(failureMessage: row.failureMessage) ? .failed : .nothingFound
            }
        } catch {
            log.error("intent outcome fetch failed: \(String(describing: error))")
            return nil
        }
    }
}

extension InboxIntentRunner {
    init(container: ModelContainer) {
        self.init(container: container, processor: .make(in: ModelContext(container)))
    }
}
