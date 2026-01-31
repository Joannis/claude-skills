@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects async let without await causing implicit cancellation
public struct AsyncLetLeakRule: SyntaxVisitorRule {
    public typealias Visitor = AsyncLetLeakVisitor

    public static let identifier = "concurrency.async-let-leak"
    public static let name = "Async Let Awaiting"
    public static let description = """
        async let bindings must be awaited before leaving scope. Not awaiting causes \
        implicit cancellation and may silently discard errors.
        """
    public static let category = RuleCategory.concurrency
    public static let defaultSeverity = Severity.error

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> AsyncLetLeakVisitor {
        AsyncLetLeakVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class AsyncLetLeakVisitor: RuleVisitor, @unchecked Sendable {
    private var asyncLetBindings: [String: VariableDeclSyntax] = [:]
    private var awaitedBindings: Set<String> = []

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        asyncLetBindings = [:]
        awaitedBindings = []
        return .visitChildren
    }

    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for async let - look for let binding with async modifier
        guard case .keyword(.let) = node.bindingSpecifier.tokenKind else {
            return .visitChildren
        }

        // Look for async in modifiers
        let hasAsync = node.modifiers.contains { $0.name.text == "async" }
        if hasAsync {
            for binding in node.bindings {
                if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                    asyncLetBindings[identifier.identifier.text] = node
                }
            }
        }
        return .visitChildren
    }

    public override func visit(_ node: AwaitExprSyntax) -> SyntaxVisitorContinueKind {
        // Track which async let bindings are awaited
        let awaited = node.expression.description
        for binding in asyncLetBindings.keys {
            if awaited.contains(binding) {
                awaitedBindings.insert(binding)
            }
        }
        return .visitChildren
    }

    public override func visitPost(_ node: FunctionDeclSyntax) {
        // Check for unwaited async let bindings
        for (name, declNode) in asyncLetBindings {
            if !awaitedBindings.contains(name) {
                addDiagnostic(
                    at: declNode,
                    message: "async let '\(name)' is never awaited. This causes implicit cancellation.",
                    fix: Fix(
                        description: "Add await before scope exit",
                        replacement: "_ = await \(name)"
                    )
                )
            }
        }
    }
}
