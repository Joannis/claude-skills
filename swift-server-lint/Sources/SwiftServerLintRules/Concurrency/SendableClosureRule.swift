@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects closures that should be Sendable
public struct SendableClosureRule: SyntaxVisitorRule {
    public typealias Visitor = SendableClosureVisitor

    public static let identifier = "concurrency.sendable-closure"
    public static let name = "Sendable Closure"
    public static let description = """
        Closures passed to Task.detached or sent across actor boundaries should be \
        marked @Sendable to ensure thread-safety.
        """
    public static let category = RuleCategory.concurrency
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> SendableClosureVisitor {
        SendableClosureVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class SendableClosureVisitor: RuleVisitor, @unchecked Sendable {
    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        // Check for Task.detached or similar
        if callee == "Task.detached" {
            // Check if closure has @Sendable
            if let trailingClosure = node.trailingClosure {
                if !hasSendableAttribute(trailingClosure) {
                    addDiagnostic(
                        at: trailingClosure,
                        message: "Closure passed to Task.detached should be @Sendable.",
                        notes: [Note(message: "Mark closure as @Sendable or ensure captured values are Sendable")]
                    )
                }
            }
        }
        return .visitChildren
    }

    private func hasSendableAttribute(_ closure: ClosureExprSyntax) -> Bool {
        if let signature = closure.signature {
            let attrs = signature.attributes
            for attr in attrs {
                if let attrSyntax = attr.as(AttributeSyntax.self) {
                    if attrSyntax.attributeName.description.contains("Sendable") {
                        return true
                    }
                }
            }
        }
        return false
    }
}
