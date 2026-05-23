import Foundation
import Testing
@testable import SnapLedger

struct AppleIntelligenceStatusTests {
    @Test func availableIsAvailable() {
        #expect(AppleIntelligenceStatus.available.isAvailable)
    }

    @Test func unavailableCasesReportNotAvailable() {
        #expect(!AppleIntelligenceStatus.appleIntelligenceOff.isAvailable)
        #expect(!AppleIntelligenceStatus.deviceNotEligible.isAvailable)
        #expect(!AppleIntelligenceStatus.modelNotReady.isAvailable)
    }

    @Test func severityMapping() {
        #expect(AppleIntelligenceStatus.available.severity == .success)
        #expect(AppleIntelligenceStatus.appleIntelligenceOff.severity == .warning)
        #expect(AppleIntelligenceStatus.deviceNotEligible.severity == .warning)
        #expect(AppleIntelligenceStatus.modelNotReady.severity == .info)
    }

    @Test func iconMapping() {
        #expect(AppleIntelligenceStatus.available.iconSystemName == "checkmark.seal.fill")
        #expect(AppleIntelligenceStatus.modelNotReady.iconSystemName == "arrow.down.circle.fill")
        #expect(AppleIntelligenceStatus.appleIntelligenceOff.iconSystemName == "exclamationmark.triangle.fill")
        #expect(AppleIntelligenceStatus.deviceNotEligible.iconSystemName == "exclamationmark.triangle.fill")
    }

    @Test func openSystemSettingsLinkOnlyWhenUserCanFix() {
        #expect(AppleIntelligenceStatus.appleIntelligenceOff.offersSystemSettingsLink)
        #expect(!AppleIntelligenceStatus.available.offersSystemSettingsLink)
        #expect(!AppleIntelligenceStatus.deviceNotEligible.offersSystemSettingsLink)
        #expect(!AppleIntelligenceStatus.modelNotReady.offersSystemSettingsLink)
    }

    @Test func shortLabelMentionsAppleIntelligenceBrand() {
        for status in [
            AppleIntelligenceStatus.available,
            .appleIntelligenceOff,
            .modelNotReady,
        ] {
            #expect(status.shortLabel.contains("Apple Intelligence"))
        }
    }

    @Test func detailMessagesGuideUserAction() {
        let off = AppleIntelligenceStatus.appleIntelligenceOff.detailMessage
        #expect(off.contains("Apple Intelligence 및 Siri"))
        #expect(off.contains("켜"))

        let ineligible = AppleIntelligenceStatus.deviceNotEligible.detailMessage
        #expect(ineligible.contains("iPhone 15 Pro"))
        #expect(ineligible.contains("직접 입력"))

        let available = AppleIntelligenceStatus.available.detailMessage
        #expect(available.contains("기기 안에서"))

        let notReady = AppleIntelligenceStatus.modelNotReady.detailMessage
        #expect(notReady.contains("준비"))
    }

    @Test func badgeLabelForOffStatePointsToSettingsPath() {
        let label = AppleIntelligenceStatus.appleIntelligenceOff.badgeLabel
        #expect(label.contains("설정"))
        #expect(label.contains("Apple Intelligence 및 Siri"))
    }

    @Test func reviewTabMessageEmptyWhenAvailable() {
        #expect(AppleIntelligenceStatus.available.reviewTabMessage.isEmpty)
    }

    @Test func reviewTabMessagesMentionManualInput() {
        for status in [
            AppleIntelligenceStatus.appleIntelligenceOff,
            .deviceNotEligible,
            .modelNotReady,
        ] {
            #expect(status.reviewTabMessage.contains("수동 입력") || status.reviewTabMessage.contains("직접 추가"))
        }
    }
}
