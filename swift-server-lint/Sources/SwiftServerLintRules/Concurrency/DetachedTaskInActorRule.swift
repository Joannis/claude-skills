@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects Task.detached usage inside actors
public struct DetachedTaskInActorRule: SyntaxVisitorRule {
    public typealias Visitor = DetachedTaskInActorVisitor

    public static let identifier = "concurrency.detached-task-in-actor"
    public static let name = "Detached Task in Actor"
    public static let description = """
        Task.detached inside an actor loses actor isolation and can lead to data races \
        if accessing actor state. Use Task {} instead to inherit actor context.
        """
    public static let category = RuleCategory.concurrency
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> DetachedTaskInActorVisitor {
        DetachedTaskInActorVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class DetachedTaskInActorVisitor: RuleVisitor, @unchecked Sendable {
    private var isInActor = false
    private var actorDepth = 0

    public override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        isInActor = true
        actorDepth += 1
        return .visitChildren
    }

    public override func visitPost(_ node: ActorDeclSyntax) {
        actorDepth -= 1
        isInActor = actorDepth > 0
    }

    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard isInActor else { return .visitChildren }

        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)
        if callee == "Task.detached" {
            addDiagnostic(
                at: node,
                message: "Task.detached inside actor loses actor isolation. Use Task {} to inherit actor context.",
                fix: Fix(
                    description: "Replace with Task {}",
                    replacement: "Task"
                )
            )
        }
        return .visitChildren
    }
}
