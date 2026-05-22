import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Bindable var settings: AppSettings
    let onComplete: () -> Void

    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            OnboardingValuePage(onNext: goToSetup)
                .tag(0)
            OnboardingSetupPage(settings: settings, isVisible: selection == 1, onComplete: onComplete)
                .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func goToSetup() {
        withAnimation(.smooth) { selection = 1 }
    }
}
