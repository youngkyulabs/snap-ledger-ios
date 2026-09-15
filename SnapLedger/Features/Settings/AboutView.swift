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

    // App icon recreation with background tile and scaled logo glyph.
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

    // Open web links in SFSafariViewController to retain app context.
    private func openInApp(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        safariLink = SafariLink(url: url)
    }

    // Open App Store directly via itms-apps URL scheme.
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
        // iOS 26 manages control tinting via Liquid Glass system style.
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
