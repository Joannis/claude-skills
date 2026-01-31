@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Warns about large source files
public struct LargeFileRule: SyntaxVisitorRule {
    public typealias Visitor = LargeFileVisitor

    public static let identifier = "general.large-file"
    public static let name = "Large File"
    public static let description = """
        Large source files are harder to maintain. Consider splitting into smaller, \
        focused files.
        """
    public static let category = RuleCategory.general
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> LargeFileVisitor {
        let maxLines = configuration.options["max_lines"]?.intValue ?? 500
        return LargeFileVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity,
            maxLines: maxLines
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class LargeFileVisitor: RuleVisitor, @unchecked Sendable {
    private let maxLines: Int

    public init(
        context: RuleContext,
        ruleIdentifier: String,
        severity: Severity,
        maxLines: Int
    ) {
        self.maxLines = maxLines
        super.init(context: context, ruleIdentifier: ruleIdentifier, severity: severity)
    }

    public override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        let endLocation = context.locationConverter.location(for: node.endPosition)
        let lineCount = endLocation.line

        if lineCount > maxLines {
            addDiagnostic(
                at: node,
                message: "File has \(lineCount) lines (max \(maxLines)). Consider splitting into smaller files.",
                notes: [Note(message: "Large files are harder to navigate and maintain")]
            )
        }
        return .skipChildren
    }
}
