import Foundation
import ImageIO
import SwiftUI
import UIKit

/// Downsampled image loader for App Group inbox files.
@MainActor
enum InboxImageLoader {
    static func load(filename: String, maxPixel: CGFloat) -> UIImage? {
        let url = AppGroup.inboxURL.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

/// Text loader for App Group inbox files shared as text.
@MainActor
enum InboxTextLoader {
    static func load(filename: String) -> String? {
        let url = AppGroup.inboxURL.appendingPathComponent(filename)
        return try? InboxPayload.readText(at: url)
    }
}

/// Square thumbnail view for inbox images.
struct InboxThumbnail: View {
    let filename: String
    var size: CGFloat = 52
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.quaternary)
            .overlay {
                if InboxPayload.isText(filename: filename) {
                    Image(systemName: "text.alignleft")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .task(id: filename) {
                guard !InboxPayload.isText(filename: filename) else { return }
                image = InboxImageLoader.load(filename: filename, maxPixel: size * 3)
            }
            .accessibilityHidden(true)
    }
}

/// Full-aspect preview view for inbox images, or the shared text itself.
struct InboxImageView: View {
    let filename: String
    @State private var image: UIImage?

    var body: some View {
        if InboxPayload.isText(filename: filename) {
            InboxTextView(filename: filename)
        } else {
            imageBody
        }
    }

    private var imageBody: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary)
                    .frame(height: 160)
                    .overlay { ProgressView() }
            }
        }
        .task(id: filename) {
            image = InboxImageLoader.load(filename: filename, maxPixel: 1600)
        }
        .accessibilityLabel("원본 이미지")
    }
}

/// Scrollable preview of text shared into the inbox.
struct InboxTextView: View {
    let filename: String
    @State private var text: String?

    var body: some View {
        ScrollView {
            Text(text ?? "공유한 내용을 찾을 수 없어요.")
                .font(.callout)
                .foregroundStyle(text == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: filename) {
            text = InboxTextLoader.load(filename: filename)
        }
        .accessibilityLabel("공유한 내용")
    }
}
