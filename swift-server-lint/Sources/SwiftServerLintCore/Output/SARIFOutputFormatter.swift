import Foundation

/// SARIF output formatter for GitHub integration
public struct SARIFOutputFormatter: OutputFormatter, Sendable {
    public init() {}

    public func format(diagnostics: [Diagnostic]) -> String {
        let sarif = SARIFLog(diagnostics: diagnostics)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(sarif)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{\"error\": \"Failed to encode SARIF\"}"
        }
    }
}

// SARIF format structures
private struct SARIFLog: Encodable {
    let version = "2.1.0"
    let schema = "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json"
    let runs: [SARIFRun]

    init(diagnostics: [Diagnostic]) {
        // Group diagnostics by rule
        var ruleMap: [String: [Diagnostic]] = [:]
        for diagnostic in diagnostics {
            ruleMap[diagnostic.ruleIdentifier, default: []].append(diagnostic)
        }

        let rules = ruleMap.keys.sorted().enumerated().map { index, ruleId in
            SARIFRule(id: ruleId, index: index)
        }

        let ruleIndexMap = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0.index) })

        let results = diagnostics.map { diagnostic in
            SARIFResult(
                diagnostic: diagnostic,
                ruleIndex: ruleIndexMap[diagnostic.ruleIdentifier] ?? 0
            )
        }

        self.runs = [SARIFRun(
            tool: SARIFTool(driver: SARIFDriver(rules: rules)),
            results: results
        )]
    }

    enum CodingKeys: String, CodingKey {
        case version
        case schema = "$schema"
        case runs
    }
}

private struct SARIFRun: Encodable {
    let tool: SARIFTool
    let results: [SARIFResult]
}

private struct SARIFTool: Encodable {
    let driver: SARIFDriver
}

private struct SARIFDriver: Encodable {
    let name = "swift-server-lint"
    let version = "1.0.0"
    let informationUri = "https://github.com/swift-server/swift-server-lint"
    let rules: [SARIFRule]
}

private struct SARIFRule: Encodable {
    let id: String
    let index: Int
    let shortDescription: SARIFMessage
    let fullDescription: SARIFMessage?
    let helpUri: String?

    init(id: String, index: Int) {
        self.id = id
        self.index = index
        self.shortDescription = SARIFMessage(text: id)
        self.fullDescription = nil
        self.helpUri = nil
    }
}

private struct SARIFMessage: Encodable {
    let text: String
}

private struct SARIFResult: Encodable {
    let ruleId: String
    let ruleIndex: Int
    let level: String
    let message: SARIFMessage
    let locations: [SARIFLocation]
    let fixes: [SARIFFix]?

    init(diagnostic: Diagnostic, ruleIndex: Int) {
        self.ruleId = diagnostic.ruleIdentifier
        self.ruleIndex = ruleIndex
        self.level = Self.sarifLevel(for: diagnostic.severity)
        self.message = SARIFMessage(text: diagnostic.message)
        self.locations = [SARIFLocation(diagnostic: diagnostic)]

        if let fix = diagnostic.fix {
            self.fixes = [SARIFFix(fix: fix, diagnostic: diagnostic)]
        } else {
            self.fixes = nil
        }
    }

    static func sarifLevel(for severity: Severity) -> String {
        switch severity {
        case .error: return "error"
        case .warning: return "warning"
        case .info: return "note"
        }
    }
}

private struct SARIFLocation: Encodable {
    let physicalLocation: SARIFPhysicalLocation

    init(diagnostic: Diagnostic) {
        self.physicalLocation = SARIFPhysicalLocation(
            artifactLocation: SARIFArtifactLocation(uri: diagnostic.filePath),
            region: SARIFRegion(location: diagnostic.location)
        )
    }
}

private struct SARIFPhysicalLocation: Encodable {
    let artifactLocation: SARIFArtifactLocation
    let region: SARIFRegion
}

private struct SARIFArtifactLocation: Encodable {
    let uri: String
}

private struct SARIFRegion: Encodable {
    let startLine: Int
    let startColumn: Int
    let endLine: Int?
    let endColumn: Int?

    init(location: SourceLocation) {
        self.startLine = location.line
        self.startColumn = location.column
        self.endLine = location.endLine
        self.endColumn = location.endColumn
    }
}

private struct SARIFFix: Encodable {
    let description: SARIFMessage
    let artifactChanges: [SARIFArtifactChange]

    init(fix: Fix, diagnostic: Diagnostic) {
        self.description = SARIFMessage(text: fix.description)
        self.artifactChanges = [SARIFArtifactChange(
            artifactLocation: SARIFArtifactLocation(uri: diagnostic.filePath),
            replacements: [SARIFReplacement(
                deletedRegion: SARIFRegion(location: diagnostic.location),
                insertedContent: SARIFContent(text: fix.replacement)
            )]
        )]
    }
}

private struct SARIFArtifactChange: Encodable {
    let artifactLocation: SARIFArtifactLocation
    let replacements: [SARIFReplacement]
}

private struct SARIFReplacement: Encodable {
    let deletedRegion: SARIFRegion
    let insertedContent: SARIFContent
}

private struct SARIFContent: Encodable {
    let text: String
}
