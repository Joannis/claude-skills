@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects @unchecked Sendable without safety documentation
public struct UncheckedSendableRule: SyntaxVisitorRule {
    public typealias Visitor = UncheckedSendableVisitor

    public static let identifier = "concurrency.unchecked-sendable"
    public static let name = "Unchecked Sendable Documentation"
    public static let description = """
        Types marked as @unchecked Sendable bypass the compiler's thread-safety checks. \
        This should only be used when you can prove thread-safety manually, and the \
        reasoning should be documented in a comment explaining why it's safe.
        """
    public static let category = RuleCategory.concurrency
    public static let defaultSeverity = Severity.warning

    public static let triggeringExamples = [
        """
        struct MyType: @unchecked Sendable {
            var value: Int
        }
        """,
        """
        class UnsafeClass: @unchecked Sendable {
            var mutableState: String
        }
        """
    ]

    public static let nonTriggeringExamples = [
        """
        // Thread-safety: All access to `value` is synchronized via `lock`
        struct MyType: @unchecked Sendable {
            private let lock = NSLock()
            private var _value: Int
        }
        """,
        """
        // SAFETY: Immutable after initialization
        final class ImmutableClass: @unchecked Sendable {
            let value: String
            init(value: String) { self.value = value }
        }
        """,
        """
        struct SafeType: Sendable {
            let value: Int
        }
        """
    ]

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> UncheckedSendableVisitor {
        let requireComment = configuration.options["require_safety_comment"]?.boolValue ?? true
        return UncheckedSendableVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity,
            requireSafetyComment: requireComment
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class UncheckedSendableVisitor: RuleVisitor, @unchecked Sendable {
    private let requireSafetyComment: Bool

    private let safetyCommentPatterns = [
        "thread-safe",
        "thread safe",
        "threadsafe",
        "safety:",
        "SAFETY:",
        "synchronized",
        "immutable",
        "lock",
        "atomic"
    ]

    public init(
        context: RuleContext,
        ruleIdentifier: String,
        severity: Severity,
        requireSafetyComment: Bool
    ) {
        self.requireSafetyComment = requireSafetyComment
        super.init(context: context, ruleIdentifier: ruleIdentifier, severity: severity)
    }

    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        checkForUncheckedSendable(inheritanceClause: node.inheritanceClause, node: node)
        return .visitChildren
    }

    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        checkForUncheckedSendable(inheritanceClause: node.inheritanceClause, node: node)
        return .visitChildren
    }

    public override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        checkForUncheckedSendable(inheritanceClause: node.inheritanceClause, node: node)
        return .visitChildren
    }

    public override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        checkForUncheckedSendable(inheritanceClause: node.inheritanceClause, node: node)
        return .visitChildren
    }

    private func checkForUncheckedSendable(inheritanceClause: InheritanceClauseSyntax?, node: some SyntaxProtocol) {
        guard let inheritanceClause = inheritanceClause else { return }

        for inheritedType in inheritanceClause.inheritedTypes {
            let typeDescription = inheritedType.type.description

            // Check for @unchecked Sendable
            if typeDescription.contains("@unchecked") && typeDescription.contains("Sendable") {
                if !requireSafetyComment {
                    // Just warn about unchecked Sendable usage
                    addDiagnostic(
                        at: inheritedType,
                        message: "@unchecked Sendable bypasses thread-safety checks. Consider adding a safety comment.",
                        notes: [Note(message: "Document why this type is thread-safe despite using @unchecked")]
                    )
                    return
                }

                // Check for safety comment
                if !hasSafetyComment(node) {
                    addDiagnostic(
                        at: inheritedType,
                        message: "@unchecked Sendable requires a comment explaining thread-safety.",
                        fix: Fix(
                            description: "Add a safety comment",
                            replacement: "// SAFETY: <explain why this is thread-safe>\n"
                        ),
                        notes: [
                            Note(message: "Add a comment with: thread-safe, SAFETY:, synchronized, immutable, lock, or atomic")
                        ]
                    )
                }
            }
        }
    }

    private func hasSafetyComment(_ node: some SyntaxProtocol) -> Bool {
        // Check leading trivia of the node
        let leadingTrivia = node.leadingTrivia.description.lowercased()

        for pattern in safetyCommentPatterns {
            if leadingTrivia.contains(pattern.lowercased()) {
                return true
            }
        }

        // Also check the previous sibling's trailing trivia
        if let parent = node.parent {
            let siblings = parent.children(viewMode: .sourceAccurate)
            var previousSibling: Syntax?
            for sibling in siblings {
                if sibling.id == node.id {
                    break
                }
                previousSibling = sibling
            }
            if let prev = previousSibling {
                let trailingTrivia = prev.trailingTrivia.description.lowercased()
                for pattern in safetyCommentPatterns {
                    if trailingTrivia.contains(pattern.lowercased()) {
                        return true
                    }
                }
            }
        }

        return false
    }
}
