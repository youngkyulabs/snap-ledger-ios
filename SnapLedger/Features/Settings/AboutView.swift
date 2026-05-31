import SwiftUI
import UIKit

struct AboutView: View {
    private static let appStoreURL = "https://apps.apple.com/app/id6772852897"
    private static let privacyPolicyURL = "https://youngkyulabs.github.io/snap-ledger-ios/privacy-policy.html"
    private static let supportURL = "https://youngkyulabs.github.io/snap-ledger-ios/support.html"

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    brandIcon
                    VStack(spacing: 4) {
                        Text("찰칵가계부").font(.title3.weight(.semibold))
                        Text("버전 \(appVersionText)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("스크린샷이 한 줄 가계부로")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                Button {
                    open(Self.privacyPolicyURL)
                } label: {
                    Label("개인정보 처리방침", systemImage: "hand.raised.fill").foregroundStyle(.primary)
                }
                Button {
                    open(Self.supportURL)
                } label: {
                    Label("지원", systemImage: "questionmark.circle").foregroundStyle(.primary)
                }
                Button {
                    open(Self.appStoreURL)
                } label: {
                    Label("App Store에서 보기", systemImage: "arrow.up.right.square").foregroundStyle(.primary)
                }
            } footer: {
                Text("© 2026 YOUNGKYU SEO")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("정보")
        .navigationBarTitleDisplayMode(.inline)
    }

    // 앱 아이콘과 같은 모양을 재현: 브랜드 배경 타일(LaunchBackground = 아이콘 배경색) 위에
    // 코랄 글리프(LaunchLogo)를 얹는다. 글리프 원본은 캔버스의 ~26%(세로)뿐이라 확대해 채운다.
    private var brandIcon: some View {
        ZStack {
            Color("LaunchBackground")
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .scaleEffect(2.0)
        }
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .accessibilityHidden(true)
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        if let version, !version.isEmpty { return version }
        return "?"
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}
