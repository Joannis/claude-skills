@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects incorrect ChannelPipeline handler ordering
public struct ChannelPipelineOrderRule: SyntaxVisitorRule {
    public typealias Visitor = ChannelPipelineOrderVisitor

    public static let identifier = "nio.channel-pipeline-order"
    public static let name = "ChannelPipeline Handler Order"
    public static let description = """
        ChannelPipeline handlers should be added in the correct order. Decoders should \
        come before encoders in the inbound direction.
        """
    public static let category = RuleCategory.nio
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> ChannelPipelineOrderVisitor {
        ChannelPipelineOrderVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class ChannelPipelineOrderVisitor: RuleVisitor, @unchecked Sendable {
    private var pipelineAdditions: [(type: String, node: FunctionCallExprSyntax)] = []

    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        if callee.contains("pipeline.addHandler") || callee.contains("addHandler") {
            if let firstArg = node.arguments.first {
                let handlerType = firstArg.expression.description
                pipelineAdditions.append((type: handlerType, node: node))
            }
        }
        return .visitChildren
    }

    public override func visitPost(_ node: SourceFileSyntax) {
        // Check for obvious ordering issues
        var seenEncoder = false
        for (type, handlerNode) in pipelineAdditions {
            if type.contains("Encoder") {
                seenEncoder = true
            } else if type.contains("Decoder") && seenEncoder {
                addDiagnostic(
                    at: handlerNode,
                    message: "Decoder added after Encoder in pipeline. Inbound handlers (decoders) typically come before outbound handlers (encoders).",
                    notes: [Note(message: "Review pipeline handler order for correct data flow")]
                )
            }
        }
    }
}
