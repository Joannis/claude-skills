import Foundation
@preconcurrency import SwiftSyntax
import SwiftParser

/// Main linter engine
public final class Linter: Sendable {
    public let configuration: Configuration
    public let profile: String?

    public init(configuration: Configuration = .loadFromCurrentDirectory(), profile: String? = nil) {
        self.configuration = configuration
        self.profile = profile
    }
}
