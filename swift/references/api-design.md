# Swift API Design Patterns

Excellent patterns for designing Swift APIs, extracted from production frameworks.

## Protocol Design

### Associated Types with Generic Constraints

Use associated types to create flexible, type-safe abstractions:

```swift
public protocol HTTPResponder<Context>: Sendable {
    associatedtype Context
    @Sendable func respond(to request: Request, context: Context) async throws -> Response
}

// Constrain usage sites to enforce type relationships
public struct Router<Context: RequestContext> {
    public func on<Responder: HTTPResponder>(
        _ path: RouterPath,
        responder: Responder
    ) -> Self where Responder.Context == Context {
        // Type safety: Context types must match
    }
}
```

**Benefits:**
- Compile-time type checking
- Prevents runtime type errors
- Enables specialization for performance
- Clear type relationships

### Protocol Composition for Flexible Conformance

```swift
// Base protocol for request decoding
public protocol RequestContext: InitializableFromSource, RequestContextSource {
    associatedtype Source: RequestContextSource = ApplicationRequestContextSource
    associatedtype Decoder: RequestDecoder = JSONDecoder
    associatedtype Encoder: ResponseEncoder = JSONEncoder

    var coreContext: CoreRequestContextStorage { get set }
    var maxUploadSize: Int { get }
    var requestDecoder: Decoder { get }
    var responseEncoder: Encoder { get }
}

// Specialized protocol for authentication
public protocol AuthRequestContext: RequestContext {
    var auth: LoginCache { get set }
}

// Users compose the protocols they need
struct AppContext: AuthRequestContext, WebSocketRequestContext {
    var coreContext: CoreRequestContextStorage
    var auth: LoginCache
    var webSocket: WebSocketContext

    init(source: Source) {
        self.coreContext = .init(source: source)
        self.auth = .init()
        self.webSocket = .init()
    }
}
```

## Result Builder Patterns

### Composing Middleware/Handlers

```swift
@resultBuilder
public enum RouteBuilder<Context: RouterRequestContext> {
    // Build individual expressions
    public static func buildExpression<M: MiddlewareProtocol>(
        _ middleware: M
    ) -> M where M.Input == Request, M.Output == Response, M.Context == Context {
        middleware
    }

    public static func buildExpression<Output: ResponseGenerator>(
        _ handler: @escaping @Sendable (Request, Context) async throws -> Output
    ) -> Handle<Output, Context> {
        .init(handler)
    }

    // Build partial blocks for composition
    public static func buildPartialBlock<M0: MiddlewareProtocol, M1: MiddlewareProtocol>(
        accumulated m0: M0,
        next m1: M1
    ) -> _Middleware2<M0, M1> where M0.Context == M1.Context {
        _Middleware2(m0, m1)
    }

    // Support conditional compilation
    public static func buildEither<M: MiddlewareProtocol>(
        first component: M
    ) -> M {
        component
    }

    public static func buildEither<M: MiddlewareProtocol>(
        second component: M
    ) -> M {
        component
    }
}

// Usage - declarative, type-safe
let router = RouterBuilder(context: AppContext.self) {
    LoggingMiddleware()
    CORSMiddleware()

    #if DEBUG
    DebugMiddleware()
    #endif

    Handle { request, context in
        "Hello, World!"
    }
}
```

## Builder Pattern

### Static Factory Methods

```swift
public struct HTTPServerBuilder: Sendable {
    package let buildChildChannel: @Sendable (@escaping HTTPChannelHandler.Responder) throws -> any ServerChildChannel

    // Private init, public static factories
    public init(_ build: @escaping @Sendable (@escaping HTTPChannelHandler.Responder) throws -> any ServerChildChannel) {
        self.buildChildChannel = build
    }

    public static func http1(configuration: HTTP1Channel.Configuration = .init()) -> HTTPServerBuilder {
        .init { responder in
            HTTP1Channel(responder: responder, configuration: configuration)
        }
    }

    public static func http2(tlsConfiguration: TLSConfiguration) -> HTTPServerBuilder {
        .init { responder in
            HTTP2Channel(responder: responder, tlsConfiguration: tlsConfiguration)
        }
    }
}

// Usage - clear intent
let app = Application(
    router: router,
    server: .http1(configuration: .init(idleTimeout: .seconds(30)))
)
```

