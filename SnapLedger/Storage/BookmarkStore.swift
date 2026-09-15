import Foundation

enum BookmarkStore {
    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    /// Validates whether the directory URL exists and is reachable.
    static func isReachableDirectory(_ url: URL) -> Bool {
        guard !isInTrash(url) else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Checks whether the URL is located inside the Trash directory.
    static func isInTrash(_ url: URL) -> Bool {
        url.pathComponents.contains(".Trash")
    }
}
