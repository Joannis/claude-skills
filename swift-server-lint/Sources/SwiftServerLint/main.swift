import ArgumentParser
import Foundation
@preconcurrency import SwiftSyntax
import SwiftParser
import SwiftServerLintCore
import SwiftServerLintRules

@main
struct SwiftServerLintCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-server-lint",
        abstract: "A linter for Swift server-side best practices",
        version: "1.0.0",
        subcommands: [Lint.self, Rules.self, Explain.self, Init.self],
        defaultSubcommand: Lint.self
    )
}

// MARK: - Lint Command

struct Lint: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Lint Swift source files"
    )

    @Argument(help: "Paths to lint (files or directories)")
    var paths: [String] = ["."]

    @Option(name: .long, help: "Output format (text, json, sarif)")
    var format: OutputFormat = .text

    @Option(name: .long, help: "Configuration profile to use")
    var profile: String?

    @Option(name: .long, help: "Path to configuration file")
    var config: String?

    @Flag(name: .long, help: "Treat warnings as errors")
    var strict: Bool = false

    @Flag(name: .long, help: "Only lint staged files")
    var staged: Bool = false

    @Flag(name: .long, help: "Disable colored output")
    var noColor: Bool = false

    func run() throws {
        // Load configuration
        let configuration: Configuration
        if let configPath = config {
            configuration = try Configuration.load(from: configPath)
        } else {
            configuration = Configuration.loadFromCurrentDirectory()
        }

        // Get files to lint
        var filesToLint: [String] = []

        if staged {
            filesToLint = try getStagedFiles()
        } else {
            for path in paths {
                let expanded = try expandPath(path, configuration: configuration)
                filesToLint.append(contentsOf: expanded)
            }
        }

        // Filter to Swift files only
        filesToLint = filesToLint.filter { $0.hasSuffix(".swift") }

        if filesToLint.isEmpty {
            print("No Swift files to lint.")
            return
        }

        // Create rules
        let registry = RuleRegistry.shared
        var rules: [any SwiftServerLintRules.Rule] = []

        for ruleType in registry.allRules {
            let ruleConfig = configuration.configuration(for: ruleType.identifier, profile: profile)
            if ruleConfig.enabled {
                rules.append(ruleType.init(configuration: ruleConfig))
            }
        }

        // Lint files
        var allDiagnostics: [Diagnostic] = []

        for file in filesToLint {
            do {
                let source = try String(contentsOfFile: file, encoding: .utf8)
                let diagnostics = lintFile(file: file, source: source, rules: rules, configuration: configuration)
                allDiagnostics.append(contentsOf: diagnostics)
            } catch {
                allDiagnostics.append(Diagnostic(
                    ruleIdentifier: "internal.file-read-error",
                    severity: .error,
                    message: "Could not read file: \(error.localizedDescription)",
                    filePath: file,
                    location: SourceLocation(line: 1, column: 1)
                ))
            }
        }

        // Apply strict mode
        if strict {
            allDiagnostics = allDiagnostics.map { diagnostic in
                if diagnostic.severity == .warning {
                    return Diagnostic(
                        ruleIdentifier: diagnostic.ruleIdentifier,
                        severity: .error,
                        message: diagnostic.message,
                        filePath: diagnostic.filePath,
                        location: diagnostic.location,
                        fix: diagnostic.fix,
                        notes: diagnostic.notes
                    )
                }
                return diagnostic
            }
        }

        // Format and output
        let formatter: OutputFormatter
        switch format {
        case .text:
            formatter = TextOutputFormatter(colored: !noColor)
        case .json:
            formatter = JSONOutputFormatter()
        case .sarif:
            formatter = SARIFOutputFormatter()
        }

        print(formatter.format(diagnostics: allDiagnostics))

        // Exit with appropriate code
        let hasErrors = allDiagnostics.contains { $0.severity == .error }
        if hasErrors {
            throw ExitCode(1)
        }
    }

    private func lintFile(
        file: String,
        source: String,
        rules: [any SwiftServerLintRules.Rule],
        configuration: Configuration
    ) -> [Diagnostic] {
        let sourceFile = Parser.parse(source: source)
        let locationConverter = SourceLocationConverter(fileName: file, tree: sourceFile)

        var diagnostics: [Diagnostic] = []

        for rule in rules {
            let ruleConfig = configuration.configuration(for: type(of: rule).identifier, profile: profile)
            guard ruleConfig.enabled else { continue }

            let context = RuleContext(
                sourceFile: sourceFile,
                filePath: file,
                configuration: ruleConfig,
                locationConverter: locationConverter
            )

            let ruleDiagnostics = rule.lint(context: context)

            // Apply severity override from configuration
            if let severityOverride = ruleConfig.severity {
                diagnostics.append(contentsOf: ruleDiagnostics.map { diag in
                    Diagnostic(
                        ruleIdentifier: diag.ruleIdentifier,
                        severity: severityOverride,
                        message: diag.message,
                        filePath: diag.filePath,
                        location: diag.location,
                        fix: diag.fix,
                        notes: diag.notes
                    )
                })
            } else {
                diagnostics.append(contentsOf: ruleDiagnostics)
            }
        }

        return diagnostics
    }

    private func expandPath(_ path: String, configuration: Configuration) throws -> [String] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw ValidationError("Path does not exist: \(path)")
        }

        if isDirectory.boolValue {
            return try findSwiftFiles(in: path, configuration: configuration)
        } else {
            return [path]
        }
    }

    private func findSwiftFiles(in directory: String, configuration: Configuration) throws -> [String] {
        let fileManager = FileManager.default
        var results: [String] = []

        guard let enumerator = fileManager.enumerator(atPath: directory) else {
            return results
        }

        while let relativePath = enumerator.nextObject() as? String {
            let fullPath = (directory as NSString).appendingPathComponent(relativePath)

            // Check if excluded
            var excluded = false
            for pattern in configuration.exclude {
                if matchesGlob(path: relativePath, pattern: pattern) {
                    excluded = true
                    break
                }
            }

            if excluded {
                continue
            }

            // Check if Swift file
            if relativePath.hasSuffix(".swift") {
                results.append(fullPath)
            }
        }

        return results
    }

    private func matchesGlob(path: String, pattern: String) -> Bool {
        // Simple glob matching - handles ** and *
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "**", with: ".*")
            .replacingOccurrences(of: "*", with: "[^/]*")

        guard let regex = try? NSRegularExpression(pattern: "^\(regexPattern)$") else {
            return false
        }

        let range = NSRange(path.startIndex..., in: path)
        return regex.firstMatch(in: path, range: range) != nil
    }

    private func getStagedFiles() throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["diff", "--cached", "--name-only", "--diff-filter=ACM"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return output.split(separator: "\n").map(String.init)
    }
}

