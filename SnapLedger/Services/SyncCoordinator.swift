import Foundation
import OSLog
import SwiftData

private let log = Logger(subsystem: "com.youngkyu.snapledger", category: "sync")

/// 외부 변경 감지 결과. 파일 삭제는 (사고 방지를 위해) 다루지 않는다.
struct DetectedChange: Equatable, Identifiable {
    enum Kind: Equatable { case modified, externalNew }
    let monthKey: String
    let kind: Kind
    var id: String { monthKey }
}

/// 파일 동기화 화면에서 보여줄 월별 상태.
struct MonthSyncStatus: Identifiable, Equatable {
    enum State: Equatable {
        case synced            // 앱·파일 일치
        case externalModified  // 앱·파일 둘 다 있는데 파일이 다름
        case fileOnly          // 파일에만 있음 (앱으로 가져오기 후보)
        case appOnly           // 앱에만 있음 (파일로 내보내기 후보)
        case notReady          // iCloud 다운로드 중
    }

    let monthKey: String
    let state: State
    var id: String { monthKey }

    var allowsImport: Bool {
        switch state {
        case .synced, .externalModified, .fileOnly: true
        case .appOnly, .notReady: false
        }
    }

    var allowsExport: Bool {
        switch state {
        case .synced, .externalModified, .appOnly: true
        case .fileOnly, .notReady: false
        }
    }
}

/// 저장 폴더 섹션에 요약해 보여줄 전체 동기화 상태.
enum FolderSyncSummary: Equatable {
    case empty                  // 아직 동기화할 데이터가 없음 → 아이콘 없음
    case synced                 // 모든 달이 최신
    case needsSync(count: Int)  // 맞춰야 할 달이 있음
    case folderMissing          // bookmark는 있으나 폴더가 삭제/이동돼 접근 불가
}

/// 월별 CSV 파일과 SwiftData(`SavedEntry`) 사이의 양방향 동기화를 오케스트레이션한다.
///
/// CSV 행에는 안정적 ID가 없으므로 동기화 단위는 **월 단위 통째 교체**다.
/// - 파일 → 앱(import): 그 달 CSV를 파싱해 그 달 `SavedEntry` 전체를 교체.
/// - 앱 → 파일(export): SwiftData 기준으로 그 달 CSV를 재기록.
/// 모든 쓰기/읽기 후 `CSVFileState` 지문을 갱신해 다음 변경 감지의 기준으로 삼는다.
@MainActor
struct SyncCoordinator {
    enum SyncError: Error, LocalizedError {
        case noCSVFolder
        case bookmarkResolveFailed(underlying: Error)
        case folderUnavailable

        var errorDescription: String? {
            switch self {
            case .noCSVFolder: "CSV 폴더가 설정되어 있지 않아요. 설정에서 폴더를 먼저 골라주세요."
            case .bookmarkResolveFailed(let err): "폴더 권한을 복구하지 못했어요: \(err.localizedDescription)"
            case .folderUnavailable:
                "저장 폴더를 찾을 수 없어요. 폴더가 삭제됐거나 이동했을 수 있어요. 설정 → 저장 폴더에서 다시 선택해 주세요."
            }
        }
    }

    struct ImportSummary: Equatable {
        var importedMonths: [String] = []
        var totalRows: Int = 0
        var skippedRows: Int = 0
        /// iCloud에서 아직 안 받아져 이번에 건너뛴 달 (다운로드는 트리거됨).
        var notReadyMonths: [String] = []
        /// 파일을 읽지 못해(권한·잠금·비-UTF8 등) 건너뛴 달 — 앱 데이터는 건드리지 않음.
        var unreadableMonths: [String] = []

        /// 사용자에게 보여줄 결과 요약 문구.
        var userMessage: String {
            var parts: [String] = []
            if importedMonths.isEmpty {
                parts.append("가져온 내용이 없어요.")
            } else {
                parts.append("\(CSVWriter.monthLabels(importedMonths)) \(totalRows)건을 가져왔어요.")
            }
            if skippedRows > 0 {
                parts.append("형식이 맞지 않는 \(skippedRows)줄은 건너뛰었어요.")
            }
            if !notReadyMonths.isEmpty {
                parts.append(
                    "아직 내려받는 중이라 건너뛴 달이 있어요: \(CSVWriter.monthLabels(notReadyMonths)). 잠시 후 다시 시도해 주세요."
                )
            }
            if !unreadableMonths.isEmpty {
                parts.append(
                    "파일을 읽지 못해 건너뛴 달이 있어요: \(CSVWriter.monthLabels(unreadableMonths))."
                )
            }
            return parts.joined(separator: " ")
        }

