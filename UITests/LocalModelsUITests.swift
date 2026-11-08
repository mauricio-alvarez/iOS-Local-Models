import XCTest

final class LocalModelsUITests: XCTestCase {
    @MainActor func testModelLifecycleAndInference() throws {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launch()
        app.tabBars.buttons["Models"].tap()
        XCTAssertTrue(app.staticTexts["On this iPhone"].waitForExistence(timeout: 10))
        let load = app.buttons["Load model"].firstMatch
        XCTAssertTrue(load.exists)
        load.tap()
        XCTAssertTrue(app.staticTexts["Ready on this iPhone"].waitForExistence(timeout: 60))
        let prompt = app.textViews["prompt"]
        if prompt.exists { prompt.tap(); prompt.typeText("What is the capital of France? Answer briefly.") }
        else { let field = app.textFields["prompt"]; field.tap(); field.typeText("What is the capital of France? Answer briefly.") }
        XCTAssertTrue(app.buttons["Send message"].isEnabled, app.debugDescription)
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.buttons["Copy response"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Paris'")).firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "iPhone 13 - local inference"
        shot.lifetime = .keepAlways
        add(shot)
        app.tabBars.buttons["Models"].tap()
        if app.buttons["Unload"].waitForExistence(timeout: 3) {
            app.buttons["Unload"].tap()
            app.tabBars.buttons["Chat"].tap()
            XCTAssertTrue(app.staticTexts["Model unloaded"].waitForExistence(timeout: 15))
        } else {
            // iOS can request memory reclamation while other apps (e.g. PiP) run.
            app.tabBars.buttons["Chat"].tap()
            XCTAssertTrue(app.staticTexts["Unloaded to free memory"].exists)
        }
    }
}
