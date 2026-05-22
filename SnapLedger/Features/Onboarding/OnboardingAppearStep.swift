import SwiftUI

private struct AppearStepModifier: ViewModifier {
    let stage: Int
    let current: Int

    func body(content: Content) -> some View {
        content
            .opacity(current >= stage ? 1 : 0)
            .offset(y: current >= stage ? 0 : -16)
    }
}

extension View {
    func appearStep(_ stage: Int, current: Int) -> some View {
        modifier(AppearStepModifier(stage: stage, current: current))
    }
}

enum OnboardingAppearStep {
    static let totalStages = 4
    static let stepInterval: Duration = .milliseconds(100)
    static let stepAnimation: Animation = .smooth(duration: 0.4)

    static func run(setStep: @escaping @MainActor (Int) -> Void) async {
        for stage in 1...totalStages {
            try? await Task.sleep(for: stepInterval)
            await MainActor.run {
                withAnimation(stepAnimation) {
                    setStep(stage)
                }
            }
        }
    }
}
