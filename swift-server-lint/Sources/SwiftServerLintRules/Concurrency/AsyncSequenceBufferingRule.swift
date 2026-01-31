@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects unbounded AsyncSequence buffering
public struct AsyncSequenceBufferingRule: SyntaxVisitorRule {
    public typealias Visitor = AsyncSequenceBufferingVisitor

    public static let identifier = "concurrency.async-sequence-buffering"
    public static let name = "AsyncSequence Buffering"
    public static let description = """
        AsyncStream without explicit buffering policy can lead to unbounded memory growth. \
        Consider specifying a buffering policy.
        """
    public static let category = RuleCategory.concurrency
    public static let defaultSeverity = Severity.info

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> AsyncSequenceBufferingVisitor {
        AsyncSequenceBufferingVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class AsyncSequenceBufferingVisitor: RuleVisitor, @unchecked Sendable {
    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        if callee.contains("AsyncStream") {
            // Check if bufferingPolicy is specified
            var hasBufferingPolicy = false
            for argument in node.arguments {
                if argument.label?.text == "bufferingPolicy" {
                    hasBufferingPolicy = true
                    break
                }
            }

            if !hasBufferingPolicy {
                addDiagnostic(
                    at: node,
                    message: "AsyncStream without explicit bufferingPolicy. Consider specifying .bounded or .bufferingNewest.",
                    notes: [Note(message: "Default unbounded buffering can lead to memory issues with fast producers")]
                )
            }
        }
        return .visitChildren
    }
}
