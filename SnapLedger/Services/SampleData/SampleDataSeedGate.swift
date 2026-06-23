#if DEBUG
import CloudKit

/// iCloud 오염 가드. 앱이 CloudKit으로 동기화 중이면(계정 available) 시딩이 실제 사용자
/// iCloud를 오염시키므로 막는다. 미로그인(로컬 전용 폴백)일 때만 시딩을 허용한다.
enum SampleDataSeedGate {
    /// `true`면 시딩 안전(미로그인). `.available`이거나 상태 확인 실패면 `false`(보수적 차단).
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