        /// 건너뛴 행/달이 있을 때만 사용자에게 보여줄 안내. 깨끗하면 nil (조용히 진행).
        var skipNotice: String? {
            guard skippedRows > 0 || !notReadyMonths.isEmpty || !unreadableMonths.isEmpty else {
                return nil
            }
            return userMessage
        }
    }

    /// 저장/수정/삭제 직전 충돌 검사 결과.
    enum WriteGuard: Equatable {
        case clear
        case conflict([String])
        case notReady([String])
    }

    // MARK: - 변경 감지 (자동, 비블로킹)

    /// 폴더의 월별 CSV를 스캔해 외부 변경된 달을 찾는다. 다운로드 안 된/읽지 못한 파일은 건너뛴다.
    /// 파일 해시 계산은 메인 액터 밖에서 수행한다 (런치/포그라운드 프레임을 막지 않도록).
    func detectChanges(in context: ModelContext) async -> [DetectedChange] {
        (try? await withFolderAsync(in: context) { folderURL in
            let readiness = await Self.scanReadiness(in: folderURL)
            let states = fileStatesByName(in: context)
            var changes: [DetectedChange] = []
            for (key, reading) in readiness {
                guard case .ready(let content) = reading else { continue }
                let name = CSVWriter.filename(forMonthKey: key)
                if let state = states[name] {
                    if state.lastSyncedHash != content.hash {
                        changes.append(DetectedChange(monthKey: key, kind: .modified))
                    }
                } else {
                    changes.append(DetectedChange(monthKey: key, kind: .externalNew))
                }
            }
            return changes.sorted { $0.monthKey > $1.monthKey }
        }) ?? []
    }

    /// 파일 동기화 화면용 — 앱에 있는 달 ∪ 폴더에 있는 달 각각의 동기화 상태.
    func monthStatuses(in context: ModelContext) async -> [MonthSyncStatus] {
        (try? await withFolderAsync(in: context) { folderURL in
            let readiness = await Self.scanReadiness(in: folderURL)
            let states = fileStatesByName(in: context)
            let allSaved = (try? context.fetch(FetchDescriptor<SavedEntry>())) ?? []
            let appMonths = Set(allSaved.map { CSVWriter.monthKey(for: $0.date) })

            let allKeys = appMonths.union(readiness.keys)
            return allKeys
                .map { key in
                    MonthSyncStatus(
                        monthKey: key,
                        state: monthState(
                            key: key,
                            readiness: readiness[key],
                            hasApp: appMonths.contains(key),
                            states: states
                        )
                    )
                }
                .sorted { $0.monthKey > $1.monthKey }
        }) ?? []
    }

    /// 저장 폴더 섹션 배지용 — 전체 동기화 상태 요약.
    func folderSyncSummary(in context: ModelContext) async -> FolderSyncSummary {
        switch isFolderReachable(in: context) {
        case .none:
            return .empty
        case .some(false):
            return .folderMissing
        case .some(true):
            let statuses = await monthStatuses(in: context)
            if statuses.isEmpty { return .empty }
            let pending = statuses.filter { $0.state != .synced }
            return pending.isEmpty ? .synced : .needsSync(count: pending.count)
        }
    }

    /// 저장 폴더에 실제 접근 가능한지. bookmark는 있으나 폴더가 삭제/이동된 경우 false.
    /// 폴더 미설정이면 nil.
    func isFolderReachable(in context: ModelContext) -> Bool? {
        guard let settings = try? fetchOrCreateSettings(in: context),
              let bookmark = settings.csvFolderBookmark else {
            return nil
        }
        guard let resolved = try? BookmarkStore.resolve(bookmark) else {
            return false
        }
        let url = resolved.url
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return BookmarkStore.isReachableDirectory(url)
    }

    private func monthState(
        key: String,
        readiness: FileFingerprint.Readiness?,
        hasApp: Bool,
        states: [String: CSVFileState]
    ) -> MonthSyncStatus.State {
        guard let readiness else { return .appOnly } // 파일 없음 + 앱에만 있음
        switch readiness {
        case .notDownloaded, .unreadable:
            // 내려받는 중이거나 읽지 못한 파일 — 상태를 확신할 수 없어 액션을 막는다.
            return .notReady
        case .missing:
            return hasApp ? .appOnly : .fileOnly
        case .ready(let content):
            let stateHash = states[CSVWriter.filename(forMonthKey: key)]?.lastSyncedHash
            if stateHash == content.hash {
                return hasApp ? .synced : .fileOnly
            }
            return hasApp ? .externalModified : .fileOnly
        }
    }

