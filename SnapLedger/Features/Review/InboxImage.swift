import Foundation
import ImageIO
import SwiftUI
import UIKit

/// App Group inbox 에 보관된 원본 이미지를 다운샘플해 로드한다.
/// 실패한 PendingImage 는 파일이 남아 있어 검토 탭에서 미리보기·수동 입력에 재사용된다.
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

/// 리스트 행용 정사각 썸네일.
struct InboxThumbnail: View {
    let filename: String
    var size: CGFloat = 52
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.quaternary)
            .overlay {
                if let image {
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
                image = InboxImageLoader.load(filename: filename, maxPixel: size * 3)
            }
            .accessibilityHidden(true)
    }
}

/// 편집 화면 상단의 원본 이미지 미리보기 (전체 비율 유지).
struct InboxImageView: View {
    let filename: String
    @State private var image: UIImage?

    var body: some View {
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
