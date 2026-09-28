import Foundation

/// Lists and deletes files directly inside the storage folder.
enum ExportFolderFiles {
    static func names(in folderURL: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folderURL.path)
    }

    /// Deletes the file under file coordination.
    static func remove(_ url: URL) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var thrown: (any Error)?
        unsafe coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { coordinatedURL in
            do {
                try FileManager.default.removeItem(at: coordinatedURL)
            } catch {
                thrown = error
            }
        }
        if let err = coordinationError { throw err }
        if let err = thrown { throw err }
    }
}
