@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Warns about high cyclomatic complexity
public struct CyclomaticComplexityRule: SyntaxVisitorRule {
    public typealias Visitor = CyclomaticComplexityVisitor

    public static let identifier = "general.cyclomatic-complexity"
    public static let name = "Cyclomatic Complexity"
    public static let description = """
        High cyclomatic complexity indicates code that is hard to test and maintain. \
        Consider breaking complex functions into smaller, focused functions.
        """
    public static let category = RuleCategory.general
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> CyclomaticComplexityVisitor {
        let maxComplexity = configuration.options["max_complexity"]?.intValue ?? 10
        return CyclomaticComplexityVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity,
            maxComplexity: maxComplexity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class CyclomaticComplexityVisitor: RuleVisitor, @unchecked Sendable {
    private let maxComplexity: Int
    private var currentComplexity = 0
    private var currentFunction: FunctionDeclSyntax?

    public init(
        context: RuleContext,
        ruleIdentifier: String,
        severity: Severity,
        maxComplexity: Int
    ) {
        self.maxComplexity = maxComplexity
        super.init(context: context, ruleIdentifier: ruleIdentifier, severity: severity)
    }

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        currentFunction = node
        currentComplexity = 1  // Base complexity
        return .visitChildren
    }

    public override func visitPost(_ node: FunctionDeclSyntax) {
        if currentComplexity > maxComplexity, let funcNode = currentFunction {
            addDiagnostic(
                at: funcNode,
                message: "Function '\(funcNode.name.text)' has cyclomatic complexity of \(currentComplexity) (max \(maxComplexity)). Consider refactoring.",
                notes: [Note(message: "Split into smaller functions with single responsibilities")]
            )
        }
        currentFunction = nil
    }

    public override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        currentComplexity += 1
        return .visitChildren
    }

    public override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        currentComplexity += 1
        return .visitChildren
    }

    public override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        currentComplexity += 1
        return .visitChildren
    }

    public override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        currentComplexity += 1
        return .visitChildren
    }

    public override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        currentComplexity += 1
        return .visitChildren
    }

    public override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        currentComplexity += 1
        return .visitChildren
    }

    public override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        currentComplexity += 1
        return .visitChildren
    }

    public override func visit(_ node: TernaryExprSyntax) -> SyntaxVisitorContinueKind {
        currentComplexity += 1
        return .visitChildren
    }

    public override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for && and ||
        if let op = node.operator.as(BinaryOperatorExprSyntax.self) {
            let opText = op.operator.text
            if opText == "&&" || opText == "||" {
                currentComplexity += 1
            }
        }
        return .visitChildren
    }
}
