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

        var errorDescription: String? {
            switch self {
            case .noCSVFolder: "CSV 폴더가 설정되어 있지 않아요. 설정에서 폴더를 먼저 골라주세요."
            case .bookmarkResolveFailed(let err): "폴더 권한을 복구하지 못했어요: \(err.localizedDescription)"
            }
        }
    }

    struct ImportSummary: Equatable {
        var importedMonths: [String] = []
        var totalRows: Int = 0
        var skippedRows: Int = 0
        /// iCloud에서 아직 안 받아져 이번에 건너뛴 달 (다운로드는 트리거됨).
        var notReadyMonths: [String] = []

        /// 사용자에게 보여줄 결과 요약 문구.
        var userMessage: String {
            var parts = ["\(importedMonths.count)개 월, \(totalRows)건 가져왔어요."]
            if skippedRows > 0 {
                parts.append("형식이 맞지 않는 \(skippedRows)행은 건너뛰었어요.")
            }
            if !notReadyMonths.isEmpty {
                parts.append(
                    "\(notReadyMonths.joined(separator: ", "))은(는) 아직 받아오는 중이라 잠시 후 다시 시도해 주세요."
                )
            }
            return parts.joined(separator: " ")
        }
    }

    /// 저장/수정/삭제 직전 충돌 검사 결과.
    enum WriteGuard: Equatable {
        case clear
        case conflict([String])
        case notReady([String])
    }

    // MARK: - 변경 감지 (자동, 비블로킹)

    /// 폴더의 월별 CSV를 스캔해 외부 변경된 달을 찾는다. 다운로드 안 된 파일은 건너뛴다.
    func detectChanges(in context: ModelContext) -> [DetectedChange] {
        (try? withFolder(in: context) { folderURL, ctx in
            let states = fileStatesByName(in: ctx)
            var changes: [DetectedChange] = []
            for (key, url) in monthCSVFiles(in: folderURL) {
                guard case .ready(let content) = FileFingerprint.read(at: url) else { continue }
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
    func monthStatuses(in context: ModelContext) -> [MonthSyncStatus] {
        (try? withFolder(in: context) { folderURL, ctx in
            let states = fileStatesByName(in: ctx)
            let allSaved = (try? ctx.fetch(FetchDescriptor<SavedEntry>())) ?? []
            let appMonths = Set(allSaved.map { CSVWriter.monthKey(for: $0.date) })
            let files = monthCSVFiles(in: folderURL)
            let urlByKey = Dictionary(files.map { ($0.key, $0.url) }) { first, _ in first }

            let allKeys = appMonths.union(files.map(\.key))
            return allKeys
                .map { key in
                    MonthSyncStatus(
                        monthKey: key,
                        state: monthState(
                            key: key,
                            url: urlByKey[key],
                            hasApp: appMonths.contains(key),
                            states: states
                        )
                    )
                }
                .sorted { $0.monthKey > $1.monthKey }
        }) ?? []
    }

    private func monthState(
        key: String,
        url: URL?,
        hasApp: Bool,
        states: [String: CSVFileState]
    ) -> MonthSyncStatus.State {
        guard let url else { return .appOnly } // 파일 없음 + 앱에만 있음
        switch FileFingerprint.read(at: url) {
        case .notDownloaded:
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
                for (key, url) in monthCSVFiles(in: folderURL) {
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
            monthCSVFiles(in: folderURL).map(\.key)
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
            case .notDownloaded:
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
        if case .ready(let content) = FileFingerprint.read(at: url) {
            upsertFileState(filename: name, hash: content.hash, modified: content.modified, in: context)
        } else {
            removeFileState(filename: name, in: context)
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

    // MARK: - 내부 헬퍼

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

    private func monthCSVFiles(in folderURL: URL) -> [(key: String, url: URL)] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }
        return entries.compactMap { url in
            Self.monthKey(fromFilename: url.lastPathComponent).map { ($0, url) }
        }
    }

    /// `expenses-2026-05.csv` → `2026-05`. 패턴이 안 맞으면 nil.
    static func monthKey(fromFilename name: String) -> String? {
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

        let result = try body(folderURL, context)

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
