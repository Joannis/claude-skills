@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Warns about force unwrap usage
public struct ForceUnwrapRule: SyntaxVisitorRule {
    public typealias Visitor = ForceUnwrapVisitor

    public static let identifier = "general.force-unwrap"
    public static let name = "Force Unwrap"
    public static let description = """
        Force unwrapping (!) can cause crashes. Use optional binding, nil coalescing, \
        or guard statements instead.
        """
    public static let category = RuleCategory.general
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> ForceUnwrapVisitor {
        ForceUnwrapVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class ForceUnwrapVisitor: RuleVisitor, @unchecked Sendable {
    public override func visit(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for safety comment
        if hasSafetyComment(node) {
            return .visitChildren
        }

        addDiagnostic(
            at: node,
            message: "Force unwrap can crash. Use if let, guard let, or ?? instead.",
            fix: Fix(
                description: "Use optional binding",
                replacement: "if let value = optional { ... }"
            )
        )
        return .visitChildren
    }

    private func hasSafetyComment(_ node: some SyntaxProtocol) -> Bool {
        let trivia = node.leadingTrivia.description.lowercased()
        return trivia.contains("safe") || trivia.contains("guaranteed") || trivia.contains("known")
    }
}
