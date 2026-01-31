@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects blocking operations on MainActor
public struct MainActorBlockingRule: SyntaxVisitorRule {
    public typealias Visitor = MainActorBlockingVisitor

    public static let identifier = "concurrency.main-actor-blocking"
    public static let name = "MainActor Blocking Prevention"
    public static let description = """
        Blocking operations on @MainActor can freeze the UI. Use Task {} to move \
        blocking work off the main thread.
        """
    public static let category = RuleCategory.concurrency
    public static let defaultSeverity = Severity.error

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> MainActorBlockingVisitor {
        MainActorBlockingVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class MainActorBlockingVisitor: RuleVisitor, @unchecked Sendable {
    private var isOnMainActor = false

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        isOnMainActor = hasMainActorAttribute(node.attributes)
        return .visitChildren
    }

    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if hasMainActorAttribute(node.attributes) {
            isOnMainActor = true
        }
        return .visitChildren
    }

    public override func visitPost(_ node: ClassDeclSyntax) {
        isOnMainActor = false
    }

    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard isOnMainActor else { return .visitChildren }

        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)
        let blockingCalls = ["Thread.sleep", "sleep", "usleep", ".wait()"]

        for blocking in blockingCalls {
            if callee.contains(blocking) {
                addDiagnostic(
                    at: node,
                    message: "Blocking call '\(blocking)' on MainActor will freeze the UI.",
                    fix: Fix(
                        description: "Move to background Task",
                        replacement: "Task.detached { ... }"
                    )
                )
            }
        }
        return .visitChildren
    }

    private func hasMainActorAttribute(_ attributes: AttributeListSyntax) -> Bool {
        for attribute in attributes {
            if let attr = attribute.as(AttributeSyntax.self) {
                let name = attr.attributeName.description.trimmingCharacters(in: .whitespaces)
                if name == "MainActor" || name == "main" {
                    return true
                }
            }
        }
        return false
    }
}
