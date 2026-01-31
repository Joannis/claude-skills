@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects potential ByteBuffer memory leaks
public struct ByteBufferLeakRule: SyntaxVisitorRule {
    public typealias Visitor = ByteBufferLeakVisitor

    public static let identifier = "nio.byte-buffer-leak"
    public static let name = "ByteBuffer Memory Management"
    public static let description = """
        ByteBuffers should be properly managed. Creating large buffers without releasing \
        them can cause memory issues.
        """
    public static let category = RuleCategory.nio
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> ByteBufferLeakVisitor {
        ByteBufferLeakVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class ByteBufferLeakVisitor: RuleVisitor, @unchecked Sendable {
    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        // Check for allocator.buffer with large capacity
        if callee.contains("allocator.buffer") {
            for argument in node.arguments {
                if argument.label?.text == "capacity" {
                    if let intLiteral = argument.expression.as(IntegerLiteralExprSyntax.self) {
                        if let value = Int(intLiteral.literal.text), value > 1_000_000 {
                            addDiagnostic(
                                at: node,
                                message: "Large ByteBuffer allocation (\(value) bytes). Ensure buffer is released after use.",
                                notes: [Note(message: "Consider using streaming or smaller buffers for large data")]
                            )
                        }
                    }
                }
            }
        }
        return .visitChildren
    }
}
