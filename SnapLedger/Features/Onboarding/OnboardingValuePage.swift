import SwiftUI

struct OnboardingValuePage: View {
    let onNext: () -> Void

    @State private var isAIAvailable = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

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

            availabilityBadge
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
        }
        .padding(.horizontal)
        .onAppear {
            isAIAvailable = FoundationModelsExtractionService.isAvailable
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
    OnboardingValuePage { }
}
