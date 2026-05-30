import SwiftData
import SwiftUI

/// 저장/수정/삭제 도중 대상 월 파일이 앱 밖에서 변경됐을 때의 해소 컨텍스트.
struct SyncConflict: Identifiable {
    enum Mode { case afterImport, overwrite }

    let id = UUID()
    let months: [String]
    /// 추가(저장)처럼 작업이 가산적이라 "덮어쓰기"가 의미 없을 때 false.
    var allowOverwrite: Bool = true
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
    @State private var importError: String?

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
                Button("파일 내용 가져온 뒤 진행") { importThenPerform(conflict) }
                if conflict.allowOverwrite {
                    Button("앱 내용으로 덮어쓰기", role: .destructive) {
                        conflict.perform(.overwrite)
                        self.conflict = nil
                    }
                }
                Button("취소", role: .cancel) { self.conflict = nil }
            } message: { conflict in
                Text("\(conflict.months.joined(separator: ", ")) 파일이 앱 밖에서 바뀌었어요. 어떻게 할까요?")
            }
            .alert(
                "가져오기 실패",
                isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                ),
                presenting: importError
            ) { _ in
                Button("확인", role: .cancel) { importError = nil }
            } message: { message in
                Text(message)
            }
    }

    private func importThenPerform(_ conflict: SyncConflict) {
        do {
            try SyncCoordinator().importMonths(conflict.months, in: modelContext)
            conflict.perform(.afterImport)
        } catch {
            importError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        self.conflict = nil
    }
}