    // MARK: - 기존 사용자 마이그레이션

    /// 동기화 기능 도입 전부터 있던 파일들을 "외부 새 파일"로 오인하지 않도록
    /// 현재 지문을 baseline으로 한 번 기록한다. 이미 했으면 아무것도 안 한다.
    func establishBaselineIfNeeded(in context: ModelContext) {
        let settings = try? fetchOrCreateSettings(in: context)
        guard let settings, !settings.hasSyncBaseline else { return }
        do {
            try withFolder(in: context) { folderURL, ctx in
                for (key, url) in Self.monthCSVFiles(in: folderURL) {
                    guard case .ready(let content) = FileFingerprint.read(at: url) else { continue }
                    upsertFileState(
                        filename: CSVWriter.filename(forMonthKey: key),
                        hash: content.hash,
                        modified: content.modified,
                        in: ctx
                    )
                }
            }
            settings.hasSyncBaseline = true
            try? context.save()
        } catch {
            // 폴더 미설정 등 — baseline은 폴더가 준비된 뒤 다음 진입에서 재시도한다.
            log.info("baseline deferred: \(String(describing: error))")
        }
    }

    // MARK: - Import (파일 → 앱)

    @discardableResult
    func importMonths(_ keys: [String], in context: ModelContext) throws -> ImportSummary {
        try withFolder(in: context) { folderURL, ctx in
            var summary = ImportSummary()
            for key in keys {
                let url = folderURL.appendingPathComponent(CSVWriter.filename(forMonthKey: key))
                switch FileFingerprint.read(at: url) {
                case .ready(let content):
                    let parsed = CSVRowParser.parse(content.text)
                    replaceMonthEntries(monthKey: key, rows: parsed.rows, in: ctx)
                    upsertFileState(
                        filename: CSVWriter.filename(forMonthKey: key),
                        hash: content.hash,
                        modified: content.modified,
                        in: ctx
                    )
                    summary.importedMonths.append(key)
                    summary.totalRows += parsed.rows.count
                    summary.skippedRows += parsed.skipped
                case .notDownloaded:
                    summary.notReadyMonths.append(key)
                case .unreadable:
                    // 읽기 실패를 "빈 파일"로 오판해 그 달을 비우면 데이터 손실이므로 건너뛴다.
                    summary.unreadableMonths.append(key)
                case .missing:
                    // 파일이 없으면 그 달을 비운다 (외부에서 비워졌다고 보고 앱도 맞춤).
                    replaceMonthEntries(monthKey: key, rows: [], in: ctx)
                    removeFileState(filename: CSVWriter.filename(forMonthKey: key), in: ctx)
                    summary.importedMonths.append(key)
                }
            }
            try ctx.save()
            return summary
        }
    }

    @discardableResult
    func importAll(in context: ModelContext) throws -> ImportSummary {
        let keys = try withFolder(in: context) { folderURL, _ in
            Self.monthCSVFiles(in: folderURL).map(\.key)
        }
        return try importMonths(keys, in: context)
    }

    // MARK: - Export (앱 → 파일)

    func exportMonths(_ keys: [String], in context: ModelContext) throws {
        try withFolder(in: context) { folderURL, ctx in
            try exportMonths(keys, folderURL: folderURL, in: ctx)
            try ctx.save()
        }
    }

    func exportAll(in context: ModelContext) throws {
        let all = (try? context.fetch(FetchDescriptor<SavedEntry>())) ?? []
        let keys = Array(Set(all.map { CSVWriter.monthKey(for: $0.date) }))
        try exportMonths(keys, in: context)
    }

    /// 폴더를 이미 연 호출자(`SaveCoordinator`)용. security scope를 새로 열지 않는다.
    func exportMonths(_ keys: [String], folderURL: URL, in context: ModelContext) throws {
        let writer = CSVWriter(folder: folderURL)
        let allSaved = (try? context.fetch(FetchDescriptor<SavedEntry>())) ?? []
        for key in keys {
            let rows = allSaved
                .filter { CSVWriter.monthKey(for: $0.date) == key }
                .sorted { $0.savedAt < $1.savedAt }
                .map {
                    SavedRow(
                        date: $0.date,
                        description: $0.merchant,
                        category: $0.category,
                        amount: $0.amount,
                        note: $0.note
                    )
                }
            try writer.replaceMonth(monthKey: key, rows: rows)
            refreshFileState(monthKey: key, folderURL: folderURL, in: context)
        }
    }

