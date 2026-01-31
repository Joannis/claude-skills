@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects public import statements that leak dependencies
public struct PublicImportRule: SyntaxVisitorRule {
    public typealias Visitor = PublicImportVisitor

    public static let identifier = "library-design.public-import"
    public static let name = "Public Import Prevention"
    public static let description = """
        Public imports (using `public import` or `@_exported import`) expose internal \
        dependencies to consumers of your library. This creates tight coupling and \
        can cause issues with versioning and API stability. Use internal or package \
        access level for imports, and re-export only intentionally chosen types.
        """
    public static let category = RuleCategory.libraryDesign
    public static let defaultSeverity = Severity.error

    public static let triggeringExamples = [
        """
        public import Foundation
        """,
        """
        @_exported import NIO
        """,
        """
        public import struct Foundation.URL
        """
    ]

    public static let nonTriggeringExamples = [
        """
        import Foundation
        """,
        """
        internal import NIO
        """,
        """
        package import MyInternalModule
        """
    ]

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> PublicImportVisitor {
        PublicImportVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class PublicImportVisitor: RuleVisitor, @unchecked Sendable {
    public override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for @_exported attribute
        for attribute in node.attributes {
            if let attr = attribute.as(AttributeSyntax.self) {
                let attrName = attr.attributeName.description.trimmingCharacters(in: .whitespaces)
                if attrName == "_exported" {
                    let moduleName = node.path.description.trimmingCharacters(in: .whitespaces)
                    addDiagnostic(
                        at: node,
                        message: "@_exported import '\(moduleName)' leaks dependency to consumers. Remove @_exported.",
                        fix: Fix(
                            description: "Remove @_exported attribute",
                            replacement: "import \(moduleName)"
                        )
                    )
                    return .skipChildren
                }
            }
        }

        // Check for public or open access modifier
        for modifier in node.modifiers {
            let modifierName = modifier.name.text
            if modifierName == "public" || modifierName == "open" {
                let moduleName = node.path.description.trimmingCharacters(in: .whitespaces)
                addDiagnostic(
                    at: node,
                    message: "public import '\(moduleName)' leaks dependency to consumers. Use internal or package import.",
                    fix: Fix(
                        description: "Change to internal import",
                        replacement: "internal import \(moduleName)"
                    )
                )
                return .skipChildren
            }
        }

        return .visitChildren
    }
}
