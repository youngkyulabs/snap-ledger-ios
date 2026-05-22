import Foundation
import UserNotifications

enum OnboardingPermissionAction: Equatable {
    case requestAuthorization
    case openSystemSettings
    case keepOn

    static func decide(status: UNAuthorizationStatus) -> OnboardingPermissionAction {
        switch status {
        case .notDetermined:
            .requestAuthorization
        case .denied:
            .openSystemSettings
        case .authorized, .provisional, .ephemeral:
            .keepOn
        @unknown default:
            .openSystemSettings
        }
    }
}
