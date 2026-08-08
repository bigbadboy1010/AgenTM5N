import Foundation
import FoundationModels

public enum AppleMacNativeTools {
  public static func makeTools() -> [any Tool] {
    [
      CalendarListEventsTool(),
      ContactsSearchTool(),
      MailListRecentTool(),
      MailReadMessageTool(),
    ]
  }
}

private struct CalendarListEventsTool: Tool {
  let name = "calendar_list_events"
  let description = "Read the user's upcoming macOS Calendar events. Use this when the user asks about today's schedule, appointments, meetings, or upcoming calendar entries."

  @Generable
  struct Arguments {
    @Guide(description: "Number of days to inspect from now", .range(1...30))
    var days: Int

    @Guide(description: "Maximum number of events to return", .range(1...100))
    var limit: Int
  }

  func call(arguments: Arguments) async throws -> String {
    await execute(
      name: name,
      arguments: [
        "days": .number(Double(arguments.days)),
        "limit": .number(Double(arguments.limit)),
      ]
    )
  }
}

private struct ContactsSearchTool: Tool {
  let name = "contacts_search"
  let description = "Search the user's macOS Contacts by person name or organization. Use this only when contact information is relevant to the user's request."

  @Generable
  struct Arguments {
    @Guide(description: "Person name or organization to search for")
    var query: String

    @Guide(description: "Maximum number of contacts to return", .range(1...100))
    var limit: Int
  }

  func call(arguments: Arguments) async throws -> String {
    await execute(
      name: name,
      arguments: [
        "query": .string(arguments.query),
        "limit": .number(Double(arguments.limit)),
      ]
    )
  }
}

private struct MailListRecentTool: Tool {
  let name = "mail_list_recent"
  let description = "List recent messages from the user's Apple Mail inbox. Returns only message ID, subject, sender, and received date so a specific message can be read separately when needed."

  @Generable
  struct Arguments {
    @Guide(description: "Maximum number of recent inbox messages to return", .range(1...25))
    var limit: Int
  }

  func call(arguments: Arguments) async throws -> String {
    await execute(
      name: name,
      arguments: [
        "limit": .number(Double(arguments.limit))
      ]
    )
  }
}

private struct MailReadMessageTool: Tool {
  let name = "mail_read_message"
  let description = "Read one Apple Mail inbox message by the numeric message ID returned by mail_list_recent. Use only when the message body is required."

  @Generable
  struct Arguments {
    @Guide(description: "Numeric Apple Mail message ID returned by mail_list_recent")
    var messageID: Int

    @Guide(description: "Maximum number of body characters to return", .range(500...12_000))
    var maximumCharacters: Int
  }

  func call(arguments: Arguments) async throws -> String {
    await execute(
      name: name,
      arguments: [
        "message_id": .number(Double(arguments.messageID)),
        "maximum_characters": .number(Double(arguments.maximumCharacters)),
      ]
    )
  }
}

private func execute(
  name: String,
  arguments: [String: JSONValue]
) async -> String {
  let result = await MacNativeAgentTools.execute(
    call: ProviderToolCall(
      function: ProviderToolCall.Function(
        name: name,
        arguments: arguments
      )
    )
  )
  if result.success {
    return result.output
  }
  return "TOOL_ERROR: \(result.output)"
}
