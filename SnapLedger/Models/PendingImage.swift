import Foundation
import SwiftData

enum PendingImageState: String, Codable, Sendable {
    case queued
    case processing
    case done
    case failed
}

@Model
final class PendingImage {
    var id: UUID
    var filename: String
    var receivedAt: Date
    var state: PendingImageState
    var failureMessage: String?

    init(
        id: UUID = UUID(),
        filename: String,
        receivedAt: Date = .now,
        state: PendingImageState = .queued,
        failureMessage: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.receivedAt = receivedAt
        self.state = state
        self.failureMessage = failureMessage
    }
}
