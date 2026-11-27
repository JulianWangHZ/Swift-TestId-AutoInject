import SwiftSyntax

/// Reads naming signals from a SwiftUI control call and its modifier chain.
enum SignalExtractor {
    /// Arguments that hold the action closure or function reference.
    static let actionLabels: Set<String> = ["action", "primaryAction"]
    /// Arguments whose binding names the value the control edits (`text: $email`).
    static let bindingLabels: Set<String> = ["text", "isOn", "selection", "value"]
    /// Receivers too generic to name an intent (`viewModel.signIn()` -> `sign-in`).
    static let genericReceivers: Set<String> = [
        "self", "viewModel", "vm", "model", "store", "presenter", "interactor",
        "coordinator", "router", "state", "actions", "action", "env", "environment",
    ]
    static let stopwords: Set<String> = [
        "fn", "cb", "callback", "handler", "handle", "on", "e", "ev", "evt", "event", "action",
    ]

    static func signals(for call: FunctionCallExprSyntax, chain: [FunctionCallExprSyntax]) -> Signals {
        let closures = Closures(call)
        return Signals(
            label: accessibilityLabel(in: chain) ?? stringArgument(of: call) ?? closures.label.flatMap(firstText),
            handler: handler(of: call, closures: closures),
            symbol: closures.label.flatMap(firstSymbol)
        )
    }

    // MARK: - Labels

    private static func accessibilityLabel(in chain: [FunctionCallExprSyntax]) -> String? {
        for modifier in chain {
            guard let member = modifier.calledExpression.as(MemberAccessExprSyntax.self),
                  member.declName.baseName.text == "accessibilityLabel",
                  let first = modifier.arguments.first,
                  let text = literal(first.expression) else { continue }
            return text
        }
        return nil
    }

    /// The first unlabeled string literal, e.g. `Button("Sign In")`, `TextField("Email", ...)`.
    private static func stringArgument(of call: FunctionCallExprSyntax) -> String? {
        for arg in call.arguments where arg.label == nil {
            if let text = literal(arg.expression) { return text }
        }
        return nil
    }

    /// The first `Text("…")` or `Label("…", …)` inside a label closure.
    private static func firstText(in node: some SyntaxProtocol) -> String? {
        firstCall(in: node, named: ["Text", "Label"]) { call in
            call.arguments.first.flatMap { $0.label == nil ? literal($0.expression) : nil }
        }
    }

    /// `Image(systemName: "trash")` -> `trash`, for icon-only controls.
    private static func firstSymbol(in node: some SyntaxProtocol) -> String? {
        firstCall(in: node, named: ["Image", "Label"]) { call in
            call.arguments.first { $0.label?.text == "systemName" }.flatMap { literal($0.expression) }
        }
    }

    // MARK: - Handlers

    private static func handler(of call: FunctionCallExprSyntax, closures: Closures) -> String? {
        for arg in call.arguments {
            guard let label = arg.label?.text else { continue }
            if actionLabels.contains(label), let signal = intent(of: arg.expression) { return signal }
            if bindingLabels.contains(label), let signal = bindingName(arg.expression) { return signal }
            if label == "destination", let signal = destinationName(arg.expression) { return signal }
        }
        return closures.action.flatMap { firstCallSignal(in: $0) }
    }

