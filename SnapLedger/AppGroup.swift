import Foundation

enum AppGroup {
    static let identifier = "group.com.youngkyu.snapledger"

    static var containerURL: URL {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) else {
            fatalError("App Group container unavailable — missing entitlement for \(identifier)")
        }
        return url
    }

    static var inboxURL: URL {
        let url = containerURL.appendingPathComponent("inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
