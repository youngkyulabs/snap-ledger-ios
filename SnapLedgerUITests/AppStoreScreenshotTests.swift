import XCTest

/// Captures the App Store screenshot set; driven by scripts/capture_screenshots.sh.
final class AppStoreScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureScreenshots() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["SCREENSHOT_DIR"], let set = environment["SCREENSHOT_SET"] else {
            throw XCTSkip("Run scripts/capture_screenshots.sh to capture screenshots.")
        }
        continueAfterFailure = false
        try ScreenshotRun(outputDirectory: directory, isPad: set.hasPrefix("ipad")).captureAll()
    }
}

@MainActor
private struct ScreenshotRun {
    let outputDirectory: String
    let isPad: Bool
    let app = XCUIApplication()

    func captureAll() throws {
        app.launchArguments += ["-SeedSampleData"]
        app.launch()

        try captureReview()
        try captureHistory()
        try captureLedger()
    }

    // MARK: - Cuts

    private func captureReview() throws {
        let firstEntry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '메가커피 선릉'")).firstMatch
        try require(firstEntry, "seeded review entries (sign the simulator out of iCloud)", timeout: 30)
        try capture("01-review")

        firstEntry.tap()
        try require(app.buttons["저장"], "review editor")
        try capture("02-review-editor")
        app.buttons["닫기"].tap()
    }

    private func captureHistory() throws {
        try openTab("최근 기록")
        let header = app.staticTexts[Self.heroLastDayHeader]
        scroll(until: header, reaches: navigationBarBottom + 12)
        try capture("03-history")
    }

    private func captureLedger() throws {
        try openTab("월간 요약")
        app.buttons["이전 달"].tap()
        let monthPicker = app.buttons["월 선택"]
        let heroSelected = NSPredicate(format: "value == %@", Self.heroMonthLabel)
        let selected = XCTNSPredicateExpectation(predicate: heroSelected, object: monthPicker)
        guard XCTWaiter().wait(for: [selected], timeout: 10) == .completed else {
            throw failure("hero month \(Self.heroMonthLabel)")
        }
        try capture("04-summary")

        let progress = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(Self.heroMonthLabel) 예산")).firstMatch
        let donut = app.buttons.matching(NSPredicate(format: "label ENDSWITH '총 지출'")).firstMatch
        if isPad {
            try captureSheet("05-category-progress", opening: progress, title: "카테고리별 진행률")
            try captureSheet("06-category-totals", opening: donut, title: "카테고리별 합계")
        } else {
            try captureSheet("06-category-progress", opening: progress, title: "카테고리별 진행률")
        }

        let reconciliation = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '정상'")).firstMatch
        reconciliation.tap()
        try require(app.navigationBars["월 정산"], "reconciliation view")
        try capture("07-reconciliation")

        if !isPad {
            app.buttons["BackButton"].firstMatch.tap()
            let categoryHeader = app.staticTexts["카테고리 비중"]
            scroll(until: categoryHeader, reaches: navigationBarBottom - 40)
            try capture("05-categories")
        }
    }

    private func captureSheet(_ name: String, opening trigger: XCUIElement, title: String) throws {
        trigger.tap()
        let titleText = app.staticTexts[title]
        try require(titleText, title)
        if !isPad {
            expandSheet(grabbing: titleText)
        }
        try capture(name)
        app.buttons["완료"].tap()
        guard app.staticTexts[title].waitForNonExistence(timeout: 10) else { throw failure("\(title) dismissal") }
    }

    // MARK: - Helpers

    /// Header of the last day in the hero (previous) month, as the history list shows it.
    private static var heroLastDayHeader: String {
        let calendar = Calendar.current
        let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let lastDay = calendar.date(byAdding: .day, value: -1, to: thisMonth) ?? thisMonth
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter.string(from: lastDay)
    }

    private static var heroMonthLabel: String {
        let hero = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
        let components = Calendar.current.dateComponents([.year, .month], from: hero)
        return "\(components.year ?? 0)년 \(components.month ?? 0)월"
    }

    private var navigationBarBottom: CGFloat {
        app.navigationBars.firstMatch.frame.maxY
    }

    private func openTab(_ label: String) throws {
        let tab = app.tabBars.buttons[label].exists ? app.tabBars.buttons[label] : app.buttons[label].firstMatch
        tab.tap()
        try require(app.navigationBars[label], "\(label) tab")
    }

    /// Drags the list slowly (no inertia) until the element's top edge sits at targetY.
    private func scroll(until element: XCUIElement, reaches targetY: CGFloat) {
        let window = app.windows.firstMatch.frame
        for _ in 0..<30 where !element.exists || element.frame.minY > window.maxY * 0.8 {
            drag(by: window.height * 0.4)
        }
        for _ in 0..<4 {
            let offset = element.frame.minY - targetY
            if abs(offset) < 6 { break }
            drag(by: offset)
            // iPhone Duo applies touches a few seconds late
            Thread.sleep(forTimeInterval: 2)
        }
    }

    /// Pulls a medium-detent sheet up to its large detent.
    private func expandSheet(grabbing handle: XCUIElement) {
        Thread.sleep(forTimeInterval: 1)
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let top = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        start.press(forDuration: 0.2, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    private func drag(by distance: CGFloat) {
        let window = app.windows.firstMatch
        let startY = distance > 0 ? 0.75 : 0.3
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
        let end = start.withOffset(CGVector(dx: 0, dy: -distance))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.8)
    }

    private func require(_ element: XCUIElement, _ description: String, timeout: TimeInterval = 15) throws {
        guard element.waitForExistence(timeout: timeout) else { throw failure(description) }
    }

    private func failure(_ description: String) -> XCTestError {
        XCTestError(.failureWhileWaiting, userInfo: [NSLocalizedDescriptionKey: "Missing \(description)"])
    }

    /// Lets animations settle, then writes a native-resolution PNG.
    private func capture(_ name: String) throws {
        Thread.sleep(forTimeInterval: 2.5)
        let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent("\(name).png")
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }
}
