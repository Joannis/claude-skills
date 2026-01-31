@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects NIO to async/await bridging patterns
public struct NIOAsyncBridgingRule: SyntaxVisitorRule {
    public typealias Visitor = NIOAsyncBridgingVisitor

    public static let identifier = "nio.async-bridging"
    public static let name = "NIO Async Bridging"
    public static let description = """
        When bridging NIO futures to async/await, use the built-in .get() method \
        instead of manual withCheckedContinuation.
        """
    public static let category = RuleCategory.nio
    public static let defaultSeverity = Severity.info

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> NIOAsyncBridgingVisitor {
        NIOAsyncBridgingVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class NIOAsyncBridgingVisitor: RuleVisitor, @unchecked Sendable {
    private var isInContinuation = false

    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        if callee.contains("withCheckedContinuation") || callee.contains("withCheckedThrowingContinuation") {
            isInContinuation = true
        }

        // Check for whenComplete inside continuation
        if isInContinuation && callee.contains("whenComplete") {
            addDiagnostic(
                at: node,
                message: "Manual continuation bridging for NIO future. Use future.get() instead.",
                fix: Fix(
                    description: "Replace with .get()",
                    replacement: "try await future.get()"
                )
            )
        }

        return .visitChildren
    }

    public override func visitPost(_ node: FunctionCallExprSyntax) {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)
        if callee.contains("withCheckedContinuation") || callee.contains("withCheckedThrowingContinuation") {
            isInContinuation = false
        }
    }
}
