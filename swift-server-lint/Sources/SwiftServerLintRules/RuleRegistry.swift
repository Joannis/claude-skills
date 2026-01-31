import SwiftServerLintCore

/// Registry of all available rules.
/// SAFETY: Rules dictionary is only written during init (single-threaded), then immutable.
public final class RuleRegistry: @unchecked Sendable {
    public static let shared = RuleRegistry()

    private var rules: [String: any Rule.Type] = [:]

    private init() {
        registerBuiltInRules()
    }

    /// Register a rule type
    public func register<R: Rule>(_ ruleType: R.Type) {
        rules[R.identifier] = ruleType
    }

    /// Get all registered rule identifiers
    public var allIdentifiers: [String] {
        Array(rules.keys).sorted()
    }

    /// Get all registered rules
    public var allRules: [any Rule.Type] {
        Array(rules.values)
    }

    /// Get rules for a specific category
    public func rules(for category: RuleCategory) -> [any Rule.Type] {
        allRules.filter { $0.category == category }
    }

    /// Get a rule type by identifier
    public func rule(for identifier: String) -> (any Rule.Type)? {
        rules[identifier]
    }

    /// Create a rule instance with configuration
    public func createRule(identifier: String, configuration: RuleConfiguration) -> (any Rule)? {
        guard let ruleType = rules[identifier] else { return nil }
        return ruleType.init(configuration: configuration)
    }

    private func registerBuiltInRules() {
        // Concurrency rules
        register(UncheckedSendableRule.self)
        register(ActorReentrancyRule.self)
        register(DetachedTaskInActorRule.self)
        register(TaskGroupCancellationRule.self)
        register(AsyncLetLeakRule.self)
        register(MainActorBlockingRule.self)
        register(SendableClosureRule.self)
        register(GlobalActorMixingRule.self)
        register(UnsafeContinuationRule.self)
        register(TaskLocalInheritanceRule.self)
        register(AsyncSequenceBufferingRule.self)

        // NIO rules
        register(EventLoopBlockingRule.self)
        register(EventLoopFutureLeakRule.self)
        register(ByteBufferLeakRule.self)
        register(ChannelPipelineOrderRule.self)
        register(EventLoopPromiseDoubleCompleteRule.self)
        register(NIODeadlockRule.self)
        register(EventLoopGroupShutdownRule.self)
        register(ByteBufferViewRetainRule.self)
        register(NIOAsyncBridgingRule.self)

        // Postgres rules
        register(SQLInjectionRule.self)
        register(PostgresConnectionLeakRule.self)
        register(PostgresTransactionRule.self)
        register(PostgresPreparedStatementRule.self)
        register(PostgresPoolExhaustionRule.self)
        register(PostgresNullHandlingRule.self)
        register(PostgresBatchInsertRule.self)
        register(PostgresDecimalPrecisionRule.self)
        register(PostgresJSONBTypingRule.self)
        register(PostgresEnumSyncRule.self)

        // Hummingbird rules
        register(RequestContextMutationRule.self)
        register(MiddlewareOrderRule.self)
        register(ResponseBodyStreamRule.self)
        register(RouteHandlerAsyncRule.self)

        // Library Design rules
        register(PublicImportRule.self)
        register(InlinableLeakingRule.self)
        register(SPILeakingRule.self)
        register(ExistentialPerformanceRule.self)

        // General rules
        register(LinuxCLibraryRule.self)
        register(FoundationAvoidanceRule.self)
        register(LoggerUsageRule.self)
        register(FatalErrorUsageRule.self)
        register(ForceUnwrapRule.self)
        register(ForceTryRule.self)
        register(ImplicitlyUnwrappedOptionalRule.self)
        register(TodoCommentRule.self)
        register(LargeFileRule.self)
        register(CyclomaticComplexityRule.self)
        register(DeepNestingRule.self)
        register(UnusedImportRule.self)
    }
}

/// Extension to get rule info for display
extension RuleRegistry {
    public struct RuleInfo {
        public let identifier: String
        public let name: String
        public let description: String
        public let category: RuleCategory
        public let defaultSeverity: Severity
        public let documentationURL: String?
    }

    public func info(for identifier: String) -> RuleInfo? {
        guard let ruleType = rules[identifier] else { return nil }
        return RuleInfo(
            identifier: ruleType.identifier,
            name: ruleType.name,
            description: ruleType.description,
            category: ruleType.category,
            defaultSeverity: ruleType.defaultSeverity,
            documentationURL: ruleType.documentationURL
        )
    }

    public var allRuleInfo: [RuleInfo] {
        allIdentifiers.compactMap { info(for: $0) }
    }
}
