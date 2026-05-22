import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Bindable var settings: AppSettings
    let onComplete: () -> Void

    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            OnboardingValuePage()
                .tag(0)
            OnboardingSetupPage(settings: settings, onComplete: onComplete)
                .tag(1)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }
}
