import SwiftData
import SwiftUI

/// 저장/수정/삭제 도중 대상 월 파일이 앱 밖에서 변경됐을 때의 해소 컨텍스트.
struct SyncConflict: Identifiable {
    enum Mode { case afterImport, overwrite }

    let id = UUID()
    let months: [String]
    /// 추가(저장)처럼 작업이 가산적이라 "덮어쓰기"가 의미 없을 때 false.
    var allowOverwrite: Bool = true
    /// 가져오기가 진행 중인 편집을 대체(폐기)하는 경우 true (수정·삭제).
    /// false면 가져온 뒤 작업이 그대로 이어진다 (저장=추가). 버튼 문구/안내가 달라진다.
    var importDiscardsEdit: Bool = false
    /// 사용자가 해소 방법을 고른 뒤 실제 작업을 마무리한다.
    let perform: (Mode) -> Void
}

extension View {
    /// 외부 변경 충돌을 만나면 [가져오기/덮어쓰기/취소] 다이얼로그로 해소한다.
    func syncConflictAlert(_ conflict: Binding<SyncConflict?>) -> some View {
        modifier(SyncConflictAlertModifier(conflict: conflict))
    }
}

private struct SyncConflictAlertModifier: ViewModifier {
    @Binding var conflict: SyncConflict?
    @Environment(\.modelContext) private var modelContext
    @State private var notice: String?
    /// 가져오기 안내(건너뛴 행 등)를 확인한 뒤 이어서 실행할 작업. nil이면 그냥 닫는다.
    @State private var proceedAfterNotice: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "파일이 앱 밖에서 바뀌었어요",
                isPresented: Binding(
                    get: { conflict != nil },
                    set: { if !$0 { conflict = nil } }
                ),
                titleVisibility: .visible,
                presenting: conflict
            ) { conflict in
                Button(importButtonTitle(for: conflict)) { importThenPerform(conflict) }
                if conflict.allowOverwrite {
                    Button("앱 내용으로 덮어쓰기", role: .destructive) {
                        conflict.perform(.overwrite)
                        self.conflict = nil
                    }
                }
                Button("취소", role: .cancel) { self.conflict = nil }
            } message: { conflict in
                Text(dialogMessage(for: conflict))
            }
            .alert(
                "가져오기",
                isPresented: Binding(
                    get: { notice != nil },
                    set: { if !$0 { notice = nil } }
                ),
                presenting: notice
            ) { _ in
                Button("확인", role: .cancel) {
                    let proceed = proceedAfterNotice
                    proceedAfterNotice = nil
                    notice = nil
                    proceed?()
                }
            } message: { message in
                Text(message)
            }
    }

    private func importButtonTitle(for conflict: SyncConflict) -> String {
        // 수정·삭제는 가져오면 진행 중 편집이 버려지므로 "진행" 대신 명확히 표기.
        conflict.importDiscardsEdit ? "파일 내용으로 맞추기" : "파일 내용 가져온 뒤 진행"
    }

    private func dialogMessage(for conflict: SyncConflict) -> String {
        let months = conflict.months.joined(separator: ", ")
        if conflict.importDiscardsEdit {
            return "\(months) 파일이 앱 밖에서 바뀌었어요. ‘파일 내용으로 맞추기’를 누르면 "
                + "이번 변경은 취소되고 파일 내용으로 맞춰져요."
        }
        return "\(months) 파일이 앱 밖에서 바뀌었어요. 어떻게 할까요?"
    }

    private func importThenPerform(_ conflict: SyncConflict) {
        self.conflict = nil
        do {
            let summary = try SyncCoordinator().importMonths(conflict.months, in: modelContext)
            if let info = summary.skipNotice {
                // 건너뛴 행/달이 있으면 먼저 알리고, 확인을 누르면 이어서 진행한다.
                proceedAfterNotice = { conflict.perform(.afterImport) }
                notice = info
            } else {
                conflict.perform(.afterImport)
            }
        } catch {
            // 가져오기 실패 시에는 작업을 진행하지 않는다 (확인만 누르면 닫힘).
            notice = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