enum OutputFormat: String, ExpressibleByArgument {
    case text
    case json
    case sarif
}

// MARK: - Rules Command

struct Rules: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List available lint rules"
    )

    @Option(name: .long, help: "Filter by category")
    var category: String?

    @Flag(name: .long, help: "Show detailed descriptions")
    var verbose: Bool = false

    func run() {
        let registry = RuleRegistry.shared
        var rules = registry.allRuleInfo

        if let categoryName = category {
            if let cat = RuleCategory(rawValue: categoryName) {
                rules = rules.filter { $0.category == cat }
            } else {
                print("Unknown category: \(categoryName)")
                print("Available categories: \(RuleCategory.allCases.map(\.rawValue).joined(separator: ", "))")
                return
            }
        }

        // Group by category
        var grouped: [RuleCategory: [RuleRegistry.RuleInfo]] = [:]
        for rule in rules {
            grouped[rule.category, default: []].append(rule)
        }

        for category in RuleCategory.allCases {
            guard let categoryRules = grouped[category], !categoryRules.isEmpty else { continue }

            print("\n\u{001B}[1m\(category.rawValue.uppercased())\u{001B}[0m")
            print(String(repeating: "-", count: 40))

            for rule in categoryRules.sorted(by: { $0.identifier < $1.identifier }) {
                let severityIndicator: String
                switch rule.defaultSeverity {
                case .error: severityIndicator = "\u{001B}[31m●\u{001B}[0m"
                case .warning: severityIndicator = "\u{001B}[33m●\u{001B}[0m"
                case .info: severityIndicator = "\u{001B}[34m●\u{001B}[0m"
                }

                print("\(severityIndicator) \(rule.identifier)")
                if verbose {
                    print("    \(rule.name)")
                    print("    \(rule.description)")
                    if let url = rule.documentationURL {
                        print("    Docs: \(url)")
                    }
                    print()
                }
            }
        }

        print("\n\(rules.count) rules available")
    }
}

// MARK: - Explain Command

struct Explain: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show detailed information about a rule"
    )

    @Argument(help: "Rule identifier (e.g., postgres.sql-injection)")
    var ruleIdentifier: String

    func run() {
        let registry = RuleRegistry.shared

        guard let ruleType = registry.rule(for: ruleIdentifier) else {
            print("Unknown rule: \(ruleIdentifier)")
            print("Use 'swift-server-lint rules' to see available rules.")
            return
        }

        print("\u{001B}[1m\(ruleType.identifier)\u{001B}[0m")
        print()
        print("Name: \(ruleType.name)")
        print("Category: \(ruleType.category.rawValue)")
        print("Default Severity: \(ruleType.defaultSeverity.rawValue)")
        print()
        print("Description:")
        print(ruleType.description)

        if let url = ruleType.documentationURL {
            print()
            print("Documentation: \(url)")
        }

        if !ruleType.triggeringExamples.isEmpty {
            print()
            print("\u{001B}[31mTriggering Examples:\u{001B}[0m")
            for example in ruleType.triggeringExamples {
                print("```swift")
                print(example)
                print("```")
                print()
            }
        }

        if !ruleType.nonTriggeringExamples.isEmpty {
            print()
            print("\u{001B}[32mNon-Triggering Examples:\u{001B}[0m")
            for example in ruleType.nonTriggeringExamples {
                print("```swift")
                print(example)
                print("```")
                print()
            }
        }
    }
}

// MARK: - Init Command

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate a configuration file"
    )

    @Flag(name: .long, help: "Generate full configuration with all options")
    var full: Bool = false

    @Option(name: .shortAndLong, help: "Output file path")
    var output: String = ".swift-server-lint.yaml"

    func run() throws {
        let yaml = Configuration.generateDefaultYAML(full: full)

        if FileManager.default.fileExists(atPath: output) {
            print("Configuration file already exists at \(output)")
            print("Use a different path with --output or remove the existing file.")
            throw ExitCode(1)
        }

        try yaml.write(toFile: output, atomically: true, encoding: .utf8)
        print("Created configuration file at \(output)")
    }
}
