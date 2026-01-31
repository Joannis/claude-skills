@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects @inlinable functions that leak internal types
public struct InlinableLeakingRule: SyntaxVisitorRule {
    public typealias Visitor = InlinableLeakingVisitor

    public static let identifier = "library-design.inlinable-leaking"
    public static let name = "Inlinable Type Leaking"
    public static let description = """
        @inlinable functions can only use public or @usableFromInline types in their \
        implementation. Using internal types in @inlinable code causes compilation errors \
        for consumers.
        """
    public static let category = RuleCategory.libraryDesign
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> InlinableLeakingVisitor {
        InlinableLeakingVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class InlinableLeakingVisitor: RuleVisitor, @unchecked Sendable {
    private var isInInlinableFunction = false
    private var internalTypes: Set<String> = []

    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        // Track internal types
        let isPublic = node.modifiers.contains { $0.name.text == "public" || $0.name.text == "open" }
        let isUsableFromInline = node.attributes.contains {
            $0.as(AttributeSyntax.self)?.attributeName.description.contains("usableFromInline") ?? false
        }
        if !isPublic && !isUsableFromInline {
            internalTypes.insert(node.name.text)
        }
        return .visitChildren
    }

    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let isPublic = node.modifiers.contains { $0.name.text == "public" || $0.name.text == "open" }
        let isUsableFromInline = node.attributes.contains {
            $0.as(AttributeSyntax.self)?.attributeName.description.contains("usableFromInline") ?? false
        }
        if !isPublic && !isUsableFromInline {
            internalTypes.insert(node.name.text)
        }
        return .visitChildren
    }

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        isInInlinableFunction = node.attributes.contains {
            $0.as(AttributeSyntax.self)?.attributeName.description.contains("inlinable") ?? false
        }
        return .visitChildren
    }

    public override func visitPost(_ node: FunctionDeclSyntax) {
        isInInlinableFunction = false
    }

    public override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        guard isInInlinableFunction else { return .visitChildren }

        let name = node.baseName.text
        if internalTypes.contains(name) {
            addDiagnostic(
                at: node,
                message: "Internal type '\(name)' used in @inlinable function. Mark it @usableFromInline or public.",
                fix: Fix(
                    description: "Add @usableFromInline",
                    replacement: "@usableFromInline internal"
                )
            )
        }
        return .visitChildren
    }
}
