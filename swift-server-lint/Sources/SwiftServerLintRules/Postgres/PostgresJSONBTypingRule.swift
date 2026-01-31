@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Suggests proper JSONB typing
public struct PostgresJSONBTypingRule: SyntaxVisitorRule {
    public typealias Visitor = PostgresJSONBTypingVisitor

    public static let identifier = "postgres.jsonb-typing"
    public static let name = "PostgreSQL JSONB Typing"
    public static let description = """
        JSONB columns should use proper Swift types with Codable conformance \
        instead of raw dictionary access.
        """
    public static let category = RuleCategory.postgres
    public static let defaultSeverity = Severity.info

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> PostgresJSONBTypingVisitor {
        PostgresJSONBTypingVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class PostgresJSONBTypingVisitor: RuleVisitor, @unchecked Sendable {
    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            if let typeAnnotation = binding.typeAnnotation?.type {
                let typeName = typeAnnotation.description.trimmingCharacters(in: .whitespaces)
                if typeName.contains("[String: Any]") || typeName.contains("[String: AnyObject]") {
                    // Check if this looks like JSON data
                    if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                        let name = identifier.identifier.text.lowercased()
                        if name.contains("json") || name.contains("data") || name.contains("metadata") || name.contains("payload") {
                            addDiagnostic(
                                at: node,
                                message: "Consider using a Codable type instead of [String: Any] for JSONB data.",
                                notes: [Note(message: "Typed Codable structs provide better type safety and performance")]
                            )
                        }
                    }
                }
            }
        }
        return .visitChildren
    }
}
