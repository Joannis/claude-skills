@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects potential SQL injection vulnerabilities in PostgreSQL queries
public struct SQLInjectionRule: SyntaxVisitorRule {
    public typealias Visitor = SQLInjectionVisitor

    public static let identifier = "postgres.sql-injection"
    public static let name = "SQL Injection Prevention"
    public static let description = """
        Detects potential SQL injection vulnerabilities when constructing PostgreSQL queries. \
        String interpolation or concatenation in SQL queries can lead to SQL injection attacks. \
        Use parameterized queries with PostgresBindings instead.
        """
    public static let category = RuleCategory.postgres
    public static let defaultSeverity = Severity.error

    public static let triggeringExamples = [
        #"""
        let query = "SELECT * FROM users WHERE id = \(userId)"
        """#,
        #"""
        connection.query("SELECT * FROM users WHERE name = '" + name + "'")
        """#,
        #"""
        let sql = "DELETE FROM users WHERE id = " + String(id)
        """#
    ]

    public static let nonTriggeringExamples = [
        #"""
        connection.query("SELECT * FROM users WHERE id = $1", [userId])
        """#,
        #"""
        // swift-server-lint:unsafe-sql - validated input from enum
        let query = "SELECT * FROM users WHERE status = '\(status.rawValue)'"
        """#
    ]

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> SQLInjectionVisitor {
        let allowUnsafeComment = configuration.options["allow_unsafe_sql_with_comment"]?.boolValue ?? true
        return SQLInjectionVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity,
            allowUnsafeComment: allowUnsafeComment
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class SQLInjectionVisitor: RuleVisitor, @unchecked Sendable {
    private let allowUnsafeComment: Bool

    private let sqlPatterns = [
        "SELECT", "INSERT", "UPDATE", "DELETE", "DROP", "CREATE", "ALTER",
        "TRUNCATE", "GRANT", "REVOKE", "FROM", "WHERE", "JOIN"
    ]

    public init(
        context: RuleContext,
        ruleIdentifier: String,
        severity: Severity,
        allowUnsafeComment: Bool
    ) {
        self.allowUnsafeComment = allowUnsafeComment
        super.init(context: context, ruleIdentifier: ruleIdentifier, severity: severity)
    }

    public override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        // Check if this is a SQL string with interpolation
        guard containsSQLKeywords(node) else {
            return .visitChildren
        }

        // Check for string interpolation
        for segment in node.segments {
            if case .expressionSegment = segment {
                // Check for unsafe-sql comment if allowed
                if allowUnsafeComment && hasUnsafeSQLComment(node) {
                    return .visitChildren
                }

                addDiagnostic(
                    at: node,
                    message: "Potential SQL injection: avoid string interpolation in SQL queries. Use parameterized queries with bindings.",
                    fix: Fix(
                        description: "Use parameterized query with $1, $2, etc.",
                        replacement: "Use bindings instead of interpolation"
                    )
                )
                return .skipChildren
            }
        }

        return .visitChildren
    }

    public override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for string concatenation with +
        guard let operatorToken = node.operator.as(BinaryOperatorExprSyntax.self),
              operatorToken.operator.text == "+" else {
            return .visitChildren
        }

        // Check if either side is a SQL string
        let leftIsSQL = containsSQLInExpression(node.leftOperand)
        let rightIsSQL = containsSQLInExpression(node.rightOperand)

        if leftIsSQL || rightIsSQL {
            // Check for unsafe-sql comment
            if allowUnsafeComment && hasUnsafeSQLComment(node) {
                return .visitChildren
            }

            addDiagnostic(
                at: node,
                message: "Potential SQL injection: avoid string concatenation in SQL queries. Use parameterized queries.",
                fix: Fix(
                    description: "Use parameterized query with $1, $2, etc.",
                    replacement: "Use PostgresQuery with bindings"
                )
            )
        }

        return .visitChildren
    }

    private func containsSQLKeywords(_ node: StringLiteralExprSyntax) -> Bool {
        let content = node.segments.description.uppercased()
        return sqlPatterns.contains { content.contains($0) }
    }

    private func containsSQLInExpression(_ expr: ExprSyntax) -> Bool {
        if let stringLiteral = expr.as(StringLiteralExprSyntax.self) {
            return containsSQLKeywords(stringLiteral)
        }
        return false
    }

    private func hasUnsafeSQLComment(_ node: some SyntaxProtocol) -> Bool {
        // Check leading trivia for the comment
        let trivia = node.leadingTrivia.description
        return trivia.contains("swift-server-lint:unsafe-sql") ||
               trivia.contains("swiftserverlint:disable") ||
               trivia.contains("// unsafe-sql")
    }
}
