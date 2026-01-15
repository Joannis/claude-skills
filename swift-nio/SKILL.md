---
name: swift-nio
description: 'Expert guidance on Swift NIO best practices, patterns, and implementation. Use when developers mention: (1) SwiftNIO, NIO, ByteBuffer, Channel, ChannelPipeline, ChannelHandler, EventLoop, NIOAsyncChannel or NIOFileSystem (2) "use SwiftNIO", EventLoopFuture, ServerBootstrap.'
---

# Swift NIO

## Overview

This skill provides expert guidance on SwiftNIO, Apple's event-driven network application framework. Use this skill to help developers write safe, performant networking code, build protocol implementations, and properly integrate with Swift Concurrency.

## Agent Behavior Contract (Follow These Rules)

1. Analyze the project's `Package.swift` to determine which SwiftNIO packages are used.
2. Before proposing fixes, identify if Swift Concurrency can be used instead of `EventLoopFuture` chains.
3. **Never recommend blocking the EventLoop** - this is the most critical rule in SwiftNIO development.
4. Prefer `NIOAsyncChannel` and structured concurrency over legacy `ChannelHandler` patterns for new code.
5. Use `EventLoopFuture`/`EventLoopPromise` only for low-level protocol implementations.
6. When working with `ByteBuffer`, always consider memory ownership and avoid unnecessary copies.

## Quick Decision Tree

When a developer needs SwiftNIO guidance, follow this decision tree:

1. **Building a TCP/UDP server or client?**
   - Read `references/Channels.md` for Channel concepts and `NIOAsyncChannel`
   - Use `ServerBootstrap` for TCP servers, `DatagramBootstrap` for UDP

2. **Understanding EventLoops?**
   - Read `references/EventLoops.md` for event loop concepts
   - Critical: Never block the EventLoop!

3. **Working with binary data?**
   - Read `references/ByteBuffer.md` for buffer operations
   - Prefer slice views over copies when possible

4. **Migrating from EventLoopFuture to async/await?**
   - Use `.get()` to bridge futures to async
   - Use `NIOAsyncChannel` for channel-based async code

## Triage-First Playbook (Common Issues -> Solutions)

- **"Blocking the EventLoop"**
  - Offload CPU-intensive work to a dispatch queue or use `NIOThreadPool`
  - Never perform synchronous I/O on an EventLoop
  - See `references/EventLoops.md`

- **Type mismatch crash in ChannelPipeline**
  - Ensure `InboundOut` of handler N matches `InboundIn` of handler N+1
  - Ensure `OutboundOut` of handler N matches `OutboundIn` of handler N-1
  - See `references/Channels.md`

- **Memory issues with ByteBuffer**
  - Use `readSlice` instead of `readBytes` when possible
  - Remember ByteBuffer uses copy-on-write semantics
  - See `references/ByteBuffer.md`

- **Deadlock when waiting for EventLoopFuture**
  - Never `.wait()` on a future from within the same EventLoop
  - Use `.get()` from async contexts or chain with `.flatMap`

## Core Patterns Reference

### Creating a TCP Server (Modern Approach)

```swift
let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
    .bind(host: "0.0.0.0", port: 8080) { channel in
        channel.eventLoop.makeCompletedFuture {
            try NIOAsyncChannel(
                wrappingChannelSynchronously: channel,
                configuration: .init(
                    inboundType: ByteBuffer.self,
                    outboundType: ByteBuffer.self
                )
            )
        }
    }

try await withThrowingDiscardingTaskGroup { group in
    try await server.executeThenClose { clients in
        for try await client in clients {
            group.addTask {
                try await handleClient(client)
            }
        }
    }
}
```

### EventLoopGroup Best Practice

```swift
// Preferred: Use the singleton
let group = MultiThreadedEventLoopGroup.singleton

// Get any EventLoop from the group
let eventLoop = group.any()
```

### Bridging EventLoopFuture to async/await

```swift
// From EventLoopFuture to async
let result = try await someFuture.get()

// From async to EventLoopFuture
let future = eventLoop.makeFutureWithTask {
    try await someAsyncOperation()
}
```

### ByteBuffer Operations

```swift
var buffer = ByteBufferAllocator().buffer(capacity: 1024)

// Writing
buffer.writeString("Hello")
buffer.writeInteger(UInt32(42))

// Reading
let string = buffer.readString(length: 5)
let number = buffer.readInteger(as: UInt32.self)
```

## Reference Files

Load these files as needed for specific topics:

- **`EventLoops.md`** - EventLoop concepts, nonblocking I/O, why blocking is bad
- **`Channels.md`** - Channel anatomy, ChannelPipeline, ChannelHandlers, NIOAsyncChannel

## Best Practices Summary

1. **Never block the EventLoop** - Offload heavy work to thread pools
2. **Use structured concurrency** - Prefer `NIOAsyncChannel` over legacy handlers
3. **Use the singleton EventLoopGroup** - `MultiThreadedEventLoopGroup.singleton`
4. **Handle errors in task groups** - Throwing from a client task closes the server
5. **Mind the types in pipelines** - Type mismatches crash at runtime
6. **Use ByteBuffer efficiently** - Prefer slices over copies