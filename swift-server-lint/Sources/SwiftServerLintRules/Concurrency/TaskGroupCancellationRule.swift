@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects missing cancellation handling in TaskGroups
public struct TaskGroupCancellationRule: SyntaxVisitorRule {
    public typealias Visitor = TaskGroupCancellationVisitor

    public static let identifier = "concurrency.task-group-cancellation"
    public static let name = "TaskGroup Cancellation Handling"
    public static let description = """
        TaskGroup children should check for cancellation to allow graceful shutdown. \
        Without cancellation checks, task groups may continue work even after cancellation.
        """
    public static let category = RuleCategory.concurrency
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> TaskGroupCancellationVisitor {
        TaskGroupCancellationVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class TaskGroupCancellationVisitor: RuleVisitor, @unchecked Sendable {
    private var isInTaskGroup = false
    private var isInAddTask = false
    private var hasCancellationCheck = false
    private var addTaskNode: FunctionCallExprSyntax?

    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        if callee.contains("withTaskGroup") || callee.contains("withThrowingTaskGroup") {
            isInTaskGroup = true
        }

        if isInTaskGroup && (callee.contains("addTask") || callee.contains("group.addTask")) {
            isInAddTask = true
            hasCancellationCheck = false
            addTaskNode = node
        }

        // Check for cancellation checks
        if isInAddTask {
            if callee.contains("Task.isCancelled") ||
               callee.contains("Task.checkCancellation") ||
               callee.contains("isCancelled") {
                hasCancellationCheck = true
            }
        }

        return .visitChildren
    }

    public override func visitPost(_ node: FunctionCallExprSyntax) {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        if callee.contains("addTask") && isInAddTask {
            if !hasCancellationCheck, let taskNode = addTaskNode {
                addDiagnostic(
                    at: taskNode,
                    message: "TaskGroup child task doesn't check for cancellation. Consider using Task.checkCancellation() or Task.isCancelled.",
                    notes: [Note(message: "Add cancellation checks for cooperative cancellation in long-running tasks")]
                )
            }
            isInAddTask = false
            addTaskNode = nil
        }

        if callee.contains("withTaskGroup") || callee.contains("withThrowingTaskGroup") {
            isInTaskGroup = false
        }
    }

    public override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        if isInAddTask {
            let expr = node.expression.description
            if expr.contains("checkCancellation") {
                hasCancellationCheck = true
            }
        }
        return .visitChildren
    }

    public override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        if isInAddTask {
            let condition = node.conditions.description
            if condition.contains("isCancelled") {
                hasCancellationCheck = true
            }
        }
        return .visitChildren
    }
}
