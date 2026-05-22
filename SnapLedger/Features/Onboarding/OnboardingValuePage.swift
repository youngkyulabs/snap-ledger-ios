import SwiftUI

struct OnboardingValuePage: View {
    @State private var isAIAvailable = false
    @State private var step = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .appearStep(1, current: step)

            VStack(spacing: 12) {
                Text("결제 알림을 자동으로 가계부에")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text("스크린샷이나 영수증을 공유 시트로 보내면 Apple Intelligence가 자동으로 분류해요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .appearStep(2, current: step)

            availabilityBadge
                .appearStep(3, current: step)
            Spacer()
            Spacer()
        }
        .padding(.horizontal)
        .onAppear {
            isAIAvailable = FoundationModelsExtractionService.isAvailable
        }
        .task {
            guard step == 0 else { return }
            await OnboardingAppearStep.run(stages: 3) { step = $0 }
        }
    }

    private var availabilityBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: isAIAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isAIAvailable ? .green : .orange)
            Text(isAIAvailable
                 ? "Apple Intelligence 사용 가능"
                 : "설정 → Apple Intelligence에서 활성화 필요")
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
    }
}

#Preview {
    OnboardingValuePage()
}
