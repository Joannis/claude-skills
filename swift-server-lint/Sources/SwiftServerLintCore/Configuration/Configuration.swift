import Foundation
import Yams

/// Rule category for organization
public enum RuleCategory: String, Codable, Sendable, CaseIterable {
    case concurrency
    case nio
    case postgres
    case hummingbird
    case libraryDesign = "library-design"
    case general
}

/// Configuration for a single rule
public struct RuleConfiguration: Codable, Sendable {
    public var enabled: Bool
    public var severity: Severity?
    public var options: [String: ConfigurationValue]

    public init(enabled: Bool = true, severity: Severity? = nil, options: [String: ConfigurationValue] = [:]) {
        self.enabled = enabled
        self.severity = severity
        self.options = options
    }

    public static let `default` = RuleConfiguration()
}

/// A configuration value that can be various types
public enum ConfigurationValue: Codable, Sendable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([ConfigurationValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([ConfigurationValue].self) {
            self = .array(arrayValue)
        } else {
            throw DecodingError.typeMismatch(ConfigurationValue.self, DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported configuration value type"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        }
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

/// A profile that can override rule configurations
public struct Profile: Codable, Sendable {
    public var rules: [String: [String: RuleConfiguration]]

    public init(rules: [String: [String: RuleConfiguration]] = [:]) {
        self.rules = rules
    }
}

/// Main configuration structure
public struct Configuration: Sendable {
    public var version: Int
    public var include: [String]
    public var exclude: [String]
    public var rules: [String: [String: RuleConfiguration]]
    public var profiles: [String: Profile]

    public init(
        version: Int = 1,
        include: [String] = ["**/*.swift"],
        exclude: [String] = ["**/.build/**", "**/Packages/**"],
        rules: [String: [String: RuleConfiguration]] = [:],
        profiles: [String: Profile] = [:]
    ) {
        self.version = version
        self.include = include
        self.exclude = exclude
        self.rules = rules
        self.profiles = profiles
    }

    /// Get configuration for a specific rule
    public func configuration(for ruleIdentifier: String, profile: String? = nil) -> RuleConfiguration {
        let parts = ruleIdentifier.split(separator: ".")
        guard parts.count == 2 else { return .default }

        let category = String(parts[0])
        let ruleName = String(parts[1])

        // Start with default configuration
        var config = RuleConfiguration.default

        // Apply base rule configuration
        if let categoryRules = rules[category], let ruleConfig = categoryRules[ruleName] {
            config = ruleConfig
        }

        // Apply profile overrides if specified
        if let profileName = profile, let profile = profiles[profileName] {
            if let categoryRules = profile.rules[category], let ruleConfig = categoryRules[ruleName] {
                if !ruleConfig.enabled {
                    config.enabled = false
                }
                if let severity = ruleConfig.severity {
                    config.severity = severity
                }
                for (key, value) in ruleConfig.options {
                    config.options[key] = value
                }
            }
        }

        return config
    }

    /// Load configuration from a YAML file
    public static func load(from path: String) throws -> Configuration {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let yaml = try Yams.load(yaml: String(data: data, encoding: .utf8)!) as? [String: Any] ?? [:]
        return try parse(yaml: yaml)
    }

    /// Load configuration from the current directory or return default
    public static func loadFromCurrentDirectory() -> Configuration {
        let configNames = [".swift-server-lint.yaml", ".swift-server-lint.yml", "swift-server-lint.yaml"]
        for name in configNames {
            if FileManager.default.fileExists(atPath: name) {
                if let config = try? load(from: name) {
                    return config
                }
            }
        }
        return Configuration()
    }

    private static func parse(yaml: [String: Any]) throws -> Configuration {
        var config = Configuration()

        if let version = yaml["version"] as? Int {
            config.version = version
        }

        if let include = yaml["include"] as? [String] {
            config.include = include
        }

        if let exclude = yaml["exclude"] as? [String] {
            config.exclude = exclude
        }

        if let rules = yaml["rules"] as? [String: [String: Any]] {
            for (category, categoryRules) in rules {
                var parsedRules: [String: RuleConfiguration] = [:]
                for (ruleName, ruleConfig) in categoryRules {
                    if let ruleDict = ruleConfig as? [String: Any] {
                        parsedRules[ruleName] = parseRuleConfiguration(ruleDict)
                    }
                }
                config.rules[category] = parsedRules
            }
        }

        if let profiles = yaml["profiles"] as? [String: [String: Any]] {
            for (profileName, profileConfig) in profiles {
                if let rules = profileConfig["rules"] as? [String: [String: Any]] {
                    var parsedRules: [String: [String: RuleConfiguration]] = [:]
                    for (category, categoryRules) in rules {
                        var parsedCategoryRules: [String: RuleConfiguration] = [:]
                        for (ruleName, ruleConfig) in categoryRules {
                            if let ruleDict = ruleConfig as? [String: Any] {
                                parsedCategoryRules[ruleName] = parseRuleConfiguration(ruleDict)
                            }
                        }
                        parsedRules[category] = parsedCategoryRules
                    }
                    config.profiles[profileName] = Profile(rules: parsedRules)
                }
            }
        }

        return config
    }

    private static func parseRuleConfiguration(_ dict: [String: Any]) -> RuleConfiguration {
        var config = RuleConfiguration()

        if let enabled = dict["enabled"] as? Bool {
            config.enabled = enabled
        }

        if let severityString = dict["severity"] as? String {
            config.severity = Severity(rawValue: severityString)
        }

        if let options = dict["options"] as? [String: Any] {
            for (key, value) in options {
                config.options[key] = parseConfigurationValue(value)
            }
        }

        return config
    }

    private static func parseConfigurationValue(_ value: Any) -> ConfigurationValue {
        switch value {
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let string as String:
            return .string(string)
        case let array as [Any]:
            return .array(array.map { parseConfigurationValue($0) })
        default:
            return .string(String(describing: value))
        }
    }

    /// Generate a default configuration YAML string
    public static func generateDefaultYAML(full: Bool = false) -> String {
        if full {
            return """
            version: 1

            include:
              - "**/*.swift"

            exclude:
              - "**/.build/**"
              - "**/Packages/**"
              - "**/DerivedData/**"

            rules:
              postgres:
                sql-injection:
                  enabled: true
                  severity: error
                  options:
                    allow_unsafe_sql_with_comment: true

              concurrency:
                unchecked-sendable:
                  enabled: true
                  severity: warning
                  options:
                    require_safety_comment: true

              nio:
                event-loop-blocking:
                  enabled: true
                  severity: error

              library-design:
                public-import:
                  enabled: true
                  severity: error

              general:
                linux-c-library:
                  enabled: true
                  severity: error

            profiles:
              ci:
                rules:
                  postgres:
                    sql-injection:
                      severity: error
            """
        } else {
            return """
            version: 1

            include:
              - "**/*.swift"

            exclude:
              - "**/.build/**"
            """
        }
    }
}
