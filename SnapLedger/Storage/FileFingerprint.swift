import CryptoKit
import Foundation

/// 월별 CSV 파일의 현재 상태를 읽어 지문(내용 해시 + 수정시각)을 만든다.
/// iCloud Drive 파일이 아직 로컬에 내려와 있지 않으면 다운로드만 트리거하고
/// `.notDownloaded` 를 즉시 반환한다 — 부분 데이터로 변경/충돌을 오판하지 않기 위함.
/// (메인 스레드를 다운로드 완료까지 블로킹하지 않는다.)
///
/// 파일 I/O를 메인 액터 밖에서도 돌릴 수 있도록 `nonisolated`. 반환 타입은 `Sendable`.
nonisolated enum FileFingerprint {
    struct Content: Equatable, Sendable {
        let text: String
        let hash: String
        let modified: Date?
    }

    enum Readiness: Equatable, Sendable {
        case ready(Content)
        case notDownloaded
        case missing
        /// 파일은 존재하나 읽지 못함(권한·일시적 잠금·비-UTF8 등). "부재"나 "변경"으로
        /// 오판하면 그 달을 비우거나 잘못 덮어쓸 수 있으므로 별도 상태로 구분한다.
        case unreadable
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

        switch coordinatedRead(at: url) {
        case .success(let content):
            return .ready(content)
        case .notFound:
            // ubiquitous면 아직 안 받아온 것, 로컬이면 위 존재 확인 후 경합으로 사라진 것.
            return isUbiquitous ? .notDownloaded : .missing
        case .unreadable:
            return .unreadable
        }
    }

    private enum ReadOutcome {
        case success(Content)
        case notFound
        case unreadable
    }

    private static func coordinatedRead(at url: URL) -> ReadOutcome {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var outcome: ReadOutcome = .notFound
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            guard let data = try? Data(contentsOf: coordinatedURL) else {
                // 읽기 실패: 파일이 아직 있으면 "읽기 불가", 사라졌으면 "부재".
                outcome = FileManager.default.fileExists(atPath: coordinatedURL.path)
                    ? .unreadable : .notFound
                return
            }
            guard let text = String(bytes: data, encoding: .utf8) else {
                // 비-UTF8 → 빈 내용으로 오판해 그 달을 비우지 않도록 읽기 불가로 처리.
                outcome = .unreadable
                return
            }
            let modified = (try? coordinatedURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ))?.contentModificationDate
            outcome = .success(Content(text: text, hash: sha256Hex(data), modified: modified))
        }
        if coordinationError != nil { return .unreadable }
        return outcome
    }

    private static func triggerDownload(at url: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
