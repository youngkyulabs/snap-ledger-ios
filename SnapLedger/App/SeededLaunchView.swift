#if DEBUG
import SwiftUI
import SwiftData

/// Seeds sample data before showing the app, so onboarding never appears in screenshot runs.
struct SeededLaunchView: View {
    private enum Phase {
        case seeding
        case ready
        case blocked
    }

    @Environment(\.modelContext) private var modelContext
    @State private var phase = Phase.seeding

    var body: some View {
        switch phase {
        case .seeding:
            ProgressView()
                .task {
                    phase = await SampleDataLaunchSeeding.run(in: modelContext) ? .ready : .blocked
                }
        case .ready:
            ContentView()
        case .blocked:
            ContentUnavailableView(
                "샘플 데이터를 채우지 못했어요",
                systemImage: "exclamationmark.icloud",
                description: Text("iCloud 로그아웃 상태의 시뮬레이터에서 실행하세요.")
            )
        }
    }
}
#endif
