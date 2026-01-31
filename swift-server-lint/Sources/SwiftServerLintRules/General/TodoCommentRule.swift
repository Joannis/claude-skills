@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Flags TODO and FIXME comments
public struct TodoCommentRule: SyntaxVisitorRule {
    public typealias Visitor = TodoCommentVisitor

    public static let identifier = "general.todo-comment"
    public static let name = "TODO/FIXME Comments"
    public static let description = """
        TODO and FIXME comments indicate incomplete work. Track these in your issue \
        tracker and resolve before release.
        """
    public static let category = RuleCategory.general
    public static let defaultSeverity = Severity.info

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> TodoCommentVisitor {
        TodoCommentVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class TodoCommentVisitor: RuleVisitor, @unchecked Sendable {
    public override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        // Walk through all trivia to find comments
        walkTrivia(node.leadingTrivia, node: node)
        return .visitChildren
    }

    public override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
        walkTrivia(token.leadingTrivia, node: token)
        walkTrivia(token.trailingTrivia, node: token)
        return .visitChildren
    }

    private func walkTrivia(_ trivia: Trivia, node: some SyntaxProtocol) {
        for piece in trivia {
            switch piece {
            case .lineComment(let text), .blockComment(let text), .docLineComment(let text), .docBlockComment(let text):
                let upperText = text.uppercased()
                if upperText.contains("TODO") {
                    addDiagnostic(
                        at: node,
                        message: "TODO comment found. Track and resolve before release.",
                        notes: [Note(message: text.trimmingCharacters(in: .whitespaces))]
                    )
                } else if upperText.contains("FIXME") {
                    addDiagnostic(
                        at: node,
                        message: "FIXME comment found. This indicates a known issue.",
                        notes: [Note(message: text.trimmingCharacters(in: .whitespaces))]
                    )
                } else if upperText.contains("HACK") {
                    addDiagnostic(
                        at: node,
                        message: "HACK comment found. Consider refactoring.",
                        notes: [Note(message: text.trimmingCharacters(in: .whitespaces))]
                    )
                }
            default:
                break
            }
        }
    }
}
