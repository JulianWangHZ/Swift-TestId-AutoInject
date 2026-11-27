import Foundation
@testable import TestIDCore
import XCTest

final class TestIDRewriterTests: XCTestCase {
    private func ids(_ body: String, file: String = "LoginView.swift") -> [String] {
        let source = "struct LoginView: View {\n  var body: some View {\n\(body)\n  }\n}\n"
        return TestIDTransform.rewrite(source: source, fileName: file)?.ids ?? []
    }

    func testStringLabels() {
        XCTAssertEqual(ids(#"Button("Sign In") { }"#), ["login-sign-in-button"])
        XCTAssertEqual(ids(#"TextField("Email", text: $email)"#), ["login-email-input"])
        XCTAssertEqual(ids(#"SecureField("Password", text: $password)"#), ["login-password-input"])
        XCTAssertEqual(ids(#"Toggle("Remember me", isOn: $remember)"#), ["login-remember-me-switch"])
    }

    func testLabelClosureText() {
        XCTAssertEqual(ids(#"Button { help() } label: { Text("Help") }"#), ["login-help-button"])
        XCTAssertEqual(ids(#"Button(action: go) { Label("Settings", systemImage: "gear") }"#), ["login-settings-button"])
        XCTAssertEqual(ids(#"Toggle(isOn: $on) { Text("Dark mode") }"#), ["login-dark-mode-switch"])
    }

    func testAccessibilityLabelWins() {
        XCTAssertEqual(
            ids(#"Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")"#),
            ["login-close-button"])
    }

    func testHandlerIntentWithoutText() {
        XCTAssertEqual(ids(#"Button(action: submit) { Image(systemName: "paperplane") }"#), ["login-submit-button"])
        XCTAssertEqual(ids(#"Button(action: handleSubmit) { Image(systemName: "x") }"#), ["login-submit-button"])
        XCTAssertEqual(ids(#"Button { viewModel.signIn() } label: { Image(systemName: "x") }"#), ["login-sign-in-button"])
        XCTAssertEqual(ids(#"Button { datePicker.open() } label: { Image(systemName: "x") }"#), ["login-date-picker-button"])
        XCTAssertEqual(ids(#"Button { select("today") } label: { Image(systemName: "x") }"#), ["login-today-button"])
    }

    func testBindingNamesInput() {
        XCTAssertEqual(ids("TextField(title, text: $viewModel.email)"), ["login-email-input"])
        XCTAssertEqual(ids("Slider(value: $volume)"), ["login-volume-slider"])
    }

    func testNavigationDestination() {
        XCTAssertEqual(ids("NavigationLink(destination: SettingsView()) { Image(systemName: \"gear\") }"),
                       ["login-settings-link"])
    }

    func testNavigationValue() {
        XCTAssertEqual(ids("NavigationLink(value: donut.id) { DonutView(donut: donut) }"), ["login-donut-link"])
        XCTAssertEqual(ids("NavigationLink(value: Panel.city(city.id)) { Label(city.name, systemImage: \"building\") }"),
                       ["login-city-link"])
        XCTAssertEqual(ids("NavigationLink(value: Panel.truck) { Image(systemName: \"box\") }"), ["login-truck-link"])
    }

    func testSymbolFallback() {
        XCTAssertEqual(ids(#"Button { } label: { Image(systemName: "trash") }"#), ["login-trash-button"])
    }

    func testNonASCIILabel() {
        XCTAssertEqual(ids(#"Button("登入") { }"#), ["login-登入-button"])
        XCTAssertEqual(ids(#"Button("登入", action: handleLogin)"#), ["login-button"])
    }

    func testContentClosuresAreNotLabels() {
        XCTAssertEqual(ids(#"Picker("Size", selection: $size) { Text("S") }"#), ["login-size-select"])
        XCTAssertEqual(ids(#"Menu { Button("Copy") { } } label: { Text("More") }"#),
                       ["login-copy-button", "login-more-menu"])
    }

    func testLocalizationKeysNameControls() {
        XCTAssertEqual(ids("Button(L10n.cancel, role: .cancel) {}"), ["login-cancel-button"])
        XCTAssertEqual(ids("Button(L10n.signIn) { }"), ["login-sign-in-button"])
        XCTAssertEqual(ids("Toggle(L10n.showMissingEpisodes, isOn: $show)"), ["login-show-missing-episodes-switch"])
        XCTAssertEqual(ids("Button(R.string.localizable.save()) { }"), ["login-save-button"])
        XCTAssertEqual(ids(#"Button(String(localized: "Delete")) { }"#), ["login-delete-button"])
    }

    func testLocalizationKeysInLabelClosure() {
        XCTAssertEqual(ids(#"Button { value -= 1 } label: { Label(L10n.decrease, systemImage: "minus") }"#),
                       ["login-decrease-button"])
        XCTAssertEqual(ids("Button(L10n.learnMore + .ellipsis) { }"), ["login-learn-more-button"])
    }

    func testVariablePropertiesAreNotKeys() {
        XCTAssertEqual(ids("Button(item.name) { }"), ["login-button-button"])
        XCTAssertEqual(ids(#"Button { } label: { Label(element.title, systemImage: "gear") }"#), ["login-gear-button"])
    }

    func testRoleNamesUnlabeledButton() {
        XCTAssertEqual(ids("Button(title, role: .destructive, action: action)"), ["login-destructive-button"])
        XCTAssertEqual(ids(#"Button(title, role: .cancel) { save() }"#), ["login-save-button"])
    }

    func testDuplicatesGetSuffix() {
        XCTAssertEqual(ids("Button(\"OK\") { }\nButton(\"OK\") { }"), ["login-ok-button", "login-ok-button-2"])
    }

    func testControlNameFallback() {
        XCTAssertEqual(ids("Button(title) { }"), ["login-button-button"])
    }

    func testSkipsControlWithIdentifierInChain() {
        XCTAssertEqual(ids(#"Button("Keep") { }.padding().accessibilityIdentifier("custom")"#), [])
    }

    func testIgnoresCallsOutsideTypes() {
        XCTAssertNil(TestIDTransform.rewrite(source: #"let b = Button("x") { }"#, fileName: "A.swift"))
    }

    func testOutputKeepsLinesAndInsertsModifier() throws {
        let source = """
        struct LoginView: View {
          var body: some View {
            VStack {
              Button("Go") { }
                .padding()
            }
          }
        }
        """
        let output = try XCTUnwrap(TestIDTransform.rewrite(source: source, fileName: "LoginView.swift")).output
        XCTAssertTrue(output.contains(#"Button("Go") { }.accessibilityIdentifier("login-go-button")"#))
        XCTAssertEqual(output.components(separatedBy: "\n").count, source.components(separatedBy: "\n").count)
    }
    func testComponentFileNameIsNotRepeated() {
        XCTAssertEqual(TestIDTransform.rewrite(
            source: "struct NavigationBarCloseButton: View { var body: some View { Button(role: .close, action: a) { } } }",
            fileName: "NavigationBarCloseButton.swift")?.ids, ["navigation-bar-close-button"])
        XCTAssertEqual(TestIDTransform.rewrite(
            source: #"struct SearchField: View { var body: some View { TextField("Search", text: $q) } }"#,
            fileName: "SearchField.swift")?.ids, ["search-input"])
        XCTAssertEqual(ids(#"Button("Login") { }"#), ["login-button"])
        XCTAssertEqual(ids(#"Button("Log out") { }"#), ["login-log-out-button"])
    }
}


final class IDNamingTests: XCTestCase {
    func testScreenFromFileName() {
        XCTAssertEqual(IDNaming.screen(fromFileName: "/a/b/LoginView.swift"), "login")
        XCTAssertEqual(IDNaming.screen(fromFileName: "CheckoutViewController.swift"), "checkout")
        XCTAssertEqual(IDNaming.screen(fromFileName: "OrderListScreen.swift"), "order-list")
        XCTAssertEqual(IDNaming.screen(fromFileName: "View.swift"), "view")
    }

    func testSlugify() {
        XCTAssertEqual(IDNaming.slugify("submitButton"), "submit-button")
        XCTAssertEqual(IDNaming.slugify("Sign In!"), "sign-in")
        XCTAssertEqual(IDNaming.slugify("登入"), "")
        XCTAssertEqual(IDNaming.slugifyUnicode("登入 Now"), "登入-now")
    }
}

final class OverlayGeneratorTests: XCTestCase {
    func testWritesOverlayOnlyForChangedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = root.appendingPathComponent("App")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let view = sources.appendingPathComponent("HomeView.swift")
        try "struct HomeView: View { var body: some View { Button(\"A\") { } } }\n"
            .write(to: view, atomically: true, encoding: .utf8)
        try "struct M {}\n".write(to: sources.appendingPathComponent("Model.swift"), atomically: true, encoding: .utf8)

        let overlay = root.appendingPathComponent("out/overlay.yaml")
        let generator = OverlayGenerator(outDir: root.appendingPathComponent("out/src"), overlay: overlay)
        let files = try generator.generate(sources: SourceScanner.swiftFiles(in: [sources]))

        XCTAssertEqual(files.map(\.ids), [["home-a-button"]])
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: overlay)) as? [String: Any]
        let roots = try XCTUnwrap(json?["roots"] as? [[String: String]])
        XCTAssertEqual(roots.first?["name"], view.standardizedFileURL.path)
        XCTAssertEqual(json?["use-external-names"] as? Bool, false)
    }

    func testScannerSkipsBuildFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for dir in ["App", "Pods/Lib", ".build/x", "DerivedData/y"] {
            let url = root.appendingPathComponent(dir)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try "".write(to: url.appendingPathComponent("F.swift"), atomically: true, encoding: .utf8)
        }
        let files = SourceScanner.swiftFiles(in: [root])
            .map { $0.replacingOccurrences(of: root.standardizedFileURL.path, with: "") }
        XCTAssertEqual(files, ["/App/F.swift"])
    }
}
