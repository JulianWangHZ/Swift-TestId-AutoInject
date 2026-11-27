import XCTest

final class InjectedIDTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }

    func testInjectedIdentifiersExist() {
        XCTAssertTrue(app.textFields["login-email-input"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["login-password-input"].exists)
        XCTAssertTrue(app.switches["login-remember-me-switch"].exists)
        XCTAssertTrue(app.buttons["login-help-button"].exists)
    }

    func testTapInjectedButton() {
        app.buttons["login-sign-in-button"].tap()
        XCTAssertEqual(app.staticTexts["status"].label, "signed-in")
    }

    func testExistingIdentifierIsKept() {
        XCTAssertTrue(app.buttons["custom.keep"].exists)
        XCTAssertFalse(app.buttons["login-keep-my-id-button"].exists)
    }

    func testSourceLocationIsUnchanged() {
        let parts = app.staticTexts["sourceProbe"].label.split(separator: "|")
        XCTAssertEqual(parts.first, "20")
        let path = String(parts.last ?? "")
        XCTAssertTrue(path.hasSuffix("/Demo/Demo/LoginView.swift"), path)
        XCTAssertFalse(path.contains("DerivedSources"), "points at the rewritten copy: \(path)")
    }

    func testRowsShareOneIDAndAreReachableByIndex() {
        let remove = app.buttons.matching(identifier: "login-remove-button")
        XCTAssertEqual(remove.count, 2)
        remove.element(boundBy: 1).tap()
        XCTAssertEqual(app.staticTexts["status"].label, "removed-Pear")
    }
}
