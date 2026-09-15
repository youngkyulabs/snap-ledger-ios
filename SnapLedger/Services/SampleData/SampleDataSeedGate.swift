#if DEBUG
import CloudKit

/// Guard preventing sample seeding while signed into iCloud.
enum SampleDataSeedGate {
    /// Returns true only when iCloud is not actively syncing.
    static func canSeedWithoutICloudPollution() async -> Bool {
        let container = CKContainer(identifier: "iCloud.com.youngkyu.snapledger")
        do {
            let status = try await container.accountStatus()
            return status != .available
        } catch {
            return false
        }
    }
}
#endif
