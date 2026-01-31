@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Suggests avoiding Foundation when Swift alternatives exist
public struct FoundationAvoidanceRule: SyntaxVisitorRule {
    public typealias Visitor = FoundationAvoidanceVisitor

    public static let identifier = "general.foundation-avoidance"
    public static let name = "Foundation Avoidance"
    public static let description = """
        Some Foundation types have Swift standard library or SwiftNIO alternatives \
        that are more appropriate for server-side code.
        """
    public static let category = RuleCategory.general
    public static let defaultSeverity = Severity.info

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> FoundationAvoidanceVisitor {
        var allowedTypes: Set<String> = []
        if let allowed = configuration.options["allowed_types"] {
            if case .array(let arr) = allowed {
                for item in arr {
                    if case .string(let s) = item {
                        allowedTypes.insert(s)
                    }
                }
            }
        }

        return FoundationAvoidanceVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity,
            allowedTypes: allowedTypes
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class FoundationAvoidanceVisitor: RuleVisitor, @unchecked Sendable {
    private let allowedTypes: Set<String>

    private let alternatives: [String: String] = [
        "NSLock": "Use os.OSAllocatedUnfairLock or actors",
        "NSRecursiveLock": "Use actors instead",
        "DispatchQueue": "Use Swift Concurrency (Task, actors)",
        "DispatchGroup": "Use TaskGroup",
        "DispatchSemaphore": "Use AsyncSemaphore or actors",
        "NSCache": "Consider using in-memory cache libraries",
        "JSONSerialization": "Use Codable with JSONEncoder/JSONDecoder",
        "PropertyListSerialization": "Use Codable",
        "NSRegularExpression": "Use Swift Regex",
        "DateFormatter": "Use ISO8601DateFormatter or manual formatting",
        "NumberFormatter": "Use string interpolation or manual formatting",
        "NSNotificationCenter": "Use AsyncSequence or callbacks",
        "Timer": "Use Task.sleep or EventLoop scheduling"
    ]

    public init(
        context: RuleContext,
        ruleIdentifier: String,
        severity: Severity,
        allowedTypes: Set<String>
    ) {
        self.allowedTypes = allowedTypes
        super.init(context: context, ruleIdentifier: ruleIdentifier, severity: severity)
    }

    public override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.baseName.text

        if let alternative = alternatives[name], !allowedTypes.contains(name) {
            addDiagnostic(
                at: node,
                message: "Consider avoiding '\(name)'. \(alternative)",
                notes: [Note(message: "Server-side Swift often has better alternatives to Foundation")]
            )
        }
        return .visitChildren
    }

    public override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text

        if let alternative = alternatives[name], !allowedTypes.contains(name) {
            addDiagnostic(
                at: node,
                message: "Consider avoiding '\(name)'. \(alternative)",
                notes: [Note(message: "Server-side Swift often has better alternatives to Foundation")]
            )
        }
        return .visitChildren
    }
}
