import XCTest
import UIKit

final class MnemoUITests: XCTestCase {
    func testLastBlocksCanScrollAboveBottomMenu() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--demo"]; app.launch()
        XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout: 15))
        for (tab, identifier) in [(0, "today-last-block"), (1, "decks-last-block"), (2, "statistics-last-block"), (3, "settings-footer")] {
            app.buttons["tab-\(tab)"].tap()
            let last = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            for _ in 0..<6 {
                if last.exists && last.frame.height > 0 && last.frame.maxY < app.buttons["tab-0"].frame.minY - 12 && last.frame.minY > 80 { break }
                app.scrollViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(last.exists, identifier)
            XCTAssertGreaterThan(last.frame.height, 0, identifier)
            XCTAssertLessThan(last.frame.maxY, app.buttons["tab-0"].frame.minY - 12, identifier + " is covered by the menu")
            screenshot("scroll-bottom-\(tab)")
        }
    }
    func testDeleteDeckRequiresConfirmationAndKeepsOtherDecks() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--demo"]; app.launch()
        XCTAssertTrue(app.buttons["tab-1"].waitForExistence(timeout: 15)); app.buttons["tab-1"].tap()
        app.staticTexts["Английский B2"].firstMatch.tap()
        let options = app.buttons["deck-options"]; XCTAssertTrue(options.waitForExistence(timeout: 5)); XCTAssertTrue(options.isHittable)
        screenshot("deck-options")
        options.tap()
        let delete = app.buttons["delete-deck"]
        for _ in 0..<4 { if delete.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(delete.isHittable); delete.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3)); app.alerts.buttons["Отмена"].tap()
        XCTAssertTrue(delete.exists); delete.tap(); app.alerts.buttons["Удалить"].tap()
        XCTAssertTrue(app.buttons["create-deck"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Английский B2"].exists); XCTAssertTrue(app.staticTexts["Анатомия"].exists)
    }
    func testAIProviderSettingsAndManualModel() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.buttons["tab-3"].waitForExistence(timeout: 15)); app.buttons["tab-3"].tap()
        app.buttons["ai-settings"].tap()
        let provider = app.buttons["ai-provider"]; XCTAssertTrue(provider.waitForExistence(timeout: 5)); provider.tap()
        app.buttons["DeepSeek"].tap()
        let model = app.textFields["ai-model-id"]
        for _ in 0..<4 { if model.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(model.isHittable); model.tap(); model.typeText("manual-test-model")
        let save = app.buttons["Использовать эту модель"]
        if !save.isHittable { app.swipeUp() }; save.tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.swipeDown(); screenshot("ai-settings-deepseek")
    }
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
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        assertVisibleContent(screenshot.image, screen: name)
    }
    /// Check actual rendered pixels, not only accessibility elements that may
    /// remain present while an incorrectly animated screen is transparent.
    private func assertVisibleContent(_ image: UIImage, screen: String) {
        let width = 240, height = 520
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let bitmap = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            guard let cg = image.cgImage, let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmap) else { XCTFail("Could not inspect screenshot"); return }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var bright = 0
        for y in (height * 15 / 100)..<(height * 85 / 100) {
            for x in 8..<(width - 8) {
                let i = (y * width + x) * 4
                if bytes[i] > 190 && bytes[i + 1] > 190 && bytes[i + 2] > 190 { bright += 1 }
            }
        }
        XCTAssertGreaterThan(bright, 100, "Screen \(screen) has no readable foreground content")
    }
}
