import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var settings: AppSettings
    let onComplete: () -> Void

    @State private var selection = 0

    private var isOnFirstPage: Bool { selection == 0 }
    private var canProceed: Bool { settings.csvFolderBookmark != nil }
    private var primaryEnabled: Bool { isOnFirstPage || canProceed }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                OnboardingValuePage()
                    .tag(0)
                OnboardingSetupPage(settings: settings, isVisible: selection == 1)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            bottomBar
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if !isOnFirstPage && !canProceed {
                Text("폴더를 먼저 선택해주세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Button(action: primaryAction) {
                Text(isOnFirstPage ? "다음" : "시작하기")
                    .frame(maxWidth: .infinity)
                    .font(.headline)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!primaryEnabled)
            .padding(.horizontal)
        }
        .padding(.bottom, 16)
        .animation(.smooth(duration: 0.25), value: selection)
        .animation(.smooth(duration: 0.25), value: canProceed)
    }

    private func primaryAction() {
        if isOnFirstPage {
            withAnimation(.smooth) { selection = 1 }
        } else {
            settings.hasCompletedOnboarding = true
            try? modelContext.save()
            onComplete()
        }
    }
}
