@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Suggests async route handlers
public struct RouteHandlerAsyncRule: SyntaxVisitorRule {
    public typealias Visitor = RouteHandlerAsyncVisitor

    public static let identifier = "hummingbird.route-handler-async"
    public static let name = "Async Route Handlers"
    public static let description = """
        Route handlers should prefer async/await over EventLoopFuture for cleaner code.
        """
    public static let category = RuleCategory.hummingbird
    public static let defaultSeverity = Severity.info

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> RouteHandlerAsyncVisitor {
        RouteHandlerAsyncVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class RouteHandlerAsyncVisitor: RuleVisitor, @unchecked Sendable {
    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check if return type is EventLoopFuture
        if let returnType = node.signature.returnClause?.type {
            let typeName = returnType.description.trimmingCharacters(in: .whitespaces)
            if typeName.contains("EventLoopFuture") {
                // Check if function looks like a route handler
                let params = node.signature.parameterClause.parameters.map { $0.type.description }
                if params.contains(where: { $0.contains("Request") || $0.contains("Context") }) {
                    addDiagnostic(
                        at: node,
                        message: "Route handler returns EventLoopFuture. Consider using async/await for cleaner code.",
                        notes: [Note(message: "Hummingbird 2 supports async route handlers natively")]
                    )
                }
            }
        }
        return .visitChildren
    }
}
