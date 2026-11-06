import XCTest
import UIKit

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
