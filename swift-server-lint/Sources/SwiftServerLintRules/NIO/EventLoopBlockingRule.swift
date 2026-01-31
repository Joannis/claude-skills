@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects blocking operations on EventLoop threads
public struct EventLoopBlockingRule: SyntaxVisitorRule {
    public typealias Visitor = EventLoopBlockingVisitor

    public static let identifier = "nio.event-loop-blocking"
    public static let name = "EventLoop Blocking Prevention"
    public static let description = """
        Detects operations that block the EventLoop thread, which can cause severe performance \
        degradation or deadlocks in SwiftNIO applications. Blocking operations include \
        Thread.sleep, .wait() on futures, synchronous file I/O, and other blocking calls.
        """
    public static let category = RuleCategory.nio
    public static let defaultSeverity = Severity.error

    public static let triggeringExamples = [
        """
        eventLoop.execute {
            Thread.sleep(forTimeInterval: 1.0)
        }
        """,
        """
        channel.pipeline.addHandler(handler).wait()
        """,
        """
        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let result = someFuture.wait()
        }
        """
    ]

    public static let nonTriggeringExamples = [
        """
        eventLoop.execute {
            eventLoop.scheduleTask(in: .seconds(1)) { }
        }
        """,
        """
        someFuture.whenComplete { result in
            // handle result
        }
        """,
        """
        // In main.swift or test setup (not in handler)
        try server.wait()
        """
    ]

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> EventLoopBlockingVisitor {
        EventLoopBlockingVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class EventLoopBlockingVisitor: RuleVisitor, @unchecked Sendable {
    private let blockingCalls = [
        "Thread.sleep",
        "usleep",
        "sleep",
        "nanosleep"
    ]

    private let blockingMethods = [
        "wait"  // .wait() on futures
    ]

    private var isInEventLoopContext = false
    private var isInChannelHandler = false
    private var contextStack: [String] = []

    public override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check if this class conforms to ChannelHandler protocols
        if let inheritanceClause = node.inheritanceClause {
            let types = inheritanceClause.inheritedTypes.map { $0.type.description.trimmingCharacters(in: .whitespaces) }
            let handlerProtocols = [
                "ChannelInboundHandler",
                "ChannelOutboundHandler",
                "ChannelDuplexHandler",
                "ChannelHandler",
                "ByteToMessageDecoder",
                "MessageToByteEncoder"
            ]
            if types.contains(where: { handlerProtocols.contains($0) }) {
                isInChannelHandler = true
                contextStack.append("handler")
            }
        }
        return .visitChildren
    }

    public override func visitPost(_ node: ClassDeclSyntax) {
        if contextStack.last == "handler" {
            contextStack.removeLast()
            isInChannelHandler = contextStack.contains("handler")
        }
    }

    public override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callName = node.calledExpression.description.trimmingCharacters(in: .whitespaces)

        // Check for eventLoop.execute or similar
        if callName.contains("eventLoop") && (callName.contains("execute") || callName.contains("submit")) {
            isInEventLoopContext = true
            contextStack.append("eventLoop")
        }

        // Check for blocking calls
        if isInEventLoopContext || isInChannelHandler {
            // Check direct blocking calls
            for blocking in blockingCalls {
                if callName.contains(blocking) {
                    addDiagnostic(
                        at: node,
                        message: "Blocking call '\(blocking)' on EventLoop thread. Use EventLoop.scheduleTask(in:) for delays.",
                        fix: Fix(
                            description: "Replace with non-blocking alternative",
                            replacement: "eventLoop.scheduleTask(in: .seconds(1)) { ... }"
                        )
                    )
                    return .skipChildren
                }
            }
        }

        // Check for .wait() calls
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
            let methodName = memberAccess.declName.baseName.text
            if methodName == "wait" {
                if isInEventLoopContext || isInChannelHandler {
                    addDiagnostic(
                        at: node,
                        message: "Calling .wait() on EventLoop thread can cause deadlock. Use async/await or whenComplete.",
                        fix: Fix(
                            description: "Use async/await or callback",
                            replacement: "try await future.get()"
                        )
                    )
                }
            }
        }

        return .visitChildren
    }

    public override func visitPost(_ node: FunctionCallExprSyntax) {
        let callName = node.calledExpression.description.trimmingCharacters(in: .whitespaces)
        if callName.contains("eventLoop") && (callName.contains("execute") || callName.contains("submit")) {
            if contextStack.last == "eventLoop" {
                contextStack.removeLast()
                isInEventLoopContext = contextStack.contains("eventLoop")
            }
        }
    }

    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for ChannelHandler methods
        let handlerMethods = [
            "channelRead",
            "channelActive",
            "channelInactive",
            "channelReadComplete",
            "errorCaught",
            "write",
            "flush",
            "read",
            "close"
        ]

        let funcName = node.name.text
        if handlerMethods.contains(funcName) && isInChannelHandler {
            contextStack.append("handlerMethod")
        }

        return .visitChildren
    }

    public override func visitPost(_ node: FunctionDeclSyntax) {
        if contextStack.last == "handlerMethod" {
            contextStack.removeLast()
        }
    }
}
