import Foundation

/// Builds ids in the `{screen}-{name}-{type}` shape shared with the web injector,
/// so Appium, XCUITest and Playwright suites use one naming scheme.
public enum IDNaming {
    /// SwiftUI control -> type segment. Names missing here fall back to a slug of the name.
    static let typeMap: [String: String] = [
        "Button": "button",
        "TextField": "input",
        "SecureField": "input",
        "TextEditor": "input",
        "Toggle": "switch",
        "Picker": "select",
        "NavigationLink": "link",
        "Link": "link",
        "Slider": "slider",
        "Stepper": "stepper",
        "Menu": "menu",
        "DatePicker": "date-picker",
    ]

    public static var controls: Set<String> { Set(typeMap.keys) }

    static let screenSuffixes = ["ViewController", "Controller", "Screen", "Page", "View"]

    /// `LoginView.swift` -> `login`, `CheckoutScreen.swift` -> `checkout`.
    public static func screen(fromFileName fileName: String) -> String {
        var base = (fileName as NSString).lastPathComponent
        if let dot = base.lastIndex(of: ".") { base = String(base[..<dot]) }
        for suffix in screenSuffixes where base.count > suffix.count && base.hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
            break
        }
        return slugify(base).isEmpty ? "screen" : slugify(base)
    }

    public static func type(for control: String) -> String {
        typeMap[control] ?? (slugify(control).isEmpty ? "element" : slugify(control))
    }

    /// Picks the name from the first signal that yields a slug:
    /// ASCII label, handler intent, non-ASCII label, SF Symbol name, control name.
    static func baseID(screen: String, control: String, signals: Signals) -> String {
        let asciiLabel = signals.label.map(slugify) ?? ""
        let handler = signals.handler.map(slugify) ?? ""
        let unicodeLabel = signals.label.map(slugifyUnicode) ?? ""
        let symbol = signals.symbol.map(slugify) ?? ""
        let name = [asciiLabel, handler, unicodeLabel, symbol, slugify(control)]
            .first { !$0.isEmpty } ?? ""
        return [screen, name, type(for: control)].filter { !$0.isEmpty }.joined(separator: "-")
    }

    /// Lowercase, dash-separated, ASCII only. camelCase boundaries become dashes.
    public static func slugify(_ input: String) -> String {
        normalize(input) { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// Like `slugify`, but keeps any Unicode letter or digit (CJK, accented scripts).
    public static func slugifyUnicode(_ input: String) -> String {
        normalize(input) { $0.isLetter || $0.isNumber }
    }

    private static func normalize(_ input: String, keep: (Character) -> Bool) -> String {
        var words: [String] = []
        var current = ""
        var previous: Character?
        for char in input {
            if !keep(char) {
                if !current.isEmpty { words.append(current); current = "" }
            } else {
                if char.isUppercase, let prev = previous, prev.isLowercase || prev.isNumber, !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                current.append(char)
            }
            previous = char
        }
        if !current.isEmpty { words.append(current) }
        return words.joined(separator: "-").lowercased()
    }
}

/// Text found on or around a control, used to name it.
struct Signals: Equatable {
    var label: String?
    var handler: String?
    var symbol: String?
}