### Fluent Configuration

```swift
public struct Configuration: Sendable {
    public var address: BindAddress
    public var serverName: String?
    public var backlog: Int

    public init(
        address: BindAddress = .hostname("127.0.0.1", port: 8080),
        serverName: String? = nil,
        backlog: Int = 256
    ) {
        self.address = address
        self.serverName = serverName
        self.backlog = backlog
    }

    // Fluent modifiers
    public func address(_ address: BindAddress) -> Self {
        var copy = self
        copy.address = address
        return copy
    }

    public func serverName(_ name: String) -> Self {
        var copy = self
        copy.serverName = name
        return copy
    }
}

// Usage
let config = Configuration()
    .address(.hostname("0.0.0.0", port: 8080))
    .serverName("MyServer")
```

## Extension-Based API Design

### Protocol Extensions for Cross-Cutting Functionality

```swift
// Core protocol
public protocol ResponseGenerator: Sendable {
    func response(from request: Request, context: some RequestContext) throws -> Response
}

// Extend standard library types
extension String: ResponseGenerator {
    public func response(from request: Request, context: some RequestContext) -> Response {
        let buffer = ByteBuffer(string: self)
        return Response(
            status: .ok,
            headers: .defaultHummingbirdHeaders(contentType: "text/plain; charset=utf-8", contentLength: buffer.readableBytes),
            body: .init(byteBuffer: buffer)
        )
    }
}

extension HTTPResponse.Status: ResponseGenerator {
    public func response(from request: Request, context: some RequestContext) -> Response {
        Response(status: self, headers: [:], body: .init())
    }
}

// Conditional conformance for containers
extension Optional: ResponseGenerator where Wrapped: ResponseGenerator {
    public func response(from request: Request, context: some RequestContext) throws -> Response {
        switch self {
        case .some(let wrapped):
            return try wrapped.response(from: request, context: context)
        case .none:
            return Response(status: .noContent, headers: [:], body: .init())
        }
    }
}

extension Array: ResponseGenerator where Element: Encodable {}
extension Dictionary: ResponseGenerator where Key == String, Value: Encodable {}
```

**Benefits:**
- Open for extension, closed for modification
- Users can add their own conformances
- Type-safe and composable

## Overload Resolution Control

### @_disfavoredOverload for Disambiguation

```swift
public struct Parameters {
    // Primary overload
    public func get<T: LosslessStringConvertible>(_ key: String, as: T.Type) -> T? {
        self[key].flatMap { T(String($0)) }
    }

    // Disfavored when type matches both protocols
    @_disfavoredOverload
    public func get<T: RawRepresentable>(_ key: String, as: T.Type) -> T? where T.RawValue == String {
        self[key].flatMap { T(rawValue: String($0)) }
    }

    // Require variant for non-optional access
    public func require<T: LosslessStringConvertible>(_ key: String, as: T.Type) throws -> T {
        guard let value = self[key] else {
            throw HTTPError(.badRequest, message: "Missing parameter: \(key)")
        }
        guard let result = T(String(value)) else {
            throw HTTPError(.badRequest, message: "Cannot convert parameter '\(key)' to \(T.self)")
        }
        return result
    }
}

// Usage - clear and type-safe
let id = context.parameters.get("id", as: Int.self)           // Optional<Int>
let status = context.parameters.get("status", as: Status.self) // Optional<Status> (RawRepresentable)
let requiredId = try context.parameters.require("id", as: Int.self)  // Int (throws if missing)
```

## Custom Pattern Matching

### Custom ~= Operator

