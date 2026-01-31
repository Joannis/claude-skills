@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Warns about fatalError usage in production code
public struct FatalErrorUsageRule: SyntaxVisitorRule {
    public typealias Visitor = FatalErrorUsageVisitor

    public static let identifier = "general.fatal-error"
    public static let name = "Fatal Error Usage"
    public static let description = """
        fatalError terminates the process and should be avoided in production server code. \
        Use proper error handling or precondition for programming errors.
        """
    public static let category = RuleCategory.general
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> FatalErrorUsageVisitor {
        FatalErrorUsageVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class FatalErrorUsageVisitor: RuleVisitor, @unchecked Sendable {
    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        if callee == "fatalError" {
            addDiagnostic(
                at: node,
                message: "fatalError terminates the process. Consider throwing an error or using precondition for programming errors.",
                notes: [Note(message: "Server processes should handle errors gracefully when possible")]
            )
        }
        return .visitChildren
    }
}
