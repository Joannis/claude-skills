@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Context provided to rules during linting
public struct RuleContext: Sendable {
    /// The source file being linted
    public let sourceFile: SourceFileSyntax

    /// The file path being linted
    public let filePath: String

    /// Configuration for this rule
    public let configuration: RuleConfiguration

    /// Source location converter for the file
    public let locationConverter: SourceLocationConverter

    public init(
        sourceFile: SourceFileSyntax,
        filePath: String,
        configuration: RuleConfiguration,
        locationConverter: SourceLocationConverter
    ) {
        self.sourceFile = sourceFile
        self.filePath = filePath
        self.configuration = configuration
        self.locationConverter = locationConverter
    }
}

/// Protocol for all lint rules
public protocol Rule: Sendable {
    /// Unique identifier for the rule (e.g., "postgres.sql-injection")
    static var identifier: String { get }

    /// Human-readable name
    static var name: String { get }

    /// Detailed description of what the rule checks
    static var description: String { get }

    /// The category this rule belongs to
    static var category: RuleCategory { get }

    /// Default configuration for this rule
    static var defaultConfiguration: RuleConfiguration { get }

    /// URL to documentation for this rule
    static var documentationURL: String? { get }

    /// Default severity for this rule
    static var defaultSeverity: Severity { get }

    /// Example code that triggers this rule
    static var triggeringExamples: [String] { get }

    /// Example code that does not trigger this rule
    static var nonTriggeringExamples: [String] { get }

    /// Initialize the rule with configuration
    init(configuration: RuleConfiguration)

    /// Run the rule and return any diagnostics
    func lint(context: RuleContext) -> [Diagnostic]
}

extension Rule {
    public static var defaultConfiguration: RuleConfiguration {
        RuleConfiguration(enabled: true, severity: defaultSeverity)
    }

    public static var documentationURL: String? { nil }

    public static var triggeringExamples: [String] { [] }
    public static var nonTriggeringExamples: [String] { [] }
}

/// A rule that uses a SyntaxVisitor to find issues
public protocol SyntaxVisitorRule: Rule {
    associatedtype Visitor: SyntaxVisitor

    /// Create the visitor for this rule
    func makeVisitor(context: RuleContext) -> Visitor
}

extension SyntaxVisitorRule {
    public func lint(context: RuleContext) -> [Diagnostic] {
        let visitor = makeVisitor(context: context)
        visitor.walk(context.sourceFile)

        if let diagnosing = visitor as? DiagnosticProducing {
            return diagnosing.diagnostics
        }
        return []
    }
}

/// Protocol for visitors that produce diagnostics
public protocol DiagnosticProducing {
    var diagnostics: [Diagnostic] { get }
}

/// Base class for rule visitors that collects diagnostics.
/// SAFETY: Visitors are created fresh per-file and used single-threaded during tree walking.
open class RuleVisitor: SyntaxVisitor, DiagnosticProducing, @unchecked Sendable {
    public let context: RuleContext
    public let ruleIdentifier: String
    public let severity: Severity
    public private(set) var diagnostics: [Diagnostic] = []

    public init(context: RuleContext, ruleIdentifier: String, severity: Severity) {
        self.context = context
        self.ruleIdentifier = ruleIdentifier
        self.severity = severity
        super.init(viewMode: .sourceAccurate)
    }

    /// Add a diagnostic at the given node's location
    public func addDiagnostic(
        at node: some SyntaxProtocol,
        message: String,
        fix: Fix? = nil,
        notes: [Note] = []
    ) {
        let location = SourceLocation(from: node, in: context.locationConverter)
        diagnostics.append(Diagnostic(
            ruleIdentifier: ruleIdentifier,
            severity: severity,
            message: message,
            filePath: context.filePath,
            location: location,
            fix: fix,
            notes: notes
        ))
    }
}
