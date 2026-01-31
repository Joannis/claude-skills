@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects potential PostgreSQL connection leaks
public struct PostgresConnectionLeakRule: SyntaxVisitorRule {
    public typealias Visitor = PostgresConnectionLeakVisitor

    public static let identifier = "postgres.connection-leak"
    public static let name = "PostgreSQL Connection Management"
    public static let description = """
        PostgreSQL connections should be properly released back to the pool. \
        Use withConnection or ensure connections are closed in all code paths.
        """
    public static let category = RuleCategory.postgres
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> PostgresConnectionLeakVisitor {
        PostgresConnectionLeakVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class PostgresConnectionLeakVisitor: RuleVisitor, @unchecked Sendable {
    private var connectionVariables: Set<String> = []
    private var releasedConnections: Set<String> = []

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        connectionVariables = []
        releasedConnections = []
        return .visitChildren
    }

    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
               let initializer = binding.initializer?.value {
                let initDesc = initializer.description
                if initDesc.contains("getConnection") || initDesc.contains("leaseConnection") {
                    connectionVariables.insert(identifier.identifier.text)
                }
            }
        }
        return .visitChildren
    }

    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        // Check for withConnection pattern (which is safe)
        if callee.contains("withConnection") {
            // This is the safe pattern
            return .visitChildren
        }

        // Check for connection release
        if callee.contains("releaseConnection") || callee.contains("close") {
            if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
                let base = memberAccess.base?.description.trimmingCharacters(in: .whitespaces) ?? ""
                releasedConnections.insert(base)
            }
        }

        return .visitChildren
    }

    public override func visitPost(_ node: FunctionDeclSyntax) {
        for connVar in connectionVariables {
            if !releasedConnections.contains(connVar) {
                // Connection was obtained but not released
                addDiagnostic(
                    at: node,
                    message: "Connection '\(connVar)' may not be released. Use withConnection or ensure release in all paths.",
                    notes: [Note(message: "Unreleased connections can exhaust the connection pool")]
                )
            }
        }
    }
}
