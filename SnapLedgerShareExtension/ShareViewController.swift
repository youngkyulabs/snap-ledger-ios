import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private static let appGroupIdentifier = "group.com.youngkyu.snapledger"
    private static let inboxFolderName = "inbox"
    private static let preferredHeight: CGFloat = 220
    /// Guards against sharing an entire article into the extraction prompt: the on-device model's
    /// context window also has to hold the instruction prompt, so a longer share would overflow it.
    /// Kept in sync with `InboxPayload.extractionCharacterLimit` in the app target, which cannot be
    /// imported from here.
    private static let maxTextLength = 2_000

    private let spinner = UIActivityIndicatorView(style: .large)
    private let statusIcon = UIImageView()
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        preferredContentSize = CGSize(width: 0, height: Self.preferredHeight)
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        preferredContentSize = CGSize(width: 0, height: Self.preferredHeight)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await ingestAttachments() }
    }

    private func setupUI() {
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.contentMode = .scaleAspectFit
        statusIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .regular)
        statusIcon.isHidden = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "찰칵가계부에 저장 중…"
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0

        view.addSubview(spinner)
        view.addSubview(statusIcon)
        view.addSubview(label)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusIcon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusIcon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusIcon.widthAnchor.constraint(equalToConstant: 56),
            statusIcon.heightAnchor.constraint(equalToConstant: 56),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    @MainActor
    private func ingestAttachments() async {
        guard let inboxURL = Self.inboxURL() else {
            await finish(.failure(message: "공유 저장 공간에 접근할 수 없어요."))
            return
        }

        let items = (extensionContext?.inputItems ?? []).compactMap { $0 as? NSExtensionItem }

        var savedCount = 0
        for item in items {
            savedCount += await save(item: item, to: inboxURL)
        }

        if savedCount > 0 {
            await finish(.success(count: savedCount))
        } else {
            await finish(.failure(message: "가져올 내용을 찾을 수 없어요."))
        }
    }

    /// Saves one shared item, preferring its images: a post that carries both a screenshot and a
    /// caption is one payment, so its text is only used when no image made it to the inbox.
    private func save(item: NSExtensionItem, to inboxURL: URL) async -> Int {
        var textProviders: [NSItemProvider] = []
        var savedImages = 0
        for provider in item.attachments ?? [] {
            guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                textProviders.append(provider)
                continue
            }
            if await saveImage(provider: provider, to: inboxURL) {
                savedImages += 1
            }
        }
        if savedImages > 0 { return savedImages }

        var savedTexts = 0
        for provider in textProviders {
            guard let text = await loadText(from: provider),
                  Self.saveText(text, to: inboxURL) else { continue }
            savedTexts += 1
        }
        if savedTexts > 0 { return savedTexts }

        // Some apps (Messages) share selected text as item text with no attachment.
        if let text = item.attributedContentText?.string, Self.saveText(text, to: inboxURL) {
            return 1
        }
        return 0
    }

    private func saveImage(provider: NSItemProvider, to inboxURL: URL) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { sourceURL, error in
                guard let sourceURL, error == nil else {
                    continuation.resume(returning: false)
                    return
                }
                let ext = sourceURL.pathExtension.isEmpty ? "img" : sourceURL.pathExtension
                let dest = inboxURL.appendingPathComponent("\(UUID().uuidString).\(ext)")
                do {
                    try FileManager.default.copyItem(at: sourceURL, to: dest)
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Loads shared plain text, ignoring URLs and other non-text payloads.
    private func loadText(from provider: NSItemProvider) async -> String? {
        let textType = UTType.plainText.identifier
        guard provider.hasItemConformingToTypeIdentifier(textType) else { return nil }

        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            provider.loadItem(forTypeIdentifier: textType) { item, _ in
                switch item {
                case let string as String:
                    continuation.resume(returning: string)
                case let attributed as NSAttributedString:
                    continuation.resume(returning: attributed.string)
                case let data as Data:
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                // Files (and any app vending a file representation) hand back a URL, not a string.
                case let url as URL where url.isFileURL:
                    continuation.resume(returning: try? String(contentsOf: url, encoding: .utf8))
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func saveText(_ text: String, to inboxURL: URL) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let clipped = String(trimmed.prefix(maxTextLength))
        let dest = inboxURL.appendingPathComponent("\(UUID().uuidString).txt")
        do {
            try clipped.write(to: dest, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    private enum FinishOutcome {
        case success(count: Int)
        case failure(message: String)

        var message: String {
            switch self {
            case .success(let count): return "\(count)건 저장됨"
            case .failure(let message): return message
            }
        }

        var symbolName: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .failure: return "exclamationmark.triangle.fill"
            }
        }

        var symbolColor: UIColor {
            switch self {
            case .success: return .systemGreen
            case .failure: return .systemOrange
            }
        }

        var displayDuration: TimeInterval {
            switch self {
            case .success: return 1.2
            case .failure: return 1.6
            }
        }

        var labelColor: UIColor {
            switch self {
            case .success: return .label
            case .failure: return .secondaryLabel
            }
        }
    }

    @MainActor
    private func finish(_ outcome: FinishOutcome) async {
        spinner.stopAnimating()
        spinner.isHidden = true

        statusIcon.image = UIImage(systemName: outcome.symbolName)
        statusIcon.tintColor = outcome.symbolColor
        statusIcon.isHidden = false

        label.text = outcome.message
        label.textColor = outcome.labelColor

        try? await Task.sleep(nanoseconds: UInt64(outcome.displayDuration * 1_000_000_000))
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private static func inboxURL() -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }
        let url = container.appendingPathComponent(inboxFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
