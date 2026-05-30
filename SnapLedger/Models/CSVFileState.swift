import Foundation
import SwiftData

/// 앱이 마지막으로 동기화(읽기/쓰기)한 월별 CSV 파일의 지문.
/// 외부 변경 감지의 기준점 — 현재 파일 지문과 이 값이 다르면 앱 밖에서 수정된 것.
@Model
final class CSVFileState {
    var filename: String
    var lastSyncedHash: String
    var lastSyncedModified: Date?
    var lastSyncedAt: Date

    init(
        filename: String,
        lastSyncedHash: String,
        lastSyncedModified: Date? = nil,
        lastSyncedAt: Date = .now
    ) {
        self.filename = filename
        self.lastSyncedHash = lastSyncedHash
        self.lastSyncedModified = lastSyncedModified
        self.lastSyncedAt = lastSyncedAt
    }
}
