import SafariServices
import SwiftUI
import UIKit

struct AboutView: View {
    @State private var safariLink: SafariLink?

    private static let appStoreURL = "itms-apps://apps.apple.com/app/id6772852897"
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
                    openInApp(Self.privacyPolicyURL)
                } label: {
                    Label("개인정보 처리방침", systemImage: "hand.raised.fill").foregroundStyle(.primary)
                }
                Button {
                    openInApp(Self.supportURL)
                } label: {
                    Label("지원", systemImage: "questionmark.circle").foregroundStyle(.primary)
                }
                Button {
                    openAppStore()
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
        .sheet(item: $safariLink) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
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

    // 개인정보·지원처럼 앱 컨텍스트를 유지해야 하는 웹 링크는 인앱 Safari로 연다.
    private func openInApp(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        safariLink = SafariLink(url: url)
    }

    // App Store는 itms-apps 스킴으로 App Store 앱을 직접 띄운다 (Safari 경유 없이).
    private func openAppStore() {
        guard let url = URL(string: Self.appStoreURL) else { return }
        UIApplication.shared.open(url)
    }
}

private struct SafariLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        // iOS 26부터 컨트롤 색상은 시스템(Liquid Glass)이 관리한다.
        // preferredControlTintColor는 deprecated이고 1:1 대체 API가 없어 커스터마이징을 두지 않는다.
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
