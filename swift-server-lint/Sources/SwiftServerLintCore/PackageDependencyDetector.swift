import Foundation

/// Detects dependencies from a Package.swift file to determine which rule categories are relevant.
public struct PackageDependencyDetector: Sendable {
    /// Known package names mapped to rule categories
    private static let dependencyToCategory: [String: RuleCategory] = [
        // Hummingbird
        "hummingbird": .hummingbird,
        "hummingbird-core": .hummingbird,
        "hummingbird-auth": .hummingbird,
        "hummingbird-fluent": .hummingbird,
        "hummingbird-websocket": .hummingbird,
        "hummingbird-redis": .hummingbird,
        "hummingbird-router": .hummingbird,

        // Postgres
        "postgres-nio": .postgres,
        "postgres-kit": .postgres,
        "fluent-postgres-driver": .postgres,

        // NIO
        "swift-nio": .nio,
        "swift-nio-ssl": .nio,
        "swift-nio-http2": .nio,
        "swift-nio-transport-services": .nio,
        "swift-nio-extras": .nio,
        "async-http-client": .nio,
    ]

    /// Categories that should always be enabled regardless of dependencies
    private static let alwaysEnabledCategories: Set<RuleCategory> = [
        .concurrency,
        .libraryDesign,
        .general,
    ]

    /// Result of dependency detection
    public struct DetectionResult: Sendable {
        /// Categories that should be enabled based on detected dependencies
        public let enabledCategories: Set<RuleCategory>

        public init(enabledCategories: Set<RuleCategory>) {
            self.enabledCategories = enabledCategories
        }

        /// Whether a specific category should be enabled
        public func isEnabled(_ category: RuleCategory) -> Bool {
            enabledCategories.contains(category)
        }
    }

    /// Detect dependencies from a Package.swift file at the given path
    /// - Parameter packagePath: Path to Package.swift file
    /// - Returns: Detection result with enabled categories
    public static func detect(from packagePath: String) -> DetectionResult {
        guard let contents = try? String(contentsOfFile: packagePath, encoding: .utf8) else {
            // If we can't read Package.swift, enable all categories
            return DetectionResult(enabledCategories: Set(RuleCategory.allCases))
        }

        return detectFromContent(contents)
    }

    /// Detect dependencies from Package.swift content
    /// - Parameter content: The content of Package.swift
    /// - Returns: Detection result with enabled categories
    public static func detectFromContent(_ content: String) -> DetectionResult {
        var enabledCategories = alwaysEnabledCategories

        // Parse dependencies from Package.swift
        // Look for patterns like:
        // .package(url: "https://github.com/hummingbird-project/hummingbird.git", ...)
        // .package(name: "postgres-nio", ...)
        // .product(name: "Hummingbird", ...)

        let lowercasedContent = content.lowercased()

        for (packageName, category) in dependencyToCategory {
            // Check for package name in URLs or direct references
            if lowercasedContent.contains(packageName.lowercased()) {
                enabledCategories.insert(category)
            }
        }

        // Also check for common product names that might indicate dependencies
        let productIndicators: [(String, RuleCategory)] = [
            ("hummingbird", .hummingbird),
            ("hb", .hummingbird),
            ("postgresnio", .postgres),
            ("postgresclient", .postgres),
            ("niocore", .nio),
            ("nioposix", .nio),
            ("nioembedded", .nio),
        ]

        for (indicator, category) in productIndicators {
            if lowercasedContent.contains(indicator.lowercased()) {
                enabledCategories.insert(category)
            }
        }

        return DetectionResult(enabledCategories: enabledCategories)
    }

    /// Find the Package.swift file by searching upward from the given path
    /// - Parameter startPath: Starting directory to search from
    /// - Returns: Path to Package.swift if found, nil otherwise
    public static func findPackageSwift(from startPath: String) -> String? {
        var currentPath = startPath
        let fileManager = FileManager.default

        // Normalize to directory if it's a file
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: currentPath, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                currentPath = (currentPath as NSString).deletingLastPathComponent
            }
        }

        // Search upward for Package.swift
        while currentPath != "/" && !currentPath.isEmpty {
            let packagePath = (currentPath as NSString).appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: packagePath) {
                return packagePath
            }
            currentPath = (currentPath as NSString).deletingLastPathComponent
        }

        return nil
    }
}
