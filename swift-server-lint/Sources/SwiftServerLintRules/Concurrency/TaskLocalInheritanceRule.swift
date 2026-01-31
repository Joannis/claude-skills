@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects TaskLocal access patterns
public struct TaskLocalInheritanceRule: SyntaxVisitorRule {
    public typealias Visitor = TaskLocalInheritanceVisitor

    public static let identifier = "concurrency.task-local-inheritance"
    public static let name = "TaskLocal Inheritance"
    public static let description = """
        TaskLocal values are inherited by child tasks but not by Task.detached. \
        Ensure TaskLocal values are properly propagated when needed.
        """
    public static let category = RuleCategory.concurrency
    public static let defaultSeverity = Severity.info

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> TaskLocalInheritanceVisitor {
        TaskLocalInheritanceVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class TaskLocalInheritanceVisitor: RuleVisitor, @unchecked Sendable {
    private var taskLocalNames: Set<String> = []
    private var isInDetachedTask = false

    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for @TaskLocal
        for attribute in node.attributes {
            if let attr = attribute.as(AttributeSyntax.self) {
                if attr.attributeName.description.contains("TaskLocal") {
                    for binding in node.bindings {
                        if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                            taskLocalNames.insert(identifier.identifier.text)
                        }
                    }
                }
            }
        }
        return .visitChildren
    }

    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)
        if callee == "Task.detached" {
            isInDetachedTask = true
        }
        return .visitChildren
    }

    public override func visitPost(_ node: FunctionCallExprSyntax) {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)
        if callee == "Task.detached" {
            isInDetachedTask = false
        }
    }

    public override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if isInDetachedTask {
            let memberName = node.declName.baseName.text
            if taskLocalNames.contains(memberName) {
                addDiagnostic(
                    at: node,
                    message: "TaskLocal '\(memberName)' accessed in Task.detached. TaskLocal values are not inherited by detached tasks.",
                    notes: [Note(message: "Pass the value explicitly or use Task {} instead")]
                )
            }
        }
        return .visitChildren
    }
}
