import Foundation
import Testing
import UserNotifications
@testable import SnapLedger

struct OnboardingPermissionActionTests {
    @Test func notDeterminedRequestsAuthorization() {
        #expect(OnboardingPermissionAction.decide(status: .notDetermined) == .requestAuthorization)
    }

    @Test func deniedRoutesToSystemSettings() {
        #expect(OnboardingPermissionAction.decide(status: .denied) == .openSystemSettings)
    }

    @Test func authorizedKeepsToggleOn() {
        #expect(OnboardingPermissionAction.decide(status: .authorized) == .keepOn)
    }

    @Test func provisionalKeepsToggleOn() {
        #expect(OnboardingPermissionAction.decide(status: .provisional) == .keepOn)
    }

    @Test func ephemeralKeepsToggleOn() {
        #expect(OnboardingPermissionAction.decide(status: .ephemeral) == .keepOn)
    }
}