    /// `submit`, `viewModel.submit`, `{ viewModel.signIn() }`, `handleSubmit`.
    private static func intent(of expr: ExprSyntax) -> String? {
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return meaningful(stripHandlerPrefix(ref.baseName.text))
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return memberIntent(member)
        }
        if let closure = expr.as(ClosureExprSyntax.self) {
            return firstCallSignal(in: closure)
        }
        return nil
    }

    private static func memberIntent(_ member: MemberAccessExprSyntax) -> String? {
        if let receiver = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text,
           !genericReceivers.contains(receiver),
           let signal = meaningful(receiver) {
            return signal
        }
        return meaningful(stripHandlerPrefix(member.declName.baseName.text))
    }

    /// First call in a closure: a string argument wins (`select("today")`), then the callee.
    private static func firstCallSignal(in closure: ClosureExprSyntax) -> String? {
        firstCall(in: closure, named: nil) { call in
            for arg in call.arguments {
                if let text = literal(arg.expression), text.contains(where: \.isLetter),
                   let signal = meaningful(text) {
                    return signal
                }
            }
            return intent(of: call.calledExpression)
        }
    }

    /// `$email` -> `email`, `$viewModel.email` -> `email`.
    private static func bindingName(_ expr: ExprSyntax) -> String? {
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return meaningful(member.declName.baseName.text)
        }
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return meaningful(String(ref.baseName.text.drop { $0 == "$" }))
        }
        return nil
    }

    /// `destination: SettingsView()` -> `settings`.
    private static func destinationName(_ expr: ExprSyntax) -> String? {
        guard let name = expr.as(FunctionCallExprSyntax.self)?
            .calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text else { return nil }
        let screen = IDNaming.screen(fromFileName: name)
        return screen == "screen" ? nil : screen
    }

    // MARK: - Helpers

    private static func stripHandlerPrefix(_ name: String) -> String {
        for prefix in ["handle", "on"] where name.hasPrefix(prefix) {
            let rest = name.dropFirst(prefix.count)
            if let first = rest.first, first.isUppercase || first == "_" {
                return String(rest.drop { $0 == "_" })
            }
        }
        return name
    }

    /// Rejects slugs too short or too generic to tell QA anything.
    private static func meaningful(_ text: String) -> String? {
        let slug = IDNaming.slugify(text)
        guard slug.count >= 2, !stopwords.contains(slug.replacingOccurrences(of: "-", with: "")) else {
            return nil
        }
        return text
    }

    /// A plain string literal without interpolation.
    static func literal(_ expr: ExprSyntax) -> String? {
        guard let literal = expr.as(StringLiteralExprSyntax.self) else { return nil }
        let parts = literal.segments.compactMap { $0.as(StringSegmentSyntax.self)?.content.text }
        return parts.count == literal.segments.count ? parts.joined() : nil
    }

    /// Depth-first search in source order for the first call whose `extract` returns a value.
    private static func firstCall(
        in node: some SyntaxProtocol, named names: Set<String>?, extract: (FunctionCallExprSyntax) -> String?
    ) -> String? {
        for call in node.tokens(viewMode: .sourceAccurate).lazy.compactMap(callStarting(at:)) {
            if let names {
                guard let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
                      names.contains(name) else { continue }
            }
            if let value = extract(call) { return value }
        }
        return nil
    }

    /// The call expression whose callee starts with this token, if any.
    private static func callStarting(at token: TokenSyntax) -> FunctionCallExprSyntax? {
        var node = Syntax(token)
        while let parent = node.parent {
            if let call = parent.as(FunctionCallExprSyntax.self) {
                return call.calledExpression.firstToken(viewMode: .sourceAccurate) == token ? call : nil
            }
            guard parent.firstToken(viewMode: .sourceAccurate) == token else { return nil }
            node = parent
        }
        return nil
    }
}

/// Splits a control's closures into its action and its label.
/// `Button { act } label: { Text("A") }`, `Button(action: act) { Text("A") }`,
/// `Toggle(isOn: $on) { Text("A") }`. Content closures (`Picker`, `Menu`) are neither.
private struct Closures {
    /// Controls whose trailing closure is the label when no title string is given.
    static let trailingLabelControls: Set<String> = [
        "Toggle", "Slider", "Stepper", "DatePicker", "Link", "NavigationLink",
    ]

    var action: ClosureExprSyntax?
    var label: Syntax?

    init(_ call: FunctionCallExprSyntax) {
        let control = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text ?? ""
        let hasTitle = call.arguments.first.map { $0.label == nil } ?? false
        let hasActionArgument = call.arguments.contains {
            SignalExtractor.actionLabels.contains($0.label?.text ?? "")
        }

        if let trailing = call.trailingClosure {
            if control == "Button" {
                if hasActionArgument { label = Syntax(trailing) } else { action = trailing }
            } else if Self.trailingLabelControls.contains(control) && !hasTitle {
                label = Syntax(trailing)
            }
        }
        if let argument = call.arguments.first(where: { $0.label?.text == "label" }) {
            label = Syntax(argument.expression)
        }
        if let extra = call.additionalTrailingClosures.first(where: { $0.label.text == "label" }) {
            label = Syntax(extra.closure)
        }
    }
}
