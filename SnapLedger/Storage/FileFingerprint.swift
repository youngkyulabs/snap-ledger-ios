import CryptoKit
import Foundation

/// 월별 CSV 파일의 현재 상태를 읽어 지문(내용 해시 + 수정시각)을 만든다.
/// iCloud Drive 파일이 아직 로컬에 내려와 있지 않으면 다운로드만 트리거하고
/// `.notDownloaded` 를 즉시 반환한다 — 부분 데이터로 변경/충돌을 오판하지 않기 위함.
/// (메인 스레드를 다운로드 완료까지 블로킹하지 않는다.)
enum FileFingerprint {
    struct Content: Equatable {
        let text: String
        let hash: String
        let modified: Date?
    }

    enum Readiness: Equatable {
        case ready(Content)
        case notDownloaded
        case missing
    }

    static func read(at url: URL) -> Readiness {
        let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
        ])
        let isUbiquitous = values?.isUbiquitousItem ?? false

        if isUbiquitous {
            let isCurrent = values?.ubiquitousItemDownloadingStatus == .current
            let isDownloading = values?.ubiquitousItemIsDownloading ?? false
            if !isCurrent || isDownloading {
                triggerDownload(at: url)
                return .notDownloaded
            }
        } else if !FileManager.default.fileExists(atPath: url.path) {
            return .missing
        }

        guard let content = coordinatedRead(at: url) else {
            return isUbiquitous ? .notDownloaded : .missing
        }
        return .ready(content)
    }

    private static func coordinatedRead(at url: URL) -> Content? {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var content: Content?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            guard let data = try? Data(contentsOf: coordinatedURL) else { return }
            let modified = (try? coordinatedURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ))?.contentModificationDate
            content = Content(
                text: String(bytes: data, encoding: .utf8) ?? "",
                hash: sha256Hex(data),
                modified: modified
            )
        }
        if coordinationError != nil { return nil }
        return content
    }

    private static func triggerDownload(at url: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
