@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Suggests using prepared statements
public struct PostgresPreparedStatementRule: SyntaxVisitorRule {
    public typealias Visitor = PostgresPreparedStatementVisitor

    public static let identifier = "postgres.prepared-statement"
    public static let name = "PostgreSQL Prepared Statements"
    public static let description = """
        Repeated queries should use prepared statements for better performance. \
        PostgresQuery automatically prepares statements on repeated use.
        """
    public static let category = RuleCategory.postgres
    public static let defaultSeverity = Severity.info

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> PostgresPreparedStatementVisitor {
        PostgresPreparedStatementVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class PostgresPreparedStatementVisitor: RuleVisitor, @unchecked Sendable {
    private var queryStrings: [String: [FunctionCallExprSyntax]] = [:]

    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        if callee.contains(".query") {
            if let firstArg = node.arguments.first?.expression.as(StringLiteralExprSyntax.self) {
                let queryText = firstArg.segments.description
                queryStrings[queryText, default: []].append(node)
            }
        }
        return .visitChildren
    }

    public override func visitPost(_ node: SourceFileSyntax) {
        for (_, nodes) in queryStrings {
            if nodes.count > 2 {
                for queryNode in nodes {
                    addDiagnostic(
                        at: queryNode,
                        message: "Query appears \(nodes.count) times. Consider using a prepared statement or PostgresQuery type.",
                        notes: [Note(message: "Prepared statements improve performance for repeated queries")]
                    )
                }
            }
        }
    }
}
