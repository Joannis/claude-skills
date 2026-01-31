@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects potentially unused imports
public struct UnusedImportRule: SyntaxVisitorRule {
    public typealias Visitor = UnusedImportVisitor

    public static let identifier = "general.unused-import"
    public static let name = "Unused Import"
    public static let description = """
        Unused imports increase compilation time and clutter the file. Remove imports \
        that aren't used.
        """
    public static let category = RuleCategory.general
    public static let defaultSeverity = Severity.info

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> UnusedImportVisitor {
        UnusedImportVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class UnusedImportVisitor: RuleVisitor, @unchecked Sendable {
    private var imports: [(module: String, node: ImportDeclSyntax)] = []
    private var usedIdentifiers: Set<String> = []

    // Known type mappings for common modules
    private let moduleTypes: [String: Set<String>] = [
        "Foundation": ["URL", "Data", "Date", "UUID", "URLSession", "JSONEncoder", "JSONDecoder", "FileManager", "ProcessInfo"],
        "SwiftSyntax": ["SourceFileSyntax", "SyntaxVisitor", "DeclSyntax", "ExprSyntax", "StmtSyntax", "TokenSyntax"],
        "NIO": ["EventLoop", "EventLoopFuture", "EventLoopPromise", "Channel", "ByteBuffer", "ChannelHandler"],
        "NIOHTTP1": ["HTTPRequestHead", "HTTPResponseHead", "HTTPMethod", "HTTPHeaders"],
        "Logging": ["Logger"],
        "Dispatch": ["DispatchQueue", "DispatchGroup", "DispatchSemaphore"]
    ]

    public override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let moduleName = node.path.description.trimmingCharacters(in: .whitespaces)
        imports.append((module: moduleName, node: node))
        return .visitChildren
    }

    public override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.baseName.text)
        return .visitChildren
    }

    public override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.name.text)
        return .visitChildren
    }

    public override func visitPost(_ node: SourceFileSyntax) {
        for (module, importNode) in imports {
            // Check if any known types from this module are used
            if let knownTypes = moduleTypes[module] {
                let isUsed = knownTypes.contains { usedIdentifiers.contains($0) }
                if !isUsed {
                    addDiagnostic(
                        at: importNode,
                        message: "Import '\(module)' may be unused. Remove if not needed.",
                        fix: Fix(
                            description: "Remove import",
                            replacement: ""
                        ),
                        notes: [Note(message: "This is a heuristic check - verify before removing")]
                    )
                }
            }
        }
    }
}
