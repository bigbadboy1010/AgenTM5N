import Foundation
import XCTest
@testable import AgenTM5N

final class ANEMLLToolProtocolTests: XCTestCase {
  func testParsesSingleAdvertisedToolCall() throws {
    let tool = definition(name: "read_file", properties: ["path"])
    let response = """
    <agentm5n_tool_call>{"name":"read_file","arguments":{"path":"README.md"}}</agentm5n_tool_call>
    """

    let calls = try ANEMLLToolProtocol.parseToolCalls(
      from: response,
      allowedTools: [tool]
    )

    XCTAssertEqual(calls.count, 1)
    XCTAssertEqual(calls[0].function.name, "read_file")
    XCTAssertEqual(calls[0].function.arguments["path"]?.stringValue, "README.md")
  }

  func testRejectsUnadvertisedToolCall() {
    let tool = definition(name: "read_file", properties: ["path"])
    let response = """
    <agentm5n_tool_call>{"name":"run_command","arguments":{"command":"whoami"}}</agentm5n_tool_call>
    """

    XCTAssertThrowsError(
      try ANEMLLToolProtocol.parseToolCalls(from: response, allowedTools: [tool])
    ) { error in
      XCTAssertEqual(error as? ANEMLLToolProtocolError, .unknownTool("run_command"))
    }
  }

  func testRejectsArgumentsOutsideAdvertisedSchema() {
    let tool = definition(name: "read_file", properties: ["path"])
    let response = """
    <agentm5n_tool_call>{"name":"read_file","arguments":{"path":"README.md","command":"whoami"}}</agentm5n_tool_call>
    """

    XCTAssertThrowsError(
      try ANEMLLToolProtocol.parseToolCalls(from: response, allowedTools: [tool])
    ) { error in
      XCTAssertEqual(error as? ANEMLLToolProtocolError, .malformedEnvelope)
    }
  }

  func testRejectsMultipleToolCallsInOneModelRound() {
    let tool = definition(name: "read_file", properties: ["path"])
    let response = """
    <agentm5n_tool_call>{"name":"read_file","arguments":{"path":"A"}}</agentm5n_tool_call>
    <agentm5n_tool_call>{"name":"read_file","arguments":{"path":"B"}}</agentm5n_tool_call>
    """

    XCTAssertThrowsError(
      try ANEMLLToolProtocol.parseToolCalls(from: response, allowedTools: [tool])
    ) { error in
      XCTAssertEqual(error as? ANEMLLToolProtocolError, .multipleToolCalls)
    }
  }

  func testToolCallInsideThinkingBlockIsNeverExecuted() throws {
    let tool = definition(name: "run_command", properties: ["command"])
    let response = """
    <think><agentm5n_tool_call>{"name":"run_command","arguments":{"command":"whoami"}}</agentm5n_tool_call></think>
    Keine Aktion erforderlich.
    """

    let calls = try ANEMLLToolProtocol.parseToolCalls(
      from: response,
      allowedTools: [tool]
    )
    XCTAssertTrue(calls.isEmpty)
  }

  func testTransportUsesTrailingToolResultInsteadOfRepeatingUserPrompt() throws {
    let messages = [
      ProviderMessage(role: .system, content: "system"),
      ProviderMessage(role: .user, content: "Lies README"),
      ProviderMessage(
        role: .assistant,
        content: "",
        toolCalls: [
          ProviderToolCall(
            function: .init(name: "read_file", arguments: ["path": .string("README.md")])
          )
        ]
      ),
      ProviderMessage(
        role: .tool,
        content: "AgenTM5N README result",
        toolName: "read_file"
      ),
    ]

    let request = try ANEMLLToolProtocol.makeTransportRequest(
      messages: messages,
      tools: [definition(name: "read_file", properties: ["path"])]
    )

    XCTAssertTrue(request.isToolContinuation)
    XCTAssertFalse(request.isFreshConversation)
    XCTAssertTrue(request.prompt.contains("TOOL RESULT [read_file]"))
    XCTAssertTrue(request.prompt.contains("AgenTM5N README result"))
  }

  func testToolResultIsBoundedBeforeReturningToSmallContextModel() throws {
    let hugeOutput = String(repeating: "x", count: 10_000)
    let request = try ANEMLLToolProtocol.makeTransportRequest(
      messages: [
        ProviderMessage(role: .user, content: "Lies Datei"),
        ProviderMessage(role: .assistant, content: ""),
        ProviderMessage(role: .tool, content: hugeOutput, toolName: "read_file"),
      ],
      tools: [definition(name: "read_file", properties: ["path"])]
    )

    XCTAssertLessThan(request.prompt.count, 2_000)
    XCTAssertFalse(request.prompt.contains(String(repeating: "x", count: 2_000)))
  }

  func testFirstUserTurnIsMarkedAsFreshConversation() throws {
    let request = try ANEMLLToolProtocol.makeTransportRequest(
      messages: [
        ProviderMessage(role: .system, content: "system"),
        ProviderMessage(role: .user, content: "Hallo"),
      ],
      tools: []
    )

    XCTAssertTrue(request.isFreshConversation)
    XCTAssertFalse(request.isToolContinuation)
    XCTAssertEqual(request.userTurnCount, 1)
  }

  func testToolEnvelopeFilterSuppressesChunkedEnvelope() {
    let filter = ANEMLLToolEnvelopeFilter()
    let first = filter.consume("Vorher <agentm5n_tool_")
    let second = filter.consume(
      "call>{\"name\":\"read_file\",\"arguments\":{\"path\":\"README.md\"}}</agentm5n_tool_call>"
    )
    let tail = filter.finish()

    XCTAssertEqual(first, "Vorher ")
    XCTAssertEqual(second, "")
    XCTAssertEqual(tail, "")
  }

  func testToolCatalogIsBoundedAndContainsExactEnvelopeContract() {
    let tools = [
      definition(name: "read_file", properties: ["path"]),
      definition(name: "git_status", properties: []),
    ]
    let prefix = ANEMLLToolProtocol.toolCatalogPrefix(tools)

    XCTAssertTrue(prefix.contains("read_file(path)"))
    XCTAssertTrue(prefix.contains("git_status()"))
    XCTAssertTrue(prefix.contains(ANEMLLToolProtocol.callPrefix))
    XCTAssertTrue(prefix.contains(ANEMLLToolProtocol.callSuffix))
    XCTAssertTrue(prefix.contains("One tool per round"))
  }

  private func definition(
    name: String,
    properties: [String]
  ) -> ProviderToolDefinition {
    let propertyObject = Dictionary(
      uniqueKeysWithValues: properties.map { key in
        (key, JSONValue.object(["type": .string("string")]))
      }
    )
    return ProviderToolDefinition(
      name: name,
      description: "Test tool \(name)",
      parameters: .object([
        "type": .string("object"),
        "properties": .object(propertyObject),
      ])
    )
  }
}
