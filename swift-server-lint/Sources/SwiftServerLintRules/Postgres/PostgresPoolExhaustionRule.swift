@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects patterns that could exhaust the connection pool
public struct PostgresPoolExhaustionRule: SyntaxVisitorRule {
    public typealias Visitor = PostgresPoolExhaustionVisitor

    public static let identifier = "postgres.pool-exhaustion"
    public static let name = "PostgreSQL Pool Exhaustion"
    public static let description = """
        Patterns that hold connections while waiting for other operations can exhaust \
        the connection pool and cause deadlock.
        """
    public static let category = RuleCategory.postgres
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> PostgresPoolExhaustionVisitor {
        PostgresPoolExhaustionVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class PostgresPoolExhaustionVisitor: RuleVisitor, @unchecked Sendable {
    private var isInWithConnection = false
    private var nestedConnectionRequests = 0

    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        if callee.contains("withConnection") {
            if isInWithConnection {
                nestedConnectionRequests += 1
                addDiagnostic(
                    at: node,
                    message: "Nested connection request inside withConnection. This can exhaust the pool.",
                    notes: [Note(message: "Reuse the existing connection or restructure to avoid nested requests")]
                )
            }
            isInWithConnection = true
        }

        return .visitChildren
    }

    public override func visitPost(_ node: FunctionCallExprSyntax) {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)
        if callee.contains("withConnection") {
            isInWithConnection = nestedConnectionRequests > 0
            if nestedConnectionRequests > 0 {
                nestedConnectionRequests -= 1
            }
        }
    }
}
