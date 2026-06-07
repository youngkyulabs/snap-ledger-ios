import Foundation

extension SyncCoordinator {
    /// 폴더의 월별 CSV 파일 목록. 파일 I/O라 메인 액터 밖에서도 쓸 수 있게 `nonisolated`.
    nonisolated static func monthCSVFiles(in folderURL: URL) -> [(key: String, url: URL)] {
        syncCSVFiles(in: folderURL)
            .compactMap { file in
                identity(file.identity, matches: .expenses).map { ($0, file.url) }
            }
    }

    /// 폴더의 모든 동기화 대상 CSV 파일 목록. 파일 I/O라 메인 액터 밖에서도 쓸 수 있게 `nonisolated`.
    nonisolated static func syncCSVFiles(in folderURL: URL) -> [(identity: String, url: URL)] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }
        return entries.compactMap { url in
            SyncFileKind.fileKindAndMonthKey(fromFilename: url.lastPathComponent).map {
                (identity(kind: $0.kind, monthKey: $0.key), url)
            }
        }
    }

    /// 폴더의 월별 CSV를 스캔해 `monthKey → Readiness` 맵을 만든다.
    /// `nonisolated async` 라 메인 액터에서 `await` 호출 시 파일 해시 계산이 백그라운드에서 돈다.
    nonisolated static func scanReadiness(
        in folderURL: URL,
        kind: SyncFileKind
    ) async -> [String: FileFingerprint.Readiness] {
        var out: [String: FileFingerprint.Readiness] = [:]
        for file in syncCSVFiles(in: folderURL) {
            guard let key = identity(file.identity, matches: kind) else { continue }
            out[key] = FileFingerprint.read(at: file.url)
        }
        return out
    }

    /// 폴더의 모든 월별 CSV를 스캔해 `파일 종류+월 → Readiness` 맵을 만든다.
    /// `nonisolated async` 라 메인 액터에서 `await` 호출 시 파일 해시 계산이 백그라운드에서 돈다.
    nonisolated static func scanAllReadiness(
        in folderURL: URL
    ) async -> [String: FileFingerprint.Readiness] {
        var out: [String: FileFingerprint.Readiness] = [:]
        for file in syncCSVFiles(in: folderURL) {
            out[file.identity] = FileFingerprint.read(at: file.url)
        }
        return out
    }

    /// `expenses-2026-05.csv` → `2026-05`. 패턴이 안 맞으면 nil.
    nonisolated static func monthKey(fromFilename name: String) -> String? {
        CSVWriter.monthKey(fromFilename: name, prefix: "expenses-")
    }

    nonisolated static func intMonthKey(from key: String) -> Int {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else {
            return 0
        }
        return year * 100 + month
    }

    nonisolated static func monthKeyString(from key: Int) -> String {
        String(format: "%04d-%02d", key / 100, key % 100)
    }

    nonisolated static func identity(kind: SyncFileKind, monthKey: String) -> String {
        "\(kind.rawValue)|\(monthKey)"
    }

    nonisolated static func identity(_ value: String, matches kind: SyncFileKind) -> String? {
        let prefix = "\(kind.rawValue)|"
        guard value.hasPrefix(prefix) else { return nil }
        return String(value.dropFirst(prefix.count))
    }

    nonisolated static func identityParts(_ value: String) -> (kind: SyncFileKind, monthKey: String)? {
        for kind in [SyncFileKind.expenses, .reconciliation] {
            if let monthKey = identity(value, matches: kind) {
                return (kind, monthKey)
            }
        }
        return nil
    }
}
