import XCTest

final class MnemoUITests: XCTestCase {
    func testCreateDeckCardAndReview() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["tab-1"].waitForExistence(timeout: 15)); app.buttons["tab-1"].tap()
        app.buttons["create-deck"].tap()
        let name = app.textFields["deck-name"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Biology")
        app.buttons["save-deck"].tap()
        app.staticTexts["Biology"].firstMatch.tap()
        app.buttons["add-card"].tap()
        let question = app.descendants(matching: .any).matching(identifier: "card-question").firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 5)); question.tap(); question.typeText("How many bones?")
        let answer = app.descendants(matching: .any).matching(identifier: "card-answer").firstMatch; answer.tap(); answer.typeText("206")
        app.swipeUp()
        let save = app.buttons["save-card"]; if !save.isHittable { app.swipeUp() }; XCTAssertTrue(save.waitForExistence(timeout: 5)); save.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["tab-0"].tap()
        app.buttons["start-review"].tap()
        XCTAssertTrue(app.buttons["show-answer"].waitForExistence(timeout: 5)); app.buttons["show-answer"].tap()
        app.buttons["rating-3"].tap()
        XCTAssertTrue(app.staticTexts["session-complete"].waitForExistence(timeout: 5))
        screenshot("review-summary")
    }
    func testReferenceScreenshots() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--demo"]; app.launch()
        XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout: 15))
        screenshot("today")
        for (tab, title) in [(1, "decks"), (2, "statistics"), (3, "settings")] { app.buttons["tab-\(tab)"].tap(); screenshot(title) }
        app.buttons["open-agent"].tap(); screenshot("gemini")
    }
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
