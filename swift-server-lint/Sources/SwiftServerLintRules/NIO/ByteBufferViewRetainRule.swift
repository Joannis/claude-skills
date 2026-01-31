@preconcurrency import SwiftSyntax
import SwiftServerLintCore

/// Detects ByteBufferView retention beyond buffer lifetime
public struct ByteBufferViewRetainRule: SyntaxVisitorRule {
    public typealias Visitor = ByteBufferViewRetainVisitor

    public static let identifier = "nio.byte-buffer-view-retain"
    public static let name = "ByteBufferView Retention"
    public static let description = """
        ByteBufferView references are only valid while the ByteBuffer exists. \
        Storing or returning a view can lead to use-after-free bugs.
        """
    public static let category = RuleCategory.nio
    public static let defaultSeverity = Severity.warning

    private let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public func makeVisitor(context: RuleContext) -> ByteBufferViewRetainVisitor {
        ByteBufferViewRetainVisitor(
            context: context,
            ruleIdentifier: Self.identifier,
            severity: configuration.severity ?? Self.defaultSeverity
        )
    }
}

// SAFETY: Created fresh per-file, used single-threaded
public final class ByteBufferViewRetainVisitor: RuleVisitor, @unchecked Sendable {
    public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check if function returns a ByteBufferView
        if let returnType = node.signature.returnClause?.type {
            let typeName = returnType.description.trimmingCharacters(in: .whitespaces)
            if typeName.contains("ByteBufferView") {
                addDiagnostic(
                    at: node,
                    message: "Returning ByteBufferView from function. View is only valid while original buffer exists.",
                    notes: [Note(message: "Consider returning the data as [UInt8] or copying to a new ByteBuffer")]
                )
            }
        }
        return .visitChildren
    }

    public override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for storing ByteBufferView in properties
        for attribute in node.attributes {
            // If it has @State or is in a class, it might be stored
            if let attr = attribute.as(AttributeSyntax.self) {
                let attrName = attr.attributeName.description
                if attrName == "State" || attrName == "Published" {
                    for binding in node.bindings {
                        if let typeAnnotation = binding.typeAnnotation?.type {
                            if typeAnnotation.description.contains("ByteBufferView") {
                                addDiagnostic(
                                    at: node,
                                    message: "Storing ByteBufferView in property. View may outlive original buffer.",
                                    notes: [Note(message: "Store the data as [UInt8] or ByteBuffer instead")]
                                )
                            }
                        }
                    }
                }
            }
        }
        return .visitChildren
    }
}
