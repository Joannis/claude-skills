@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects transaction management issues
public struct PostgresTransactionRule: SyntaxVisitorRule {
    public typealias Visitor = PostgresTransactionVisitor

    public static let identifier = "postgres.transaction"
    public static let name = "PostgreSQL Transaction Management"
    public static let description = """
        PostgreSQL transactions should be properly committed or rolled back. \
        Use withTransaction for automatic handling.
        """
    public static let category = RuleCategory.postgres
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> PostgresTransactionVisitor {
        PostgresTransactionVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class PostgresTransactionVisitor: RuleVisitor, @unchecked Sendable {
    private var hasBeginTransaction = false
    private var hasCommit = false
    private var hasRollback = false
    private var beginNode: FunctionCallExprSyntax?

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        hasBeginTransaction = false
        hasCommit = false
        hasRollback = false
        beginNode = nil
        return .visitChildren
    }

    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        // Safe pattern
        if callee.contains("withTransaction") {
            return .visitChildren
        }

        // Check for manual transaction management
        if callee.contains("BEGIN") || callee.contains("beginTransaction") {
            hasBeginTransaction = true
            beginNode = node
        }
        if callee.contains("COMMIT") || callee.contains("commit") {
            hasCommit = true
        }
        if callee.contains("ROLLBACK") || callee.contains("rollback") {
            hasRollback = true
        }

        return .visitChildren
    }

    public override func visitPost(_ node: FunctionDeclSyntax) {
        if hasBeginTransaction {
            if !hasCommit && !hasRollback {
                if let begin = beginNode {
                    addDiagnostic(
                        at: begin,
                        message: "Transaction started without explicit commit or rollback. Use withTransaction for automatic handling.",
                        notes: [Note(message: "Uncommitted transactions may hold locks and prevent other operations")]
                    )
                }
            } else if hasCommit && !hasRollback {
                if let begin = beginNode {
                    addDiagnostic(
                        at: begin,
                        message: "Transaction has commit but no rollback path. Consider error handling.",
                        notes: [Note(message: "Use withTransaction for automatic rollback on error")]
                    )
                }
            }
        }
    }
}
