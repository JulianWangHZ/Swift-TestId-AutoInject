import Foundation
import TestIDCore
import XCTest

final class TestIDRewriterTests: XCTestCase {
    private func inject(_ body: String) -> (output: String, ids: [String])? {
        TestIDTransform.rewrite(source: "struct LoginView: View {\n  var body: some View {\n\(body)\n  }\n}\n")
    }

    func testAddsIdentifierFromLabel() throws {
        let result = try XCTUnwrap(inject(#"    Button("Sign In") { }"#))
        XCTAssertEqual(result.ids, ["LoginView.button.sign-in"])
        XCTAssertTrue(result.output.contains(#"Button("Sign In") { }.accessibilityIdentifier("LoginView.button.sign-in")"#))
    }

    func testKeepsLineCount() throws {
        let body = """
            VStack {
              TextField("Email", text: $email)
              Button("Go") { }
                .padding()
            }
        """
        let source = "struct V: View {\n  var body: some View {\n\(body)\n  }\n}\n"
        let output = try XCTUnwrap(TestIDTransform.rewrite(source: source)).output
        XCTAssertEqual(output.components(separatedBy: "\n").count, source.components(separatedBy: "\n").count)
    }

    func testSkipsControlWithIdentifierInChain() {
        XCTAssertNil(inject(#"    Button("Keep") { }.padding().accessibilityIdentifier("custom")"#))
    }

    func testFallsBackToKindWithoutLiteral() throws {
        let result = try XCTUnwrap(inject("    Button(title) { }"))
        XCTAssertEqual(result.ids, ["LoginView.button"])
    }

    func testInterpolatedLabelFallsBackToKind() throws {
        let result = try XCTUnwrap(inject(#"    Button("Hi \(name)") { }"#))
        XCTAssertEqual(result.ids, ["LoginView.button"])
    }

    func testDuplicateIDsGetSuffix() throws {
        let result = try XCTUnwrap(inject("    Button(\"OK\") { }\n    Button(\"OK\") { }"))
        XCTAssertEqual(result.ids, ["LoginView.button.ok", "LoginView.button.ok-2"])
    }

    func testIgnoresCallsOutsideTypes() {
        XCTAssertNil(TestIDTransform.rewrite(source: #"let b = Button("x") { }"#))
    }

    func testNoControlsReturnsNil() {
        XCTAssertNil(inject(#"    Text("Hello")"#))
    }
}

final class OverlayGeneratorTests: XCTestCase {
    func testWritesOverlayOnlyForChangedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = root.appendingPathComponent("App")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let view = sources.appendingPathComponent("View.swift")
        try "struct V: View { var body: some View { Button(\"A\") { } } }\n".write(to: view, atomically: true, encoding: .utf8)
        try "struct M {}\n".write(to: sources.appendingPathComponent("Model.swift"), atomically: true, encoding: .utf8)

        let overlay = root.appendingPathComponent("out/overlay.yaml")
        let generator = OverlayGenerator(outDir: root.appendingPathComponent("out/src"), overlay: overlay)
        let files = try generator.generate(sources: SourceScanner.swiftFiles(in: [sources]))

        XCTAssertEqual(files.map(\.ids), [["V.button.a"]])
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: overlay)) as? [String: Any]
        let roots = try XCTUnwrap(json?["roots"] as? [[String: String]])
        XCTAssertEqual(roots.first?["name"], view.standardizedFileURL.path)
    }

    func testScannerSkipsBuildFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for dir in ["App", "Pods/Lib", ".build/x", "DerivedData/y"] {
            let url = root.appendingPathComponent(dir)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try "".write(to: url.appendingPathComponent("F.swift"), atomically: true, encoding: .utf8)
        }
        let files = SourceScanner.swiftFiles(in: [root]).map { $0.replacingOccurrences(of: root.standardizedFileURL.path, with: "") }
        XCTAssertEqual(files, ["/App/F.swift"])
    }
}
