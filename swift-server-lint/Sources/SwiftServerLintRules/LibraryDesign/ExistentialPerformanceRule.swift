@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Warns about existential type performance
public struct ExistentialPerformanceRule: SyntaxVisitorRule {
    public typealias Visitor = ExistentialPerformanceVisitor

    public static let identifier = "library-design.existential-performance"
    public static let name = "Existential Performance"
    public static let description = """
        Existential types (any Protocol) have runtime overhead. For hot paths in library \
        code, consider using generics or opaque types (some Protocol) instead.
        """
    public static let category = RuleCategory.libraryDesign
    public static let defaultSeverity = Severity.info

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> ExistentialPerformanceVisitor {
        ExistentialPerformanceVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class ExistentialPerformanceVisitor: RuleVisitor, @unchecked Sendable {
    private var isInPublicAPI = false

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        isInPublicAPI = node.modifiers.contains { $0.name.text == "public" || $0.name.text == "open" }
        return .visitChildren
    }

    public override func visitPost(_ node: FunctionDeclSyntax) {
        isInPublicAPI = false
    }

    public override func visit(_ node: SomeOrAnyTypeSyntax) -> SyntaxVisitorContinueKind {
        guard isInPublicAPI else { return .visitChildren }

        if node.someOrAnySpecifier.tokenKind == .keyword(.any) {
            addDiagnostic(
                at: node,
                message: "Existential type 'any' in public API has runtime overhead. Consider using 'some' or generics for hot paths.",
                notes: [Note(message: "Existentials require heap allocation and dynamic dispatch")]
            )
        }
        return .visitChildren
    }
}