```swift
public struct RouterPath: ExpressibleByStringLiteral {
    public struct Element: Equatable, Sendable {
        enum Kind {
            case path(Substring)
            case capture(Substring)
            case wildcard
            case recursiveWildcard
        }

        let kind: Kind

        // Custom pattern matching operator
        public static func ~= (lhs: Element, rhs: some StringProtocol) -> Bool {
            switch lhs.kind {
            case .path(let path):
                return path == rhs
            case .capture:
                return true  // Captures match anything
            case .wildcard:
                return true
            case .recursiveWildcard:
                return true
            }
        }
    }
}

// Enables pattern matching in switch statements
switch element {
case .path("users"):
    // Exact match for "users"
case .capture(let name):
    // Parameter capture like {id}
case .wildcard:
    // Matches any single segment
case .recursiveWildcard:
    // Matches remaining path
}
```

## Error Design

### Protocol-Based Error Types

```swift
// Protocol for errors that can generate HTTP responses
public protocol HTTPResponseError: Error, Sendable {
    var status: HTTPResponse.Status { get }
    var headers: HTTPFields { get }
    func body(allocator: ByteBufferAllocator) -> ByteBuffer?
}

// Concrete implementation
public struct HTTPError: HTTPResponseError {
    public var status: HTTPResponse.Status
    public var headers: HTTPFields
    public var message: String?

    public init(_ status: HTTPResponse.Status, message: String? = nil) {
        self.status = status
        self.headers = [:]
        self.message = message
    }

    public func body(allocator: ByteBufferAllocator) -> ByteBuffer? {
        message.map { allocator.buffer(string: $0) }
    }
}

// Extension for common cases
extension HTTPError {
    public static let notFound = HTTPError(.notFound)
    public static let unauthorized = HTTPError(.unauthorized)
    public static let badRequest = HTTPError(.badRequest)

    public static func notFound(_ message: String) -> HTTPError {
        HTTPError(.notFound, message: message)
    }
}
```

### Error Augmentation Pattern

```swift
// Wrapper that adds context to errors without changing their type
public struct EditedHTTPError: HTTPResponseError {
    public let originalError: Error
    public let additionalHeaders: HTTPFields

    public var status: HTTPResponse.Status {
        (originalError as? HTTPResponseError)?.status ?? .internalServerError
    }

    public var headers: HTTPFields {
        var headers = (originalError as? HTTPResponseError)?.headers ?? [:]
        headers.append(contentsOf: additionalHeaders)
        return headers
    }
}

// Usage in middleware
func handle(_ request: Request, context: Context, next: Next) async throws -> Response {
    do {
        return try await next(request, context)
    } catch {
        // Add CORS headers to error responses
        throw EditedHTTPError(
            originalError: error,
            additionalHeaders: [.accessControlAllowOrigin: "*"]
        )
    }
}
```

## Type-Safe Generic Constraints

### Using where Clauses Effectively

```swift
// Constrain at declaration site
public struct Router<Context: RequestContext> {
    // Methods constrain further as needed
    public func get<Output: ResponseGenerator>(
        _ path: String,
        handler: @escaping @Sendable (Request, Context) async throws -> Output
    ) {
        // Output must be ResponseGenerator
    }

    // Add middleware with matching context
    public func add<M: MiddlewareProtocol>(
        middleware: M
    ) where M.Context == Context {
        // Middleware context must match router context
    }
}

// Conditional conformance
extension Array: ResponseGenerator where Element: Encodable {
    public func response(from request: Request, context: some RequestContext) throws -> Response {
        try context.responseEncoder.encode(self, from: request, context: context)
    }
}
```

## Visibility and Access Control

### Package-Level Visibility

```swift
// Public API
public struct Router<Context: RequestContext> {
    // Public interface
    public func get(_ path: String, handler: Handler) { ... }
}

// Package-internal implementation details
package struct RouterTrie<Value> {
    package var nodes: [TrieNode]
    package func resolve(_ path: [Substring]) -> Value?
}

// Module-internal helpers
@usableFromInline
internal func buildTrie() -> RouterTrie<Value> { ... }
```

**Access levels:**
- `public`: External API surface
- `package`: Shared across package modules
- `internal`: Single module (default)
- `fileprivate`/`private`: Implementation details
