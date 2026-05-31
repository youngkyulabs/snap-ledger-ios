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
                    Image("LaunchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .accessibilityHidden(true)
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
