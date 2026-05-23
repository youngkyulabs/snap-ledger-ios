import SwiftUI

struct OnboardingValuePage: View {
    let onNext: () -> Void

    @State private var aiStatus: AppleIntelligenceStatus = .available
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

                Text("스크린샷이나 영수증을 공유 시트로 보내면 Apple Intelligence가 자동 추출해서 채워 넣어요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .appearStep(2, current: step)

            availabilityBadge
                .appearStep(3, current: step)
            Spacer()

            Button(action: onNext) {
                Text("다음")
                    .frame(maxWidth: .infinity)
                    .font(.headline)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom, 16)
            .appearStep(4, current: step)
        }
        .padding(.horizontal)
        .onAppear {
            aiStatus = AppleIntelligenceStatus.current
        }
        .task {
            guard step == 0 else { return }
            await OnboardingAppearStep.run { step = $0 }
        }
    }

    private var availabilityBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: aiStatus.iconSystemName)
                .foregroundStyle(badgeColor)
            Text(aiStatus.badgeLabel)
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
    }

    private var badgeColor: Color {
        switch aiStatus.severity {
        case .success: return .green
        case .warning: return .orange
        case .info: return .blue
        }
    }
}

#Preview {
    OnboardingValuePage { }
}
