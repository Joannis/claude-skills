@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Warns about deeply nested code
public struct DeepNestingRule: SyntaxVisitorRule {
    public typealias Visitor = DeepNestingVisitor

    public static let identifier = "general.deep-nesting"
    public static let name = "Deep Nesting"
    public static let description = """
        Deeply nested code is hard to read and maintain. Use early returns, guard \
        statements, or extract functions to reduce nesting.
        """
    public static let category = RuleCategory.general
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> DeepNestingVisitor {
        let maxDepth = configuration.options["max_depth"]?.intValue ?? 4
        return DeepNestingVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity,
            maxDepth: maxDepth
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class DeepNestingVisitor: RuleVisitor, @unchecked Sendable {
    private let maxDepth: Int
    private var currentDepth = 0

    public init(
        context: RuleContext,
        ruleIdentifier: String,
        severity: Severity,
        maxDepth: Int
    ) {
        self.maxDepth = maxDepth
        super.init(context: context, ruleIdentifier: ruleIdentifier, severity: severity)
    }

    public override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        currentDepth += 1
        if currentDepth > maxDepth {
            addDiagnostic(
                at: node,
                message: "Code nesting depth of \(currentDepth) exceeds maximum of \(maxDepth). Use early returns or extract functions.",
                notes: [Note(message: "Consider using guard statements or extracting helper functions")]
            )
        }
        return .visitChildren
    }

    public override func visitPost(_ node: CodeBlockSyntax) {
        currentDepth -= 1
    }
}
