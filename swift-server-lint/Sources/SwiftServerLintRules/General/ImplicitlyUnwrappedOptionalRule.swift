@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Warns about implicitly unwrapped optionals
public struct ImplicitlyUnwrappedOptionalRule: SyntaxVisitorRule {
    public typealias Visitor = ImplicitlyUnwrappedOptionalVisitor

    public static let identifier = "general.implicitly-unwrapped-optional"
    public static let name = "Implicitly Unwrapped Optional"
    public static let description = """
        Implicitly unwrapped optionals (Type!) can cause crashes. Use regular optionals \
        or non-optional types instead.
        """
    public static let category = RuleCategory.general
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> ImplicitlyUnwrappedOptionalVisitor {
        ImplicitlyUnwrappedOptionalVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class ImplicitlyUnwrappedOptionalVisitor: RuleVisitor, @unchecked Sendable {
    public override func visit(_ node: ImplicitlyUnwrappedOptionalTypeSyntax) -> SyntaxVisitorContinueKind {
        // IBOutlets are an acceptable use case, but not relevant for server code
        addDiagnostic(
            at: node,
            message: "Implicitly unwrapped optional can crash. Use regular optional or ensure the value is always set.",
            fix: Fix(
                description: "Change to regular optional",
                replacement: node.wrappedType.description + "?"
            )
        )
        return .visitChildren
    }
}
