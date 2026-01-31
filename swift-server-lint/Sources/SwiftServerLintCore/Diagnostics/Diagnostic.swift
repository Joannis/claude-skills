import Foundation
@preconcurrency import SwiftSyntax

/// Severity level for diagnostics
public enum Severity: String, Codable, Sendable, Comparable {
    case error
    case warning
    case info

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        let order: [Severity] = [.info, .warning, .error]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// A diagnostic message produced by a lint rule
public struct Diagnostic: Sendable {
    /// The rule that produced this diagnostic
    public let ruleIdentifier: String

    /// The severity of this diagnostic
    public let severity: Severity

    /// The main message describing the issue
    public let message: String

    /// The file path where the issue was found
    public let filePath: String

    /// The source location of the issue
    public let location: SourceLocation

    /// Optional fix suggestion
    public let fix: Fix?

    /// Additional notes or context
    public let notes: [Note]

    public init(
        ruleIdentifier: String,
        severity: Severity,
        message: String,
        filePath: String,
        location: SourceLocation,
        fix: Fix? = nil,
        notes: [Note] = []
    ) {
        self.ruleIdentifier = ruleIdentifier
        self.severity = severity
        self.message = message
        self.filePath = filePath
        self.location = location
        self.fix = fix
        self.notes = notes
    }
}

/// A source location in a file
public struct SourceLocation: Sendable {
    public let line: Int
    public let column: Int
    public let endLine: Int?
    public let endColumn: Int?

    public init(line: Int, column: Int, endLine: Int? = nil, endColumn: Int? = nil) {
        self.line = line
        self.column = column
        self.endLine = endLine
        self.endColumn = endColumn
    }

    public init(from position: AbsolutePosition, in converter: SourceLocationConverter) {
        let location = converter.location(for: position)
        self.line = location.line
        self.column = location.column
        self.endLine = nil
        self.endColumn = nil
    }

    public init(from node: some SyntaxProtocol, in converter: SourceLocationConverter) {
        let startLocation = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        let endLocation = converter.location(for: node.endPositionBeforeTrailingTrivia)
        self.line = startLocation.line
        self.column = startLocation.column
        self.endLine = endLocation.line
        self.endColumn = endLocation.column
    }
}

/// A suggested fix for a diagnostic
public struct Fix: Sendable {
    /// Description of what the fix does
    public let description: String

    /// The replacement text
    public let replacement: String

    /// The range to replace (if nil, insert at location)
    public let range: SourceRange?

    public init(description: String, replacement: String, range: SourceRange? = nil) {
        self.description = description
        self.replacement = replacement
        self.range = range
    }
}

/// A range in source code
public struct SourceRange: Sendable {
    public let start: SourceLocation
    public let end: SourceLocation

    public init(start: SourceLocation, end: SourceLocation) {
        self.start = start
        self.end = end
    }
}

/// An additional note attached to a diagnostic
public struct Note: Sendable {
    public let message: String
    public let location: SourceLocation?

    public init(message: String, location: SourceLocation? = nil) {
        self.message = message
        self.location = location
    }
}
