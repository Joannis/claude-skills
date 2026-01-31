@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects potential NULL handling issues
public struct PostgresNullHandlingRule: SyntaxVisitorRule {
    public typealias Visitor = PostgresNullHandlingVisitor

    public static let identifier = "postgres.null-handling"
    public static let name = "PostgreSQL NULL Handling"
    public static let description = """
        Comparing with NULL using = or != doesn't work as expected in SQL. \
        Use IS NULL or IS NOT NULL instead.
        """
    public static let category = RuleCategory.postgres
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> PostgresNullHandlingVisitor {
        PostgresNullHandlingVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class PostgresNullHandlingVisitor: RuleVisitor, @unchecked Sendable {
    public override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        let content = node.segments.description.uppercased()

        // Check for SQL-like content
        let sqlKeywords = ["SELECT", "WHERE", "INSERT", "UPDATE", "DELETE"]
        guard sqlKeywords.contains(where: { content.contains($0) }) else {
            return .visitChildren
        }

        // Check for = NULL or != NULL patterns
        if content.contains("= NULL") && !content.contains("IS NULL") {
            addDiagnostic(
                at: node,
                message: "Comparing with NULL using '=' doesn't work. Use 'IS NULL' instead.",
                fix: Fix(
                    description: "Replace with IS NULL",
                    replacement: "IS NULL"
                )
            )
        }
        if content.contains("!= NULL") || content.contains("<> NULL") {
            addDiagnostic(
                at: node,
                message: "Comparing with NULL using '!=' doesn't work. Use 'IS NOT NULL' instead.",
                fix: Fix(
                    description: "Replace with IS NOT NULL",
                    replacement: "IS NOT NULL"
                )
            )
        }

        return .visitChildren
    }
}
