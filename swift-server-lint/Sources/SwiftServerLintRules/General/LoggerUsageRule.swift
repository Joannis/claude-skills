@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Suggests using structured logging
public struct LoggerUsageRule: SyntaxVisitorRule {
    public typealias Visitor = LoggerUsageVisitor

    public static let identifier = "general.logger-usage"
    public static let name = "Structured Logging"
    public static let description = """
        Use swift-log's Logger instead of print for production logging. \
        Logger provides structured logging with levels and metadata.
        """
    public static let category = RuleCategory.general
    public static let defaultSeverity = Severity.info

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> LoggerUsageVisitor {
        LoggerUsageVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class LoggerUsageVisitor: RuleVisitor, @unchecked Sendable {
    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        let printFunctions = ["print", "debugPrint", "dump", "NSLog"]
        if printFunctions.contains(callee) {
            addDiagnostic(
                at: node,
                message: "Using '\(callee)' for output. Consider using Logger from swift-log for production code.",
                fix: Fix(
                    description: "Replace with Logger",
                    replacement: "logger.info(...)"
                ),
                notes: [Note(message: "Logger provides structured logging with levels, metadata, and configurable backends")]
            )
        }
        return .visitChildren
    }
}
