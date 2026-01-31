@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects @_spi types leaking into public API
public struct SPILeakingRule: SyntaxVisitorRule {
    public typealias Visitor = SPILeakingVisitor

    public static let identifier = "library-design.spi-leaking"
    public static let name = "SPI Type Leaking"
    public static let description = """
        Types marked with @_spi should not appear in public API signatures. \
        SPI types are for internal use by specific trusted clients.
        """
    public static let category = RuleCategory.libraryDesign
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> SPILeakingVisitor {
        SPILeakingVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class SPILeakingVisitor: RuleVisitor, @unchecked Sendable {
    private var spiTypes: Set<String> = []
    private var isPublicDecl = false

    public override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        // Track @_spi types
        let hasSPI = node.attributes.contains {
            $0.as(AttributeSyntax.self)?.attributeName.description.contains("_spi") ?? false
        }
        if hasSPI {
            spiTypes.insert(node.name.text)
        }
        return .visitChildren
    }

    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let hasSPI = node.attributes.contains {
            $0.as(AttributeSyntax.self)?.attributeName.description.contains("_spi") ?? false
        }
        if hasSPI {
            spiTypes.insert(node.name.text)
        }
        return .visitChildren
    }

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        isPublicDecl = node.modifiers.contains { $0.name.text == "public" || $0.name.text == "open" }

        // Don't warn if function itself is @_spi
        let hasSPI = node.attributes.contains {
            $0.as(AttributeSyntax.self)?.attributeName.description.contains("_spi") ?? false
        }
        if hasSPI {
            isPublicDecl = false
        }

        return .visitChildren
    }

    public override func visitPost(_ node: FunctionDeclSyntax) {
        isPublicDecl = false
    }

    public override func visit(_ node: TypeAnnotationSyntax) -> SyntaxVisitorContinueKind {
        guard isPublicDecl else { return .visitChildren }

        let typeName = node.type.description.trimmingCharacters(in: .whitespaces)
        for spiType in spiTypes {
            if typeName.contains(spiType) {
                addDiagnostic(
                    at: node,
                    message: "@_spi type '\(spiType)' used in public API. This exposes internal implementation.",
                    notes: [Note(message: "Either mark the function @_spi or use a public type")]
                )
            }
        }
        return .visitChildren
    }
}
