@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Suggests batch inserts for loops
public struct PostgresBatchInsertRule: SyntaxVisitorRule {
    public typealias Visitor = PostgresBatchInsertVisitor

    public static let identifier = "postgres.batch-insert"
    public static let name = "PostgreSQL Batch Insert"
    public static let description = """
        Single inserts in a loop are inefficient. Use batch inserts or COPY for better \
        performance when inserting multiple rows.
        """
    public static let category = RuleCategory.postgres
    public static let defaultSeverity = Severity.info

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> PostgresBatchInsertVisitor {
        PostgresBatchInsertVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class PostgresBatchInsertVisitor: RuleVisitor, @unchecked Sendable {
    private var isInLoop = false
    private var loopNode: (any SyntaxProtocol)?

    public override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        isInLoop = true
        loopNode = node
        return .visitChildren
    }

    public override func visitPost(_ node: ForStmtSyntax) {
        isInLoop = false
        loopNode = nil
    }

    public override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        isInLoop = true
        loopNode = node
        return .visitChildren
    }

    public override func visitPost(_ node: WhileStmtSyntax) {
        isInLoop = false
        loopNode = nil
    }

    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard isInLoop else { return .visitChildren }

        // Check for INSERT queries in loop
        if let firstArg = node.arguments.first?.expression.as(StringLiteralExprSyntax.self) {
            let query = firstArg.segments.description.uppercased()
            if query.contains("INSERT") {
                addDiagnostic(
                    at: node,
                    message: "INSERT in loop is inefficient. Use batch insert with multiple VALUES or COPY.",
                    notes: [Note(message: "Batch inserts can be orders of magnitude faster")]
                )
            }
        }

        return .visitChildren
    }
}
