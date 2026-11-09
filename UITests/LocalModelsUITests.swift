import XCTest

final class LocalModelsUITests: XCTestCase {
    @MainActor func testModelLifecycleAndInference() throws {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launch()
        app.buttons["Model library"].tap()
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
        attach(app, name: "Task island - Chat")
        app.buttons["Open response in Speak"].tap()
        let speechText = app.textViews["speech-text"]
        XCTAssertTrue(speechText.waitForExistence(timeout: 5))
        XCTAssertTrue((speechText.value as? String)?.localizedCaseInsensitiveContains("Paris") == true)
        XCTAssertTrue(app.buttons["Read aloud"].isEnabled)
        attach(app, name: "Task island - Speak handoff")
        // Changing to a native task releases the text model, but keeps the chat.
        app.buttons["Model library"].tap()
        XCTAssertTrue(app.buttons["Load model"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Unload"].exists)
        app.buttons["close-model-library"].tap()
        app.tabBars.buttons["Chat"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Paris'")).firstMatch.exists)
        app.buttons["Choose chat model"].tap()
        app.buttons["Load model"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Ready on this iPhone"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Paris'")).firstMatch.exists)
    }

    @MainActor func testDedicatedWorkspacesAndImageMode() throws {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launch()
        for name in ["Chat", "OCR", "Transcribe", "Speak"] { XCTAssertTrue(app.tabBars.buttons[name].exists) }
        XCTAssertFalse(app.tabBars.buttons["Models"].exists)
        app.buttons["Image"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Not available yet'")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Send message"].exists)
        app.buttons["Read text from an image in OCR"].tap()
        XCTAssertTrue(app.navigationBars["Read a document"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose an image"].exists)
        attach(app, name: "Task island - OCR")
        app.buttons["Model library"].tap()
        XCTAssertTrue(app.navigationBars["Model library"].waitForExistence(timeout: 5))
        app.buttons["close-model-library"].tap()
        XCTAssertTrue(app.navigationBars["Read a document"].exists)
        app.tabBars.buttons["Transcribe"].tap()
        XCTAssertTrue(app.buttons["Record audio"].exists)
        attach(app, name: "Task island - Transcribe")
        app.tabBars.buttons["Speak"].tap()
        XCTAssertTrue(app.textViews["speech-text"].exists)
        XCTAssertFalse(app.buttons["Read aloud"].isEnabled)
        app.buttons["choose-voice"].tap()
        XCTAssertTrue(app.navigationBars["Choose a voice"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.tabBars.buttons["Chat"].tap()
        app.buttons["Text"].tap()
        XCTAssertTrue(app.buttons["Choose chat model"].exists)
    }

    @MainActor private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
