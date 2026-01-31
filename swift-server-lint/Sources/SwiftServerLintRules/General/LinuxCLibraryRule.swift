@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects missing Musl/Glibc imports for Linux compatibility
public struct LinuxCLibraryRule: SyntaxVisitorRule {
    public typealias Visitor = LinuxCLibraryVisitor

    public static let identifier = "general.linux-c-library"
    public static let name = "Linux C Library Compatibility"
    public static let description = """
        Swift on Linux requires importing the appropriate C library (Glibc or Musl) \
        when using POSIX APIs. Code that imports Darwin but doesn't have corresponding \
        Linux imports will fail to compile on Linux servers.
        """
    public static let category = RuleCategory.general
    public static let defaultSeverity = Severity.error

    public static let triggeringExamples = [
        """
        #if canImport(Darwin)
        import Darwin
        #endif
        // Missing: Glibc/Musl import for Linux
        """,
        """
        import Darwin.C
        """
    ]

    public static let nonTriggeringExamples = [
        """
        #if canImport(Darwin)
        import Darwin
        #elseif canImport(Glibc)
        import Glibc
        #elseif canImport(Musl)
        import Musl
        #endif
        """,
        """
        #if os(Linux)
        import Glibc
        #elseif os(macOS) || os(iOS)
        import Darwin
        #endif
        """
    ]

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> LinuxCLibraryVisitor {
        LinuxCLibraryVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class LinuxCLibraryVisitor: RuleVisitor, @unchecked Sendable {
    private var hasDarwinImport = false
    private var hasGlibcImport = false
    private var hasMuslImport = false
    private var darwinImportNode: ImportDeclSyntax?
    private var isInConditional = false
    private var conditionalHasElse = false

    public override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        // First pass: collect import information
        for statement in node.statements {
            if let importDecl = statement.item.as(ImportDeclSyntax.self) {
                checkImport(importDecl, inConditional: false)
            } else if let ifConfig = statement.item.as(IfConfigDeclSyntax.self) {
                checkIfConfig(ifConfig)
            }
        }

        // Check for violations
        if hasDarwinImport && !hasGlibcImport && !hasMuslImport {
            if let darwinNode = darwinImportNode, !isInConditional {
                addDiagnostic(
                    at: darwinNode,
                    message: "Darwin import without Linux (Glibc/Musl) fallback. This won't compile on Linux.",
                    fix: Fix(
                        description: "Add Linux C library imports",
                        replacement: """
                        #if canImport(Darwin)
                        import Darwin
                        #elseif canImport(Glibc)
                        import Glibc
                        #elseif canImport(Musl)
                        import Musl
                        #endif
                        """
                    )
                )
            }
        }

        return .skipChildren
    }

    private func checkImport(_ node: ImportDeclSyntax, inConditional: Bool) {
        let moduleName = node.path.description.trimmingCharacters(in: .whitespaces)

        if moduleName == "Darwin" || moduleName.hasPrefix("Darwin.") {
            hasDarwinImport = true
            if !inConditional {
                darwinImportNode = node
            }
            isInConditional = inConditional
        } else if moduleName == "Glibc" {
            hasGlibcImport = true
        } else if moduleName == "Musl" {
            hasMuslImport = true
        }
    }

    private func checkIfConfig(_ node: IfConfigDeclSyntax) {
        var foundDarwinClause = false
        var foundLinuxClause = false

        for clause in node.clauses {
            let condition = clause.condition?.description ?? ""

            // Check condition for Darwin/macOS/iOS
            if condition.contains("Darwin") || condition.contains("macOS") || condition.contains("iOS") || condition.contains("os(macOS)") {
                foundDarwinClause = true
                // Check imports in this clause
                if let elements = clause.elements?.as(CodeBlockItemListSyntax.self) {
                    for element in elements {
                        if let importDecl = element.item.as(ImportDeclSyntax.self) {
                            checkImport(importDecl, inConditional: true)
                        }
                    }
                }
            }

            // Check condition for Linux/Glibc/Musl
            if condition.contains("Linux") || condition.contains("Glibc") || condition.contains("Musl") || condition.contains("os(Linux)") {
                foundLinuxClause = true
                if let elements = clause.elements?.as(CodeBlockItemListSyntax.self) {
                    for element in elements {
                        if let importDecl = element.item.as(ImportDeclSyntax.self) {
                            checkImport(importDecl, inConditional: true)
                        }
                    }
                }
            }

            // Check #else clause
            if clause.poundKeyword.tokenKind == .poundElse {
                conditionalHasElse = true
                if let elements = clause.elements?.as(CodeBlockItemListSyntax.self) {
                    for element in elements {
                        if let importDecl = element.item.as(ImportDeclSyntax.self) {
                            checkImport(importDecl, inConditional: true)
                        }
                    }
                }
            }
        }

        // If we found Darwin import in conditional but no Linux clause, that's still an issue
        if foundDarwinClause && !foundLinuxClause && !conditionalHasElse {
            if let darwinNode = darwinImportNode {
                addDiagnostic(
                    at: darwinNode,
                    message: "Darwin conditional import without Linux fallback (#elseif canImport(Glibc)).",
                    fix: Fix(
                        description: "Add Linux fallback",
                        replacement: "#elseif canImport(Glibc)\nimport Glibc\n#elseif canImport(Musl)\nimport Musl"
                    )
                )
            }
        }
    }
}
