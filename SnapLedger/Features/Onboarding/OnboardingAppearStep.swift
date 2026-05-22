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
    static let defaultStages = 4
    static let initialDelay: Duration = .milliseconds(300)
    static let stepInterval: Duration = .milliseconds(100)
    static let stepAnimation: Animation = .smooth(duration: 0.4)

    static func run(
        stages: Int = defaultStages,
        setStep: @escaping @MainActor (Int) -> Void
    ) async {
        try? await Task.sleep(for: initialDelay)
        for stage in 1...stages {
            await MainActor.run {
                withAnimation(stepAnimation) {
                    setStep(stage)
                }
            }
            try? await Task.sleep(for: stepInterval)
        }
    }
}
