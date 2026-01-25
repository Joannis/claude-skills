---
name: database-clients
description: 'Expert guidance on building Swift database client libraries. Use when developers mention: (1) database driver or client library design, (2) connection pooling patterns, (3) wire protocol implementation, (4) SQL query building or string interpolation safety, (5) prepared statements or parameterized queries, (6) PostgreSQL, Redis, or Valkey clients, (7) type-safe database access, (8) RESP or PostgreSQL wire protocol, (9) postgres-nio or valkey-swift patterns.'
---

# Database Client Design

## Overview

This skill provides expert guidance on building production-quality database client libraries in Swift, based on patterns from exemplary implementations: **valkey-swift** (Redis/Valkey) and **postgres-nio** (PostgreSQL). Use this skill to help developers design wire protocols, connection pools, type-safe query APIs, and properly integrate with Swift Concurrency.

## Agent Behavior Contract (Follow These Rules)

1. **Prefer parameterized queries** - Never concatenate user input into SQL/command strings
2. **Use string interpolation for safety** - Implement `ExpressibleByStringInterpolation` to convert values to bindings
3. **Design commands as types** - Each command/query should be a struct with associated response type
4. **Implement state machines for protocols** - Complex connection lifecycles need explicit state transitions
5. **Support backpressure** - Row/result streaming must respect consumer demand
6. **Align actor executors** - Use `unownedExecutor` to align with NIO event loops
7. **Pool connections properly** - Implement keep-alive, idle timeout, and graceful shutdown

## Quick Decision Tree

1. **Building a database driver?**
   - Read `references/valkey-patterns.md` for command protocol patterns
   - Read `references/postgres-patterns.md` for query building patterns

2. **Implementing wire protocol encoding/decoding?**
   - Use length-prefixed messages with placeholder + backfill
   - Define protocol tokens as enums with associated values
   - Implement depth limits for nested structures

3. **Designing type-safe query API?**
   - Use `ExpressibleByStringInterpolation` for SQL injection prevention
   - Create `Encodable`/`Decodable` protocol hierarchies for type coercion
   - Use variadic generics for multi-column row decoding

4. **Managing connections?**
   - Use actors with NIO executor alignment
   - Implement hierarchical state machines
   - Support cancellation via request IDs

5. **Implementing connection pooling?**
   - Conform to `PooledConnection` protocol
   - Implement keep-alive behavior
   - Track metrics via observability delegate

## Triage-First Playbook

- **"SQL Injection vulnerability"**
  - Implement `ExpressibleByStringInterpolation` on query type
  - Convert interpolated values to `$1, $2...` parameter placeholders
  - See `references/postgres-patterns.md` → String Interpolation

- **"Type mismatch when decoding results"**
  - Define `Decodable` protocol with typed throws
  - Wrap errors with column/cell context
  - See `references/postgres-patterns.md` → Cell-Based Data Access

- **"Connection state corruption"**
  - Use hierarchical state machines with explicit transitions
  - Add `.modifying` sentinel to prevent COW issues
  - See `references/postgres-patterns.md` → Hierarchical State Machine

- **"Backpressure not working"**
  - Implement adaptive buffer strategy
  - Signal demand through data source protocol
  - See `references/postgres-patterns.md` → Backpressure-Aware Row Streaming

- **"Cluster routing failures"**
  - Calculate hash slots using CRC16
  - Handle MOVED/ASK redirections with retry logic
  - See `references/valkey-patterns.md` → Hash Slot Calculation

## Core Patterns Reference

### Command as Type Pattern

```swift
public protocol DatabaseCommand: Sendable, Hashable {
    associatedtype Response: Decodable
    static var name: String { get }
    func encode(into encoder: inout CommandEncoder)
}

public struct GET: DatabaseCommand {
    public typealias Response = String?
    public static var name: String { "GET" }
    public let key: String

    public func encode(into encoder: inout CommandEncoder) {
        encoder.encode(Self.name, key)
    }
}
```

### SQL Injection Prevention

```swift
public struct Query: ExpressibleByStringInterpolation {
    public var sql: String
    public var bindings: Bindings

    public struct StringInterpolation: StringInterpolationProtocol {
        var sql: String = ""
        var bindings: Bindings = Bindings()

        public mutating func appendLiteral(_ literal: String) {
            sql.append(literal)
        }

        public mutating func appendInterpolation<T: Encodable>(_ value: T) {
            bindings.append(value)
            sql.append("$\(bindings.count)")
        }
    }
}

// Usage: let query: Query = "SELECT * FROM users WHERE id = \(userId)"
// Result: sql = "SELECT * FROM users WHERE id = $1", bindings = [userId]
```

### Actor with NIO Executor Alignment

```swift
public final actor Connection: Sendable {
    nonisolated public let unownedExecutor: UnownedSerialExecutor

    init(channel: any Channel) {
        self.unownedExecutor = channel.eventLoop.executor.asUnownedSerialExecutor()
    }
}
```

### State Machine with Actions

```swift
struct ConnectionStateMachine {
    enum State {
        case idle
        case executing(QueryStateMachine)
        case closing
        case closed
        case modifying // Prevents COW
    }

    enum Action {
        case sendMessage(Message)
        case forwardResult(Result)
        case closeConnection
        case none
    }

    mutating func handle(_ message: Message) -> Action {
        switch (state, message) {
        case (.idle, .query(let q)):
            state = .executing(QueryStateMachine(q))
            return .sendMessage(.parse(q))
        // ...
        }
    }
}
```

### Variadic Generic Row Decoding

```swift
extension Row {
    func decode<each T: Decodable>(
        _ types: (repeat each T).Type
    ) throws -> (repeat each T) {
        var index = 0
        return (repeat try decodeColumn((each T).self, at: &index))
    }
}

// Usage: let (id, name, email) = try row.decode((Int.self, String.self, String.self))
```

## Reference Files

Load these files for detailed patterns:

- **`references/valkey-patterns.md`** - Command protocol, RESP encoding/decoding, cluster routing, hash slots, subscriptions, connection pool integration, transaction patterns
- **`references/postgres-patterns.md`** - Query interpolation, wire protocol encoding, hierarchical state machines, prepared statements, row streaming with backpressure, COPY FROM bulk loading, type coercion

## Best Practices Summary

1. **Commands/Queries as types** - Each operation is a struct with associated response type
2. **String interpolation for safety** - Prevent injection by design
3. **Protocol hierarchies for encoding** - Different guarantees (throwing, static types, etc.)
4. **Length-prefixed wire formats** - Write placeholder, encode, backfill length
5. **Hierarchical state machines** - Compose child machines for complex protocols
6. **Adaptive backpressure** - Dynamically adjust buffer targets based on consumer rate
7. **Actor + NIO alignment** - Eliminate context switches with `unownedExecutor`
8. **Cell/Row wrappers** - Rich metadata for better error messages
9. **Prepared statement caching** - Deduplicate concurrent preparations
10. **Graceful shutdown** - Drain pending operations before closing

## Key Libraries Referenced

- **valkey-swift** (github.com/valkey-io/valkey-swift) - Excellent RESP3 protocol, cluster support, pub/sub
- **postgres-nio** (github.com/vapor/postgres-nio) - Excellent query safety, type coercion, state machines
