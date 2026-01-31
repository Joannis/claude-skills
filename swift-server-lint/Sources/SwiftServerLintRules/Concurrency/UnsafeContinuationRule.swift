@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects unsafe continuation usage
public struct UnsafeContinuationRule: SyntaxVisitorRule {
    public typealias Visitor = UnsafeContinuationVisitor

    public static let identifier = "concurrency.unsafe-continuation"
    public static let name = "Unsafe Continuation Usage"
    public static let description = """
        UnsafeContinuation must be resumed exactly once. Prefer CheckedContinuation \
        during development to catch resume errors.
        """
    public static let category = RuleCategory.concurrency
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> UnsafeContinuationVisitor {
        UnsafeContinuationVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class UnsafeContinuationVisitor: RuleVisitor, @unchecked Sendable {
    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        if callee.contains("withUnsafeContinuation") || callee.contains("withUnsafeThrowingContinuation") {
            addDiagnostic(
                at: node,
                message: "Using UnsafeContinuation. Consider using CheckedContinuation for safety during development.",
                fix: Fix(
                    description: "Replace with checked variant",
                    replacement: callee.replacingOccurrences(of: "Unsafe", with: "Checked")
                ),
                notes: [Note(message: "CheckedContinuation will trap if resumed twice or not at all")]
            )
        }
        return .visitChildren
    }
}
