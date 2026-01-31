@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects potential double completion of EventLoopPromise
public struct EventLoopPromiseDoubleCompleteRule: SyntaxVisitorRule {
    public typealias Visitor = EventLoopPromiseDoubleCompleteVisitor

    public static let identifier = "nio.promise-double-complete"
    public static let name = "Promise Double Completion"
    public static let description = """
        EventLoopPromise must be completed exactly once. Double completion causes a fatal error.
        """
    public static let category = RuleCategory.nio
    public static let defaultSeverity = Severity.error

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> EventLoopPromiseDoubleCompleteVisitor {
        EventLoopPromiseDoubleCompleteVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class EventLoopPromiseDoubleCompleteVisitor: RuleVisitor, @unchecked Sendable {
    private var promiseCompletions: [String: [FunctionCallExprSyntax]] = [:]
    private var currentFunction: String?

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        currentFunction = node.name.text
        promiseCompletions = [:]
        return .visitChildren
    }

    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        let completionMethods = ["succeed", "fail", "completeWith"]
        for method in completionMethods {
            if callee.contains(".\(method)") {
                // Extract promise name
                if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
                    let promiseName = memberAccess.base?.description.trimmingCharacters(in: .whitespaces) ?? ""
                    promiseCompletions[promiseName, default: []].append(node)
                }
            }
        }
        return .visitChildren
    }

    public override func visitPost(_ node: FunctionDeclSyntax) {
        // Check for multiple completions of same promise
        for (promiseName, completions) in promiseCompletions {
            if completions.count > 1 {
                // This could be conditional, so just warn
                for completion in completions.dropFirst() {
                    addDiagnostic(
                        at: completion,
                        message: "Promise '\(promiseName)' may be completed multiple times. Ensure only one completion path.",
                        notes: [Note(message: "Double completion of EventLoopPromise causes a fatal error")]
                    )
                }
            }
        }
    }
}
