@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Reminds about keeping Swift enums in sync with PostgreSQL
public struct PostgresEnumSyncRule: SyntaxVisitorRule {
    public typealias Visitor = PostgresEnumSyncVisitor

    public static let identifier = "postgres.enum-sync"
    public static let name = "PostgreSQL Enum Synchronization"
    public static let description = """
        Swift enums used with PostgreSQL should stay in sync with database enum types. \
        Consider adding a comment documenting the corresponding PostgreSQL type.
        """
    public static let category = RuleCategory.postgres
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> PostgresEnumSyncVisitor {
        PostgresEnumSyncVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class PostgresEnumSyncVisitor: RuleVisitor, @unchecked Sendable {
    public override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check if enum conforms to PostgreSQL-related protocols
        guard let inheritanceClause = node.inheritanceClause else {
            return .visitChildren
        }

        let types = inheritanceClause.inheritedTypes.map { $0.type.description.trimmingCharacters(in: .whitespaces) }
        let postgresProtocols = ["PostgresEnum", "RawRepresentable", "PostgresDecodable", "PostgresEncodable"]

        let isPostgresEnum = types.contains(where: { type in
            postgresProtocols.contains(where: { type.contains($0) })
        }) && types.contains("String")

        if isPostgresEnum {
            // Check for documentation comment about PostgreSQL
            let hasPostgresDoc = node.leadingTrivia.description.lowercased().contains("postgres")

            if !hasPostgresDoc {
                addDiagnostic(
                    at: node,
                    message: "Enum '\(node.name.text)' appears to be used with PostgreSQL. Add a comment documenting the corresponding PostgreSQL type.",
                    notes: [Note(message: "This helps keep Swift and PostgreSQL enums in sync during schema changes")]
                )
            }
        }

        return .visitChildren
    }
}
