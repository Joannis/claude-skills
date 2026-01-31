@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects potential NIO deadlock patterns
public struct NIODeadlockRule: SyntaxVisitorRule {
    public typealias Visitor = NIODeadlockVisitor

    public static let identifier = "nio.deadlock"
    public static let name = "NIO Deadlock Prevention"
    public static let description = """
        Calling .wait() on a future from within an EventLoop callback causes deadlock. \
        Use flatMap/whenComplete instead.
        """
    public static let category = RuleCategory.nio
    public static let defaultSeverity = Severity.error

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> NIODeadlockVisitor {
        NIODeadlockVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class NIODeadlockVisitor: RuleVisitor, @unchecked Sendable {
    private var isInEventLoopCallback = false
    private var callbackDepth = 0

    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        // Track entering EventLoop callbacks
        let callbacks = ["flatMap", "map", "whenComplete", "whenSuccess", "whenFailure", "always"]
        for callback in callbacks {
            if callee.hasSuffix(".\(callback)") {
                isInEventLoopCallback = true
                callbackDepth += 1
            }
        }

        // Check for .wait() calls inside callbacks
        if callee.hasSuffix(".wait()") || callee.hasSuffix(".wait") {
            if isInEventLoopCallback {
                addDiagnostic(
                    at: node,
                    message: "Calling .wait() inside EventLoop callback causes deadlock.",
                    fix: Fix(
                        description: "Use flatMap instead of wait",
                        replacement: ".flatMap { result in ... }"
                    )
                )
            }
        }

        return .visitChildren
    }

    public override func visitPost(_ node: FunctionCallExprSyntax) {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)
        let callbacks = ["flatMap", "map", "whenComplete", "whenSuccess", "whenFailure", "always"]
        for callback in callbacks {
            if callee.hasSuffix(".\(callback)") {
                callbackDepth -= 1
                if callbackDepth == 0 {
                    isInEventLoopCallback = false
                }
            }
        }
    }
}
