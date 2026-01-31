@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Suggests streaming for large response bodies
public struct ResponseBodyStreamRule: SyntaxVisitorRule {
    public typealias Visitor = ResponseBodyStreamVisitor

    public static let identifier = "hummingbird.response-body-stream"
    public static let name = "Response Body Streaming"
    public static let description = """
        Large response bodies should use streaming to avoid memory issues. \
        Use ResponseBody.stream for file downloads or large data.
        """
    public static let category = RuleCategory.hummingbird
    public static let defaultSeverity = Severity.info

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> ResponseBodyStreamVisitor {
        ResponseBodyStreamVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class ResponseBodyStreamVisitor: RuleVisitor, @unchecked Sendable {
    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        // Check for Data(contentsOf:) in response context
        if callee.contains("Data") && callee.contains("contentsOf") {
            addDiagnostic(
                at: node,
                message: "Loading entire file into memory for response. Consider using streaming for large files.",
                notes: [Note(message: "Use ResponseBody.stream or file streaming for better memory efficiency")]
            )
        }

        return .visitChildren
    }

    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for large buffer allocations in response handlers
        for binding in node.bindings {
            if let initializer = binding.initializer?.value {
                let initDesc = initializer.description
                if initDesc.contains("Data(count:") || initDesc.contains("ByteBuffer(capacity:") {
                    // Check if it's a large allocation
                    if let call = initializer.as(FunctionCallExprSyntax.self) {
                        for arg in call.arguments {
                            if let intLit = arg.expression.as(IntegerLiteralExprSyntax.self),
                               let value = Int(intLit.literal.text),
                               value > 1_000_000 {
                                addDiagnostic(
                                    at: node,
                                    message: "Large buffer allocation. Consider streaming for responses over 1MB.",
                                    notes: [Note(message: "Streaming reduces memory pressure under load")]
                                )
                            }
                        }
                    }
                }
            }
        }
        return .visitChildren
    }
}
