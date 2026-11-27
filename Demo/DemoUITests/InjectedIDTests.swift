import XCTest

final class InjectedIDTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }

    func testInjectedIdentifiersExist() {
        XCTAssertTrue(app.textFields["LoginView.textField.email"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["LoginView.secureField.password"].exists)
        XCTAssertTrue(app.switches["LoginView.toggle.remember-me"].exists)
        XCTAssertTrue(app.buttons["LoginView.button"].exists)
    }

    func testTapInjectedButton() {
        app.buttons["LoginView.button.sign-in"].tap()
        XCTAssertEqual(app.staticTexts["status"].label, "signed-in")
    }

    func testExistingIdentifierIsKept() {
        XCTAssertTrue(app.buttons["custom.keep"].exists)
        XCTAssertFalse(app.buttons["LoginView.button.keep-my-id"].exists)
    }

    func testSourceLocationIsUnchanged() {
        let parts = app.staticTexts["sourceProbe"].label.split(separator: "|")
        XCTAssertEqual(parts.first, "19")
        XCTAssertTrue(parts.last?.hasSuffix("/Demo/Demo/LoginView.swift") == true)
    }
}
