@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects missing EventLoopGroup shutdown
public struct EventLoopGroupShutdownRule: SyntaxVisitorRule {
    public typealias Visitor = EventLoopGroupShutdownVisitor

    public static let identifier = "nio.event-loop-group-shutdown"
    public static let name = "EventLoopGroup Shutdown"
    public static let description = """
        EventLoopGroup must be shut down to release resources. Use syncShutdownGracefully \
        or shutdownGracefully.
        """
    public static let category = RuleCategory.nio
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> EventLoopGroupShutdownVisitor {
        EventLoopGroupShutdownVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class EventLoopGroupShutdownVisitor: RuleVisitor, @unchecked Sendable {
    private var eventLoopGroupCreations: [(name: String, node: FunctionCallExprSyntax)] = []
    private var shutdownCalls: Set<String> = []

    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
               let initializer = binding.initializer?.value.as(FunctionCallExprSyntax.self) {
                let callee = initializer.calledExpression.description
                if callee.contains("MultiThreadedEventLoopGroup") || callee.contains("NIOTSEventLoopGroup") {
                    eventLoopGroupCreations.append((name: identifier.identifier.text, node: initializer))
                }
            }
        }
        return .visitChildren
    }

    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        if callee.contains("shutdownGracefully") || callee.contains("syncShutdownGracefully") {
            if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
                let groupName = memberAccess.base?.description.trimmingCharacters(in: .whitespaces) ?? ""
                shutdownCalls.insert(groupName)
            }
        }
        return .visitChildren
    }

    public override func visitPost(_ node: SourceFileSyntax) {
        for (name, creationNode) in eventLoopGroupCreations {
            if !shutdownCalls.contains(name) {
                // Only warn if this looks like a local variable, not a stored property
                addDiagnostic(
                    at: creationNode,
                    message: "EventLoopGroup '\(name)' may not be shut down. Call shutdownGracefully() when done.",
                    fix: Fix(
                        description: "Add shutdown call",
                        replacement: "try \(name).syncShutdownGracefully()"
                    )
                )
            }
        }
    }
}
