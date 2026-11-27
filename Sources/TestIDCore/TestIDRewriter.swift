import SwiftSyntax

/// Appends `.accessibilityIdentifier("<Type>.<label>")` to SwiftUI controls.
/// The modifier is placed on the same line as the call, so line numbers do not shift.
public final class TestIDRewriter: SyntaxRewriter {
    public static let controls: Set<String> = [
        "Button", "TextField", "SecureField", "Toggle", "NavigationLink",
        "Picker", "Slider", "Stepper", "Link", "Menu",
    ]

    public private(set) var injected: [String] = []
    private var typeStack: [String] = []
    private var usedIDs: [String: Int] = [:]

    public override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    public override func visit(_ node: StructDeclSyntax) -> DeclSyntax {
        typeStack.append(node.name.text)
        defer { typeStack.removeLast() }
        return super.visit(node)
    }

    public override func visit(_ node: ClassDeclSyntax) -> DeclSyntax {
        typeStack.append(node.name.text)
        defer { typeStack.removeLast() }
        return super.visit(node)
    }

    public override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
        let visited = super.visit(node)
        guard
            let kind = node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
            Self.controls.contains(kind),
            let owner = typeStack.last,
            !Self.hasIdentifierInChain(node)
        else { return visited }

        let id = uniqueID("\(owner).\(Self.label(for: node, kind: kind))")
        injected.append(id)
        return ExprSyntax(Self.appendModifier(to: visited, id: id))
    }

    private func uniqueID(_ base: String) -> String {
        let count = usedIDs[base, default: 0] + 1
        usedIDs[base] = count
        return count == 1 ? base : "\(base)-\(count)"
    }

    /// `Button("Sign In")` -> `button.sign-in`; no string literal -> `button`.
    static func label(for call: FunctionCallExprSyntax, kind: String) -> String {
        let prefix = kind.prefix(1).lowercased() + kind.dropFirst()
        guard let text = firstStringLiteral(in: call) else { return prefix }
        let slug = text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-")
        return slug.isEmpty ? prefix : "\(prefix).\(slug)"
    }

    private static func firstStringLiteral(in call: FunctionCallExprSyntax) -> String? {
        for arg in call.arguments {
            guard let literal = arg.expression.as(StringLiteralExprSyntax.self) else { continue }
            let parts = literal.segments.compactMap { $0.as(StringSegmentSyntax.self)?.content.text }
            guard parts.count == literal.segments.count else { return nil }
            return parts.joined()
        }
        return nil
    }

    /// Skips controls whose modifier chain already sets an identifier.
    private static func hasIdentifierInChain(_ call: FunctionCallExprSyntax) -> Bool {
        var current = Syntax(call)
        while let member = current.parent?.as(MemberAccessExprSyntax.self),
              member.base?.id == current.id,
              let outer = member.parent?.as(FunctionCallExprSyntax.self) {
            if member.declName.baseName.text == "accessibilityIdentifier" { return true }
            current = Syntax(outer)
        }
        return false
    }

    private static func appendModifier(to expr: ExprSyntax, id: String) -> FunctionCallExprSyntax {
        FunctionCallExprSyntax(
            calledExpression: MemberAccessExprSyntax(
                base: expr.with(\.trailingTrivia, []),
                period: .periodToken(),
                declName: DeclReferenceExprSyntax(baseName: .identifier("accessibilityIdentifier"))
            ),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax([
                LabeledExprSyntax(expression: stringLiteral(id)),
            ]),
            rightParen: .rightParenToken()
        )
        .with(\.trailingTrivia, expr.trailingTrivia)
    }

    /// IDs contain only type names, letters, digits, `.` and `-`, so no escaping is needed.
    private static func stringLiteral(_ text: String) -> StringLiteralExprSyntax {
        StringLiteralExprSyntax(
            openingQuote: .stringQuoteToken(),
            segments: StringLiteralSegmentListSyntax([
                .stringSegment(StringSegmentSyntax(content: .stringSegment(text))),
            ]),
            closingQuote: .stringQuoteToken()
        )
    }
}
