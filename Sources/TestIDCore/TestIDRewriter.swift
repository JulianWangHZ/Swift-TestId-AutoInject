import SwiftSyntax

/// Appends `.accessibilityIdentifier("{screen}-{name}-{type}")` to SwiftUI controls.
/// The modifier goes on the same line as the call, so line numbers do not shift.
public final class TestIDRewriter: SyntaxRewriter {
    public private(set) var injected: [String] = []
    private let screen: String
    private var typeDepth = 0
    private var usedIDs: [String: Int] = [:]

    /// `screen` is the id prefix, usually `IDNaming.screen(fromFileName:)`.
    public init(screen: String) {
        self.screen = screen
        super.init(viewMode: .sourceAccurate)
    }

    public override func visit(_ node: StructDeclSyntax) -> DeclSyntax {
        typeDepth += 1
        defer { typeDepth -= 1 }
        return super.visit(node)
    }

    public override func visit(_ node: ClassDeclSyntax) -> DeclSyntax {
        typeDepth += 1
        defer { typeDepth -= 1 }
        return super.visit(node)
    }

    public override func visit(_ node: ExtensionDeclSyntax) -> DeclSyntax {
        typeDepth += 1
        defer { typeDepth -= 1 }
        return super.visit(node)
    }

    public override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
        let visited = super.visit(node)
        guard
            typeDepth > 0,
            let control = node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
            IDNaming.controls.contains(control)
        else { return visited }

        let chain = Self.modifierChain(above: node)
        guard !chain.contains(where: { Self.modifierName($0) == "accessibilityIdentifier" }) else {
            return visited
        }

        let signals = SignalExtractor.signals(for: node, chain: chain)
        let id = uniqueID(IDNaming.baseID(screen: screen, control: control, signals: signals))
        injected.append(id)
        return ExprSyntax(Self.appendModifier(to: visited, id: id))
    }

    /// Same base twice in one file: the second gets `-2`, matching the web injector.
    private func uniqueID(_ base: String) -> String {
        let count = usedIDs[base, default: 0] + 1
        usedIDs[base] = count
        return count == 1 ? base : "\(base)-\(count)"
    }

    /// Modifier calls applied to `call`, innermost first: `.padding().accessibilityLabel("x")`.
    static func modifierChain(above call: FunctionCallExprSyntax) -> [FunctionCallExprSyntax] {
        var chain: [FunctionCallExprSyntax] = []
        var current = Syntax(call)
        while let member = current.parent?.as(MemberAccessExprSyntax.self),
              member.base?.id == current.id,
              let outer = member.parent?.as(FunctionCallExprSyntax.self) {
            chain.append(outer)
            current = Syntax(outer)
        }
        return chain
    }

    private static func modifierName(_ call: FunctionCallExprSyntax) -> String? {
        call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
    }

    private static func appendModifier(to expr: ExprSyntax, id: String) -> FunctionCallExprSyntax {
        FunctionCallExprSyntax(
            calledExpression: MemberAccessExprSyntax(
                base: expr.with(\.trailingTrivia, []),
                period: .periodToken(),
                declName: DeclReferenceExprSyntax(baseName: .identifier("accessibilityIdentifier"))
            ),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax([LabeledExprSyntax(expression: stringLiteral(id))]),
            rightParen: .rightParenToken()
        )
        .with(\.trailingTrivia, expr.trailingTrivia)
    }

    private static func stringLiteral(_ text: String) -> StringLiteralExprSyntax {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return StringLiteralExprSyntax(
            openingQuote: .stringQuoteToken(),
            segments: StringLiteralSegmentListSyntax([
                .stringSegment(StringSegmentSyntax(content: .stringSegment(escaped))),
            ]),
            closingQuote: .stringQuoteToken()
        )
    }
}
