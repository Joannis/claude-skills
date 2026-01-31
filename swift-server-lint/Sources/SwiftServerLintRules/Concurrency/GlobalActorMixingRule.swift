@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects mixing of different global actors
public struct GlobalActorMixingRule: SyntaxVisitorRule {
    public typealias Visitor = GlobalActorMixingVisitor

    public static let identifier = "concurrency.global-actor-mixing"
    public static let name = "Global Actor Mixing"
    public static let description = """
        Mixing different global actors (e.g., @MainActor with @CustomActor) in the same \
        type can lead to complex isolation requirements and potential deadlocks.
        """
    public static let category = RuleCategory.concurrency
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> GlobalActorMixingVisitor {
        GlobalActorMixingVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class GlobalActorMixingVisitor: RuleVisitor, @unchecked Sendable {
    private var actorsInType: Set<String> = []
    private var typeNode: (any SyntaxProtocol)?

    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        actorsInType = []
        typeNode = node
        collectActorAttributes(node.attributes)
        return .visitChildren
    }

    public override func visitPost(_ node: ClassDeclSyntax) {
        checkForMixing()
        actorsInType = []
    }

    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        actorsInType = []
        typeNode = node
        collectActorAttributes(node.attributes)
        return .visitChildren
    }

    public override func visitPost(_ node: StructDeclSyntax) {
        checkForMixing()
        actorsInType = []
    }

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        collectActorAttributes(node.attributes)
        return .visitChildren
    }

    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        collectActorAttributes(node.attributes)
        return .visitChildren
    }

    private func collectActorAttributes(_ attributes: AttributeListSyntax) {
        for attribute in attributes {
            if let attr = attribute.as(AttributeSyntax.self) {
                let name = attr.attributeName.description.trimmingCharacters(in: .whitespaces)
                // Check for global actor attributes
                if name == "MainActor" || name.hasSuffix("Actor") {
                    actorsInType.insert(name)
                }
            }
        }
    }

    private func checkForMixing() {
        if actorsInType.count > 1, let node = typeNode {
            let actors = actorsInType.sorted().joined(separator: ", ")
            addDiagnostic(
                at: node,
                message: "Type mixes multiple global actors: \(actors). This can cause complex isolation issues.",
                notes: [Note(message: "Consider using a single global actor or regular actor isolation")]
            )
        }
    }
}
