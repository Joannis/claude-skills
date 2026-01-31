@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects middleware ordering issues
public struct MiddlewareOrderRule: SyntaxVisitorRule {
    public typealias Visitor = MiddlewareOrderVisitor

    public static let identifier = "hummingbird.middleware-order"
    public static let name = "Middleware Order"
    public static let description = """
        Middleware order matters. Authentication middleware should come before \
        authorization, and logging should typically be first.
        """
    public static let category = RuleCategory.hummingbird
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> MiddlewareOrderVisitor {
        MiddlewareOrderVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class MiddlewareOrderVisitor: RuleVisitor, @unchecked Sendable {
    private var middlewareStack: [(name: String, node: FunctionCallExprSyntax)] = []

    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        if callee.contains("addMiddleware") || callee.contains(".add(") {
            if let firstArg = node.arguments.first {
                let middlewareName = firstArg.expression.description
                middlewareStack.append((name: middlewareName, node: node))
            }
        }

        return .visitChildren
    }

    public override func visitPost(_ node: SourceFileSyntax) {
        var seenAuth = false

        for (name, middlewareNode) in middlewareStack {
            let lowerName = name.lowercased()

            // Check if authorization comes before authentication
            if lowerName.contains("authoriz") {
                if !seenAuth {
                    addDiagnostic(
                        at: middlewareNode,
                        message: "Authorization middleware added before authentication. Authentication should come first.",
                        notes: [Note(message: "Reorder middleware so authentication runs before authorization")]
                    )
                }
            }

            if lowerName.contains("authenti") || lowerName.contains("authn") {
                seenAuth = true
            }
        }
    }
}
