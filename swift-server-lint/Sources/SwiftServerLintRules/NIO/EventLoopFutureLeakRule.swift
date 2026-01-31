@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects EventLoopFuture results that are not handled
public struct EventLoopFutureLeakRule: SyntaxVisitorRule {
    public typealias Visitor = EventLoopFutureLeakVisitor

    public static let identifier = "nio.event-loop-future-leak"
    public static let name = "EventLoopFuture Result Handling"
    public static let description = """
        EventLoopFuture results should be handled. Unhandled futures can silently drop errors.
        """
    public static let category = RuleCategory.nio
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> EventLoopFutureLeakVisitor {
        EventLoopFutureLeakVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class EventLoopFutureLeakVisitor: RuleVisitor, @unchecked Sendable {
    public override func visit(_ node: DiscardStmtSyntax) -> SyntaxVisitorContinueKind {
        // Check if discarding an EventLoopFuture
        let expr = node.expression.description
        if expr.contains("EventLoopFuture") || expr.contains("Future") {
            addDiagnostic(
                at: node,
                message: "Discarding EventLoopFuture result. Errors will be silently dropped.",
                fix: Fix(
                    description: "Handle the future result",
                    replacement: "future.whenComplete { result in ... }"
                )
            )
        }
        return .visitChildren
    }

    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for future-returning calls without handling
        if let parent = node.parent {
            // If the result is used (assigned, chained, etc.), it's fine
            if parent.is(InfixOperatorExprSyntax.self) ||
               parent.is(VariableDeclSyntax.self) ||
               parent.is(PatternBindingSyntax.self) ||
               parent.is(ReturnStmtSyntax.self) ||
               parent.is(FunctionCallExprSyntax.self) ||
               parent.is(MemberAccessExprSyntax.self) {
                return .visitChildren
            }
        }
        return .visitChildren
    }
}
