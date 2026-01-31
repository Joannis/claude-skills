import Foundation

/// JSON output formatter
public struct JSONOutputFormatter: OutputFormatter, Sendable {
    public init() {}

    public func format(diagnostics: [Diagnostic]) -> String {
        let output = JSONOutput(diagnostics: diagnostics)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(output)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{\"error\": \"Failed to encode diagnostics\"}"
        }
    }
}

private struct JSONOutput: Encodable {
    let version: Int = 1
    let diagnostics: [JSONDiagnostic]

    init(diagnostics: [Diagnostic]) {
        self.diagnostics = diagnostics.map { JSONDiagnostic(from: $0) }
    }
}

private struct JSONDiagnostic: Encodable {
    let ruleIdentifier: String
    let severity: String
    let message: String
    let filePath: String
    let location: JSONLocation
    let fix: JSONFix?
    let notes: [JSONNote]

    init(from diagnostic: Diagnostic) {
        self.ruleIdentifier = diagnostic.ruleIdentifier
        self.severity = diagnostic.severity.rawValue
        self.message = diagnostic.message
        self.filePath = diagnostic.filePath
        self.location = JSONLocation(from: diagnostic.location)
        self.fix = diagnostic.fix.map { JSONFix(from: $0) }
        self.notes = diagnostic.notes.map { JSONNote(from: $0) }
    }
}

private struct JSONLocation: Encodable {
    let line: Int
    let column: Int
    let endLine: Int?
    let endColumn: Int?

    init(from location: SourceLocation) {
        self.line = location.line
        self.column = location.column
        self.endLine = location.endLine
        self.endColumn = location.endColumn
    }
}

private struct JSONFix: Encodable {
    let description: String
    let replacement: String

    init(from fix: Fix) {
        self.description = fix.description
        self.replacement = fix.replacement
    }
}

private struct JSONNote: Encodable {
    let message: String
    let line: Int?
    let column: Int?

    init(from note: Note) {
        self.message = note.message
        self.line = note.location?.line
        self.column = note.location?.column
    }
}
