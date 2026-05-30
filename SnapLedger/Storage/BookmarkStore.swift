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

    /// bookmark가 resolve돼도 저장 폴더로 계속 써도 되는 디렉토리인지 판정한다.
    /// - 폴더가 삭제·이동돼 디스크에 없으면 false.
    /// - 휴지통(`.Trash`, '최근 삭제된 항목')으로 옮겨진 폴더는 아직 디스크에 남아
    ///   접근은 되지만, 비워지면 사라지므로 사용 가능한 폴더로 보지 않는다(false).
    /// security-scoped 접근을 이미 시작한 상태에서 호출할 것.
    static func isReachableDirectory(_ url: URL) -> Bool {
        guard !isInTrash(url) else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// iCloud Drive·로컬 휴지통(`.Trash`) 안의 경로인지. 휴지통 항목은 접근은 되지만
    /// 비워지면 영구 삭제되므로 저장 폴더로 계속 쓰면 안 된다. iOS 샌드박스엔 공개
    /// "is in trash" API가 없어 경로 구성요소(`.Trash`)로 판별한다.
    static func isInTrash(_ url: URL) -> Bool {
        url.pathComponents.contains(".Trash")
    }
}
