@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Warns about force try usage
public struct ForceTryRule: SyntaxVisitorRule {
    public typealias Visitor = ForceTryVisitor

    public static let identifier = "general.force-try"
    public static let name = "Force Try"
    public static let description = """
        Force try (try!) can cause crashes. Use do-catch, try?, or propagate the error.
        """
    public static let category = RuleCategory.general
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> ForceTryVisitor {
        ForceTryVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class ForceTryVisitor: RuleVisitor, @unchecked Sendable {
    public override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for try!
        if node.questionOrExclamationMark?.tokenKind == .exclamationMark {
            // Check for safety comment
            if hasSafetyComment(node) {
                return .visitChildren
            }

            addDiagnostic(
                at: node,
                message: "Force try can crash. Use do-catch or propagate the error with 'throws'.",
                fix: Fix(
                    description: "Use do-catch",
                    replacement: "do { try ... } catch { ... }"
                )
            )
        }
        return .visitChildren
    }

    private func hasSafetyComment(_ node: some SyntaxProtocol) -> Bool {
        let trivia = node.leadingTrivia.description.lowercased()
        return trivia.contains("safe") || trivia.contains("guaranteed") || trivia.contains("known")
    }
}
