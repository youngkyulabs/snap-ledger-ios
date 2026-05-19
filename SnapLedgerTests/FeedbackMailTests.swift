import Foundation
import Testing
@testable import SnapLedger

@MainActor
struct FeedbackMailTests {
    @Test func bodyIncludesVersionAndSystem() {
        let body = FeedbackMail.body(
            appVersion: "1.0",
            buildNumber: "10",
            systemVersion: "26.0",
            deviceModel: "iPhone"
        )
        #expect(body.contains("찰칵가계부 1.0 (10)"))
        #expect(body.contains("iOS 26.0 · iPhone"))
    }

    @Test func bodyFallsBackForMissingVersionFields() {
        let body = FeedbackMail.body(
            appVersion: nil,
            buildNumber: "",
            systemVersion: "26.0",
            deviceModel: "iPhone"
        )
        #expect(body.contains("찰칵가계부 ? (?)"))
    }

    @Test func bodyHasLeadingNewlinesForUserText() {
        let body = FeedbackMail.body(
            appVersion: "1.0",
            buildNumber: "10",
            systemVersion: "26.0",
            deviceModel: "iPhone"
        )
        // 사용자가 위에서부터 바로 쓸 수 있도록 빈 줄 + 구분선 우선.
        #expect(body.hasPrefix("\n\n---\n"))
    }

    @Test func subjectIsKorean() {
        #expect(FeedbackMail.subject == "찰칵가계부 피드백")
    }
}
