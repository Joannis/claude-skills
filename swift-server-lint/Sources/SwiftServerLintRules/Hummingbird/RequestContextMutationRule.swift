@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects RequestContext mutation issues
public struct RequestContextMutationRule: SyntaxVisitorRule {
    public typealias Visitor = RequestContextMutationVisitor

    public static let identifier = "hummingbird.request-context-mutation"
    public static let name = "RequestContext Mutation"
    public static let description = """
        RequestContext should be passed as inout for mutation. Modifying a copy won't \
        persist changes across middleware.
        """
    public static let category = RuleCategory.hummingbird
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> RequestContextMutationVisitor {
        RequestContextMutationVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class RequestContextMutationVisitor: RuleVisitor, @unchecked Sendable {
    private var contextParameters: [String: FunctionDeclSyntax] = [:]

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check parameters for RequestContext without inout
        for param in node.signature.parameterClause.parameters {
            let typeName = param.type.description.trimmingCharacters(in: .whitespaces)
            if typeName.contains("RequestContext") && !typeName.contains("inout") {
                contextParameters[param.firstName.text] = node
            }
        }
        return .visitChildren
    }

    public override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for assignment to context properties
        guard let op = node.operator.as(BinaryOperatorExprSyntax.self),
              op.operator.text == "=" else {
            return .visitChildren
        }

        let leftSide = node.leftOperand.description.trimmingCharacters(in: .whitespaces)
        for (paramName, _) in contextParameters {
            if leftSide.hasPrefix("\(paramName).") {
                addDiagnostic(
                    at: node,
                    message: "Modifying RequestContext '\(paramName)' without inout. Changes won't persist.",
                    fix: Fix(
                        description: "Add inout to parameter",
                        replacement: "inout context: RequestContext"
                    )
                )
            }
        }
        return .visitChildren
    }
}
