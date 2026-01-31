@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects potential actor reentrancy issues
public struct ActorReentrancyRule: SyntaxVisitorRule {
    public typealias Visitor = ActorReentrancyVisitor

    public static let identifier = "concurrency.actor-reentrancy"
    public static let name = "Actor Reentrancy Awareness"
    public static let description = """
        Actor methods can be re-entered at await points. State captured before an await \
        may be stale after the await completes. This rule detects patterns where state \
        is read before await and used after without re-validation.
        """
    public static let category = RuleCategory.concurrency
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> ActorReentrancyVisitor {
        ActorReentrancyVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class ActorReentrancyVisitor: RuleVisitor, @unchecked Sendable {
    private var isInActor = false
    private var capturedStateBeforeAwait: Set<String> = []
    private var hasSeenAwait = false

    public override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        isInActor = true
        return .visitChildren
    }

    public override func visitPost(_ node: ActorDeclSyntax) {
        isInActor = false
    }

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        capturedStateBeforeAwait = []
        hasSeenAwait = false
        return .visitChildren
    }

    public override func visit(_ node: AwaitExprSyntax) -> SyntaxVisitorContinueKind {
        if isInActor {
            hasSeenAwait = true
        }
        return .visitChildren
    }

    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isInActor && !hasSeenAwait else { return .visitChildren }

        // Track local variables that capture actor state before await
        for binding in node.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                if let initializer = binding.initializer?.value {
                    // Check if initializer references self
                    if initializer.description.contains("self.") {
                        capturedStateBeforeAwait.insert(identifier.identifier.text)
                    }
                }
            }
        }
        return .visitChildren
    }

    public override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        guard isInActor && hasSeenAwait else { return .visitChildren }

        let name = node.baseName.text
        if capturedStateBeforeAwait.contains(name) {
            addDiagnostic(
                at: node,
                message: "Variable '\(name)' was captured before await and may be stale. Re-read from actor state after await.",
                notes: [Note(message: "Actor state may have changed during the await suspension point")]
            )
        }
        return .visitChildren
    }
}
