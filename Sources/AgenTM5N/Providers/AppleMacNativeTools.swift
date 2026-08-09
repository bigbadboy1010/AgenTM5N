import Foundation
import FoundationModels

public enum AppleMacNativeTools {
  public static func makeTools() -> [any Tool] {
    [
      CalendarListEventsTool(),
      ContactsSearchTool(),
      MailListRecentTool(),
      MailReadMessageTool(),
      CalendarCreateEventTool(),
      CalendarUpdateEventTool(),
      CalendarDeleteEventTool(),
      ContactsCreateTool(),
      ContactsUpdateTool(),
      MailCreateDraftTool(),
      MailSendTool(),
      MailReplyTool(),
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
    await executeRead(
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
    await executeRead(
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
    await executeRead(
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
    await executeRead(
      name: name,
      arguments: [
        "message_id": .number(Double(arguments.messageID)),
        "maximum_characters": .number(Double(arguments.maximumCharacters)),
      ]
    )
  }
}

private struct CalendarCreateEventTool: Tool {
  let name = "calendar_create_event"
  let description = "Create a macOS Calendar event only when the user explicitly asks to create or add a calendar entry. AgenTM5N shows a confirmation dialog before changing the calendar."

  @Generable
  struct Arguments {
    @Guide(description: "Event title")
    var title: String

    @Guide(description: "ISO-8601 start date and time with timezone")
    var start: String

    @Guide(description: "ISO-8601 end date and time with timezone")
    var end: String

    @Guide(description: "Exact writable calendar title, or an empty string for the default calendar")
    var calendar: String

    @Guide(description: "Location, or an empty string")
    var location: String

    @Guide(description: "Notes, or an empty string")
    var notes: String

    @Guide(description: "Whether this is an all-day event")
    var isAllDay: Bool
  }

  func call(arguments: Arguments) async throws -> String {
    await executeMutation(
      name: name,
      action: "Kalenderereignis erstellen",
      details: "\(arguments.title)\n\(arguments.start) → \(arguments.end)",
      arguments: [
        "title": .string(arguments.title),
        "start": .string(arguments.start),
        "end": .string(arguments.end),
        "calendar": .string(arguments.calendar),
        "location": .string(arguments.location),
        "notes": .string(arguments.notes),
        "is_all_day": .bool(arguments.isAllDay),
      ]
    )
  }
}

private struct CalendarUpdateEventTool: Tool {
  let name = "calendar_update_event"
  let description = "Update a macOS Calendar event identified by calendar_list_events. Empty text fields mean unchanged. all_day_mode must be unchanged, true, or false. AgenTM5N shows a confirmation dialog before changing the calendar."

  @Generable
  struct Arguments {
    @Guide(description: "Exact event identifier returned by calendar_list_events")
    var eventID: String

    @Guide(description: "New title, or an empty string to leave unchanged")
    var title: String

    @Guide(description: "New ISO-8601 start date and time, or an empty string")
    var start: String

    @Guide(description: "New ISO-8601 end date and time, or an empty string")
    var end: String

    @Guide(description: "New exact calendar title, or an empty string")
    var calendar: String

    @Guide(description: "New location, or an empty string")
    var location: String

    @Guide(description: "New notes, or an empty string")
    var notes: String

    @Guide(description: "Use unchanged, true, or false")
    var allDayMode: String
  }

  func call(arguments: Arguments) async throws -> String {
    var toolArguments: [String: JSONValue] = [
      "event_id": .string(arguments.eventID),
      "title": .string(arguments.title),
      "start": .string(arguments.start),
      "end": .string(arguments.end),
      "calendar": .string(arguments.calendar),
      "location": .string(arguments.location),
      "notes": .string(arguments.notes),
    ]
    switch arguments.allDayMode.lowercased() {
    case "true":
      toolArguments["is_all_day"] = .bool(true)
    case "false":
      toolArguments["is_all_day"] = .bool(false)
    default:
      break
    }

    return await executeMutation(
      name: name,
      action: "Kalenderereignis ändern",
      details: "Event-ID: \(arguments.eventID)",
      arguments: toolArguments
    )
  }
}

private struct CalendarDeleteEventTool: Tool {
  let name = "calendar_delete_event"
  let description = "Delete one macOS Calendar event by the exact identifier returned by calendar_list_events. Use only when the user explicitly asks to delete the event. AgenTM5N shows a confirmation dialog before deletion."

  @Generable
  struct Arguments {
    @Guide(description: "Exact event identifier returned by calendar_list_events")
    var eventID: String
  }

  func call(arguments: Arguments) async throws -> String {
    await executeMutation(
      name: name,
      action: "Kalenderereignis löschen",
      details: "Event-ID: \(arguments.eventID)",
      arguments: [
        "event_id": .string(arguments.eventID)
      ]
    )
  }
}

private struct ContactsCreateTool: Tool {
  let name = "contacts_create"
  let description = "Create a macOS Contact only when the user explicitly asks to save a new contact. AgenTM5N shows a confirmation dialog first."

  @Generable
  struct Arguments {
    @Guide(description: "Given name")
    var givenName: String

    @Guide(description: "Family name, or an empty string")
    var familyName: String

    @Guide(description: "Organization, or an empty string")
    var organization: String

    @Guide(description: "Email address, or an empty string")
    var email: String

    @Guide(description: "Phone number, or an empty string")
    var phone: String
  }

  func call(arguments: Arguments) async throws -> String {
    await executeMutation(
      name: name,
      action: "Kontakt erstellen",
      details: [arguments.givenName, arguments.familyName, arguments.email, arguments.phone]
        .filter { !$0.isEmpty }
        .joined(separator: " · "),
      arguments: [
        "given_name": .string(arguments.givenName),
        "family_name": .string(arguments.familyName),
        "organization": .string(arguments.organization),
        "email": .string(arguments.email),
        "phone": .string(arguments.phone),
      ]
    )
  }
}

private struct ContactsUpdateTool: Tool {
  let name = "contacts_update"
  let description = "Update an existing macOS Contact by the exact contact identifier returned by contacts_search. Empty fields mean unchanged. AgenTM5N shows a confirmation dialog first."

  @Generable
  struct Arguments {
    @Guide(description: "Exact contact identifier returned by contacts_search")
    var contactID: String

    @Guide(description: "New given name, or an empty string")
    var givenName: String

    @Guide(description: "New family name, or an empty string")
    var familyName: String

    @Guide(description: "New organization, or an empty string")
    var organization: String

    @Guide(description: "New email address, or an empty string")
    var email: String

    @Guide(description: "New phone number, or an empty string")
    var phone: String
  }

  func call(arguments: Arguments) async throws -> String {
    await executeMutation(
      name: name,
      action: "Kontakt ändern",
      details: "Kontakt-ID: \(arguments.contactID)",
      arguments: [
        "contact_id": .string(arguments.contactID),
        "given_name": .string(arguments.givenName),
        "family_name": .string(arguments.familyName),
        "organization": .string(arguments.organization),
        "email": .string(arguments.email),
        "phone": .string(arguments.phone),
      ]
    )
  }
}

private struct MailCreateDraftTool: Tool {
  let name = "mail_create_draft"
  let description = "Create an Apple Mail draft without sending it. Use only when the user wants a draft prepared. AgenTM5N shows a confirmation dialog before creating the draft."

  @Generable
  struct Arguments {
    @Guide(description: "To recipients, comma- or semicolon-separated")
    var to: String

    @Guide(description: "CC recipients, or an empty string")
    var cc: String

    @Guide(description: "BCC recipients, or an empty string")
    var bcc: String

    @Guide(description: "Message subject")
    var subject: String

    @Guide(description: "Complete plain-text message body")
    var body: String
  }

  func call(arguments: Arguments) async throws -> String {
    await executeMutation(
      name: name,
      action: "E-Mail-Entwurf erstellen",
      details: "An: \(arguments.to)\nBetreff: \(arguments.subject)",
      arguments: mailArguments(arguments)
    )
  }

  private func mailArguments(_ arguments: Arguments) -> [String: JSONValue] {
    [
      "to": .string(arguments.to),
      "cc": .string(arguments.cc),
      "bcc": .string(arguments.bcc),
      "subject": .string(arguments.subject),
      "body": .string(arguments.body),
    ]
  }
}

private struct MailSendTool: Tool {
  let name = "mail_send"
  let description = "Immediately send a new Apple Mail message. Use only when the user explicitly asks to send, not merely draft or compose. AgenTM5N always shows a final confirmation dialog."

  @Generable
  struct Arguments {
    @Guide(description: "To recipients, comma- or semicolon-separated")
    var to: String

    @Guide(description: "CC recipients, or an empty string")
    var cc: String

    @Guide(description: "BCC recipients, or an empty string")
    var bcc: String

    @Guide(description: "Message subject")
    var subject: String

    @Guide(description: "Complete plain-text message body")
    var body: String
  }

  func call(arguments: Arguments) async throws -> String {
    await executeMutation(
      name: name,
      action: "E-Mail jetzt senden",
      details: "An: \(arguments.to)\nBetreff: \(arguments.subject)",
      arguments: [
        "to": .string(arguments.to),
        "cc": .string(arguments.cc),
        "bcc": .string(arguments.bcc),
        "subject": .string(arguments.subject),
        "body": .string(arguments.body),
      ]
    )
  }
}

private struct MailReplyTool: Tool {
  let name = "mail_reply"
  let description = "Reply to one Apple Mail inbox message by message ID. send_now=false saves a reply draft; send_now=true sends immediately. AgenTM5N always shows a confirmation dialog."

  @Generable
  struct Arguments {
    @Guide(description: "Numeric message ID returned by mail_list_recent")
    var messageID: Int

    @Guide(description: "Reply body")
    var body: String

    @Guide(description: "true sends immediately; false saves a draft reply")
    var sendNow: Bool
  }

  func call(arguments: Arguments) async throws -> String {
    await executeMutation(
      name: name,
      action: arguments.sendNow ? "Antwort jetzt senden" : "Antwortentwurf erstellen",
      details: "Mail-ID: \(arguments.messageID)",
      arguments: [
        "message_id": .number(Double(arguments.messageID)),
        "body": .string(arguments.body),
        "send_now": .bool(arguments.sendNow),
      ]
    )
  }
}

private func executeRead(
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

private func executeMutation(
  name: String,
  action: String,
  details: String,
  arguments: [String: JSONValue]
) async -> String {
  let confirmed = await MacNativeMutationConfirmation.confirm(
    action: action,
    details: details
  )
  guard confirmed else {
    return "TOOL_DENIED: The user cancelled the macOS mutation."
  }

  let result = await MacNativeMutationAgentTools.execute(
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