    // MARK: - 쓰기 전 충돌 검사

    /// 폴더를 이미 연 호출자(`SaveCoordinator`)용. 대상 달들에 외부 변경이 있는지 본다.
    func checkWriteGuard(
        monthKeys: [String],
        folderURL: URL,
        in context: ModelContext
    ) -> WriteGuard {
        let states = fileStatesByName(in: context)
        var conflicts: [String] = []
        var notReady: [String] = []
        for key in monthKeys {
            let name = CSVWriter.filename(forMonthKey: key)
            let url = folderURL.appendingPathComponent(name)
            switch FileFingerprint.read(at: url) {
            case .notDownloaded, .unreadable:
                // 읽지 못한 파일은 변경 여부를 확신할 수 없으므로 쓰기를 막고 재시도를 유도한다.
                notReady.append(key)
            case .missing:
                continue
            case .ready(let content):
                if let state = states[name] {
                    if state.lastSyncedHash != content.hash { conflicts.append(key) }
                } else {
                    conflicts.append(key)
                }
            }
        }
        if !notReady.isEmpty { return .notReady(notReady) }
        if !conflicts.isEmpty { return .conflict(conflicts) }
        return .clear
    }

    /// 폴더를 이미 연 호출자(`SaveCoordinator`)용. 쓰기 후 지문 갱신.
    func refreshFileState(monthKey key: String, folderURL: URL, in context: ModelContext) {
        let name = CSVWriter.filename(forMonthKey: key)
        let url = folderURL.appendingPathComponent(name)
        switch FileFingerprint.read(at: url) {
        case .ready(let content):
            upsertFileState(filename: name, hash: content.hash, modified: content.modified, in: context)
        case .missing:
            // 행이 비어 파일을 지운 경우 — 지문도 제거.
            removeFileState(filename: name, in: context)
        case .notDownloaded, .unreadable:
            // 방금 쓴 파일을 일시적으로 못 읽은 경우 — 기존 지문을 유지한다 (잘못된 변경 감지 방지).
            break
        }
    }

    /// 폴더 변경 시 호출 — 이전 폴더 기준 지문을 모두 비우고 baseline을 리셋.
    func resetSyncState(in context: ModelContext) {
        let states = (try? context.fetch(FetchDescriptor<CSVFileState>())) ?? []
        for state in states { context.delete(state) }
        if let settings = try? fetchOrCreateSettings(in: context) {
            settings.hasSyncBaseline = false
        }
        try? context.save()
    }
}

// MARK: - 내부 헬퍼

extension SyncCoordinator {
    private func replaceMonthEntries(monthKey key: String, rows: [SavedRow], in context: ModelContext) {
        let filename = CSVWriter.filename(forMonthKey: key)
        let all = (try? context.fetch(FetchDescriptor<SavedEntry>())) ?? []
        for entry in all where CSVWriter.monthKey(for: entry.date) == key {
            context.delete(entry)
        }
        // 행 순서를 보존하기 위해 savedAt을 행 순서대로 증가시켜 부여 (재export 시 동일 순서).
        let base = Date()
        for (index, row) in rows.enumerated() {
            context.insert(
                SavedEntry(
                    date: row.date,
                    amount: row.amount,
                    merchant: row.description,
                    category: row.category,
                    note: row.note,
                    savedAt: base.addingTimeInterval(Double(index)),
                    csvFile: filename
                )
            )
        }
    }

    private func fileStatesByName(in context: ModelContext) -> [String: CSVFileState] {
        let states = (try? context.fetch(FetchDescriptor<CSVFileState>())) ?? []
        return Dictionary(states.map { ($0.filename, $0) }) { first, _ in first }
    }

    private func upsertFileState(
        filename: String,
        hash: String,
        modified: Date?,
        in context: ModelContext
    ) {
        let states = (try? context.fetch(FetchDescriptor<CSVFileState>())) ?? []
        if let existing = states.first(where: { $0.filename == filename }) {
            existing.lastSyncedHash = hash
            existing.lastSyncedModified = modified
            existing.lastSyncedAt = Date()
        } else {
            context.insert(
                CSVFileState(filename: filename, lastSyncedHash: hash, lastSyncedModified: modified)
            )
        }
    }

