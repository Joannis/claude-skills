import Foundation

/// Protocol for output formatters
public protocol OutputFormatter: Sendable {
    /// Format diagnostics for output
    func format(diagnostics: [Diagnostic]) -> String
}

/// Text output formatter for terminal display
public struct TextOutputFormatter: OutputFormatter, Sendable {
    public let colored: Bool

    public init(colored: Bool = true) {
        self.colored = colored
    }

    public func format(diagnostics: [Diagnostic]) -> String {
        if diagnostics.isEmpty {
            return colored ? "\u{001B}[32mNo issues found.\u{001B}[0m" : "No issues found."
        }

        var output = ""
        var currentFile = ""

        // Sort by file, then line, then column
        let sorted = diagnostics.sorted { lhs, rhs in
            if lhs.filePath != rhs.filePath {
                return lhs.filePath < rhs.filePath
            }
            if lhs.location.line != rhs.location.line {
                return lhs.location.line < rhs.location.line
            }
            return lhs.location.column < rhs.location.column
        }

        for diagnostic in sorted {
            if diagnostic.filePath != currentFile {
                currentFile = diagnostic.filePath
                if !output.isEmpty {
                    output += "\n"
                }
                output += colored ? "\u{001B}[1m\(currentFile)\u{001B}[0m\n" : "\(currentFile)\n"
            }

            let severityStr: String
            if colored {
                switch diagnostic.severity {
                case .error:
                    severityStr = "\u{001B}[31merror\u{001B}[0m"
                case .warning:
                    severityStr = "\u{001B}[33mwarning\u{001B}[0m"
                case .info:
                    severityStr = "\u{001B}[34minfo\u{001B}[0m"
                }
            } else {
                severityStr = diagnostic.severity.rawValue
            }

            let location = "\(diagnostic.location.line):\(diagnostic.location.column)"
            output += "  \(location): \(severityStr): \(diagnostic.message) [\(diagnostic.ruleIdentifier)]\n"

            for note in diagnostic.notes {
                if let noteLocation = note.location {
                    output += "    note: \(noteLocation.line):\(noteLocation.column): \(note.message)\n"
                } else {
                    output += "    note: \(note.message)\n"
                }
            }

            if let fix = diagnostic.fix {
                output += "    fix: \(fix.description)\n"
            }
        }

        // Summary
        let errorCount = diagnostics.filter { $0.severity == .error }.count
        let warningCount = diagnostics.filter { $0.severity == .warning }.count
        let infoCount = diagnostics.filter { $0.severity == .info }.count

        var summary = "\n"
        var parts: [String] = []
        if errorCount > 0 {
            parts.append("\(errorCount) error\(errorCount == 1 ? "" : "s")")
        }
        if warningCount > 0 {
            parts.append("\(warningCount) warning\(warningCount == 1 ? "" : "s")")
        }
        if infoCount > 0 {
            parts.append("\(infoCount) info")
        }
        summary += parts.joined(separator: ", ")

        if colored && errorCount > 0 {
            output += "\u{001B}[31m\(summary)\u{001B}[0m\n"
        } else if colored && warningCount > 0 {
            output += "\u{001B}[33m\(summary)\u{001B}[0m\n"
        } else {
            output += summary + "\n"
        }

        return output
    }
}
