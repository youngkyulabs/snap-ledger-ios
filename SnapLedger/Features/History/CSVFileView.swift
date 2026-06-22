import SwiftUI
import SwiftData
import UIKit

struct CSVFileView: View {
    let csvFilename: String
    let monthTitle: String

    @Query private var settingsList: [AppSettings]
    @State private var rows: [[String]]?
    @State private var shareableURL: URL?
    @State private var loadError: String?
    @State private var copiedFlash = false
    @State private var isSelecting = false
    @State private var selectedRowIndices: Set<Int> = []

    var body: some View {
        Group {
            if let rows {
                if rows.count <= 1 {
                    ContentUnavailableView(
                        "기록 없음",
                        systemImage: "tablecells",
                        description: Text("이 달에는 아직 항목이 없어요.")
                    )
                } else {
                    tableView(rows: rows)
                }
            } else if let loadError {
                ContentUnavailableView(
                    "파일 열기 실패",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle(monthTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        isSelecting = false
                        selectedRowIndices = []
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        copySelected(rows: rows ?? [])
                    } label: {
                        Text("복사 (\(selectedRowIndices.count))")
                    }
                    .disabled(selectedRowIndices.isEmpty)
                }
            } else {
                if let rows, rows.count > 1 {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isSelecting = true
                            selectedRowIndices = []
                        } label: {
                            Image(systemName: "checkmark.circle")
                                .accessibilityLabel("선택")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            copyAll(rows: rows)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .accessibilityLabel("전체 복사")
                        }
                    }
                }
                if let shareableURL {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: shareableURL) {
                            Image(systemName: "square.and.arrow.up")
                                .accessibilityLabel("CSV 파일 공유")
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: copiedFlash)
        .task { load() }
    }

    private func tableView(rows: [[String]]) -> some View {
        let header = rows[0]
        let body = Array(rows.dropFirst())
        let columnCount = header.count + (isSelecting ? 1 : 0)

        return ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 0) {
                GridRow {
                    if isSelecting {
                        Color.clear.frame(width: 22, height: 1)
                    }
                    ForEach(header.indices, id: \.self) { col in
                        Text(header[col])
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(alignment(col: col, header: header))
                    }
                }
                .padding(.vertical, 8)

                Divider().gridCellColumns(columnCount)

                ForEach(body.indices, id: \.self) { rowIdx in
                    let row = body[rowIdx]
                    let isSelected = selectedRowIndices.contains(rowIdx)
                    GridRow {
                        if isSelecting {
                            Image(systemName: isSelected
                                ? "checkmark.circle.fill"
                                : "circle")
                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                .accessibilityLabel(isSelected ? "선택됨" : "선택되지 않음")
                                .onTapGesture { toggleSelection(rowIdx) }
                        }
                        ForEach(header.indices, id: \.self) { col in
                            let value = col < row.count ? row[col] : ""
                            cellText(value, col: col, header: header)
                                .contentShape(.rect)
                                .onTapGesture {
                                    if isSelecting { toggleSelection(rowIdx) }
                                }
                                .contextMenu {
                                    if !isSelecting {
                                        Button {
                                            copyRow(row)
                                        } label: {
                                            Label("이 행 복사", systemImage: "doc.on.doc")
                                        }
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 6)

                    if rowIdx < body.count - 1 {
                        Divider().gridCellColumns(columnCount)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }

    private func toggleSelection(_ rowIdx: Int) {
        if selectedRowIndices.contains(rowIdx) {
            selectedRowIndices.remove(rowIdx)
        } else {
            selectedRowIndices.insert(rowIdx)
        }
    }

    private func copySelected(rows: [[String]]) {
        let body = Array(rows.dropFirst())
        let selected = selectedRowIndices
            .sorted()
            .compactMap { idx -> [String]? in
                idx < body.count ? body[idx] : nil
            }
        guard !selected.isEmpty else { return }
        writeToPasteboard(
            tableHTML: ClipboardExporter.html(rows: selected, hasHeader: false),
            tsv: ClipboardExporter.tsv(rows: selected)
        )
        copiedFlash.toggle()
        isSelecting = false
        selectedRowIndices = []
    }

    @ViewBuilder
    private func cellText(_ value: String, col: Int, header: [String]) -> some View {
        if isAmountColumn(col: col, header: header) {
            Text(formatAmount(value))
                .font(.callout.monospacedDigit())
        } else {
            Text(value)
                .font(.callout)
        }
    }

    private func alignment(col: Int, header: [String]) -> HorizontalAlignment {
        isAmountColumn(col: col, header: header) ? .trailing : .leading
    }

    private func isAmountColumn(col: Int, header: [String]) -> Bool {
        col < header.count && header[col] == "금액"
    }

    private func formatAmount(_ raw: String) -> String {
        if let n = Int(raw) {
            return n.formatted(.number)
        }
        return raw
    }

    private func copyAll(rows: [[String]]) {
        writeToPasteboard(
            tableHTML: ClipboardExporter.html(rows: rows, hasHeader: true),
            tsv: ClipboardExporter.tsv(rows: rows)
        )
        copiedFlash.toggle()
    }

    private func copyRow(_ row: [String]) {
        writeToPasteboard(
            tableHTML: ClipboardExporter.html(rows: [row], hasHeader: false),
            tsv: ClipboardExporter.tsv(rows: [row])
        )
        copiedFlash.toggle()
    }

    private func writeToPasteboard(tableHTML: String, tsv: String) {
        let fullHTML = #"<!DOCTYPE html><html><head><meta charset="utf-8"></head><body>"# +
            tableHTML +
            "</body></html>"
        let item: [String: Any] = [
            "public.html": Data(fullHTML.utf8),
            "public.utf8-plain-text": Data(tsv.utf8),
        ]
        UIPasteboard.general.items = [item]
    }

    private func load() {
        guard let bookmark = settingsList.first?.csvFolderBookmark else {
            loadError = "저장 폴더가 설정되어 있지 않아요. 설정에서 폴더를 먼저 선택해 주세요."
            return
        }
        do {
            let resolved = try BookmarkStore.resolve(bookmark)
            let folderURL = resolved.url
            let didStart = folderURL.startAccessingSecurityScopedResource()
            defer { if didStart { folderURL.stopAccessingSecurityScopedResource() } }

            let sourceURL = folderURL.appendingPathComponent(csvFilename)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                loadError = "아직 \(csvFilename) 파일이 없어요."
                return
            }
            let content = try String(contentsOf: sourceURL, encoding: .utf8)
            rows = CSVParser.parse(content)

            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(csvFilename)
            try? FileManager.default.removeItem(at: tmpURL)
            try FileManager.default.copyItem(at: sourceURL, to: tmpURL)
            shareableURL = tmpURL
        } catch {
            loadError = error.localizedDescription
        }
    }
}