    private func removeFileState(filename: String, in context: ModelContext) {
        let states = (try? context.fetch(FetchDescriptor<CSVFileState>())) ?? []
        for state in states where state.filename == filename {
            context.delete(state)
        }
    }

    /// 폴더의 월별 CSV 파일 목록. 파일 I/O라 메인 액터 밖에서도 쓸 수 있게 `nonisolated`.
    nonisolated static func monthCSVFiles(in folderURL: URL) -> [(key: String, url: URL)] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }
        return entries.compactMap { url in
            monthKey(fromFilename: url.lastPathComponent).map { ($0, url) }
        }
    }

    /// 폴더의 월별 CSV를 스캔해 `monthKey → Readiness` 맵을 만든다.
    /// `nonisolated async` 라 메인 액터에서 `await` 호출 시 파일 해시 계산이 백그라운드에서 돈다.
    nonisolated static func scanReadiness(in folderURL: URL) async -> [String: FileFingerprint.Readiness] {
        var out: [String: FileFingerprint.Readiness] = [:]
        for (key, url) in monthCSVFiles(in: folderURL) {
            out[key] = FileFingerprint.read(at: url)
        }
        return out
    }

    /// `expenses-2026-05.csv` → `2026-05`. 패턴이 안 맞으면 nil.
    nonisolated static func monthKey(fromFilename name: String) -> String? {
        guard name.hasPrefix("expenses-"), name.hasSuffix(".csv") else { return nil }
        let mid = String(name.dropFirst("expenses-".count).dropLast(".csv".count))
        let parts = mid.split(separator: "-")
        guard parts.count == 2,
              parts[0].count == 4, Int(parts[0]) != nil,
              parts[1].count == 2, Int(parts[1]) != nil else {
            return nil
        }
        return mid
    }

    private func withFolder<T>(
        in context: ModelContext,
        _ body: (URL, ModelContext) throws -> T
    ) throws -> T {
        let settings = try fetchOrCreateSettings(in: context)
        guard let bookmark = settings.csvFolderBookmark else {
            throw SyncError.noCSVFolder
        }
        let resolved: (url: URL, isStale: Bool)
        do {
            resolved = try BookmarkStore.resolve(bookmark)
        } catch {
            throw SyncError.bookmarkResolveFailed(underlying: error)
        }
        let folderURL = resolved.url
        let didStart = folderURL.startAccessingSecurityScopedResource()
        defer { if didStart { folderURL.stopAccessingSecurityScopedResource() } }

        guard BookmarkStore.isReachableDirectory(folderURL) else {
            throw SyncError.folderUnavailable
        }

        let result = try body(folderURL, context)

        if resolved.isStale, let refreshed = try? BookmarkStore.makeBookmark(for: folderURL) {
            settings.csvFolderBookmark = refreshed
            try? context.save()
        }
        return result
    }

    /// `withFolder`의 async 버전. body 안에서 `await`(예: 백그라운드 파일 스캔)할 수 있다.
    /// security-scoped 접근은 프로세스 전역이라 await 동안에도 유지된다 (defer로 종료).
    private func withFolderAsync<T>(
        in context: ModelContext,
        _ body: (URL) async throws -> T
    ) async throws -> T {
        let settings = try fetchOrCreateSettings(in: context)
        guard let bookmark = settings.csvFolderBookmark else {
            throw SyncError.noCSVFolder
        }
        let resolved: (url: URL, isStale: Bool)
        do {
            resolved = try BookmarkStore.resolve(bookmark)
        } catch {
            throw SyncError.bookmarkResolveFailed(underlying: error)
        }
        let folderURL = resolved.url
        let didStart = folderURL.startAccessingSecurityScopedResource()
        defer { if didStart { folderURL.stopAccessingSecurityScopedResource() } }

        guard BookmarkStore.isReachableDirectory(folderURL) else {
            throw SyncError.folderUnavailable
        }

        let result = try await body(folderURL)

        if resolved.isStale, let refreshed = try? BookmarkStore.makeBookmark(for: folderURL) {
            settings.csvFolderBookmark = refreshed
            try? context.save()
        }
        return result
    }

    private func fetchOrCreateSettings(in context: ModelContext) throws -> AppSettings {
        let existing = try context.fetch(FetchDescriptor<AppSettings>())
        if let first = existing.first { return first }
        let new = AppSettings()
        context.insert(new)
        try context.save()
        return new
    }
}
