@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Warns about Double usage for monetary values
public struct PostgresDecimalPrecisionRule: SyntaxVisitorRule {
    public typealias Visitor = PostgresDecimalPrecisionVisitor

    public static let identifier = "postgres.decimal-precision"
    public static let name = "PostgreSQL Decimal Precision"
    public static let description = """
        Using Double for monetary or precise decimal values loses precision. \
        Use Decimal type instead.
        """
    public static let category = RuleCategory.postgres
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> PostgresDecimalPrecisionVisitor {
        PostgresDecimalPrecisionVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class PostgresDecimalPrecisionVisitor: RuleVisitor, @unchecked Sendable {
    private let monetaryPatterns = ["price", "amount", "cost", "total", "balance", "money", "currency", "fee", "rate"]

    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
               let typeAnnotation = binding.typeAnnotation?.type {
                let varName = identifier.identifier.text.lowercased()
                let typeName = typeAnnotation.description.trimmingCharacters(in: .whitespaces)

                // Check if variable name suggests monetary value
                let isMonetery = monetaryPatterns.contains { varName.contains($0) }
                let isDouble = typeName == "Double" || typeName == "Float"

                if isMonetery && isDouble {
                    addDiagnostic(
                        at: node,
                        message: "Using \(typeName) for '\(identifier.identifier.text)' may cause precision loss. Use Decimal for monetary values.",
                        fix: Fix(
                            description: "Change to Decimal",
                            replacement: "Decimal"
                        )
                    )
                }
            }
        }
        return .visitChildren
    }
}
