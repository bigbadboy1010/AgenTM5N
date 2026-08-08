import Foundation
import FoundationModels

public enum AppleRoutedMacNativeTools {
  public static func makeTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    [
      RoutedCalendarListEventsTool(bridge: bridge),
      RoutedContactsSearchTool(bridge: bridge),
      RoutedMailListRecentTool(bridge: bridge),
      RoutedMailReadMessageTool(bridge: bridge),
      RoutedCalendarCreateEventTool(bridge: bridge),
      RoutedCalendarUpdateEventTool(bridge: bridge),
      RoutedCalendarDeleteEventTool(bridge: bridge),
      RoutedContactsCreateTool(bridge: bridge),
      RoutedContactsUpdateTool(bridge: bridge),
      RoutedMailCreateDraftTool(bridge: bridge),
      RoutedMailSendTool(bridge: bridge),
      RoutedMailReplyTool(bridge: bridge),
    ]
  }
}

private struct RoutedCalendarListEventsTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "calendar_list_events"
  let description = "Read upcoming events from the user's macOS Calendar. Calendar results are records, not a source for the current date."

  @Generable
  struct Arguments {
    @Guide(description: "Number of days to inspect from now", .range(1...30))
    var days: Int

    @Guide(description: "Maximum number of events to return", .range(1...100))
    var limit: Int
  }

  func call(arguments: Arguments) async throws -> String {
    await route(
      bridge: bridge,
      name: name,
      arguments: [
        "days": .number(Double(arguments.days)),
        "limit": .number(Double(arguments.limit)),
      ]
    )
  }
}

private struct RoutedContactsSearchTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "contacts_search"
  let description = "Search the user's macOS Contacts by person name or organization when contact information is relevant."

  @Generable
  struct Arguments {
    @Guide(description: "Person name or organization to search for")
    var query: String

    @Guide(description: "Maximum number of contacts to return", .range(1...100))
    var limit: Int
  }

  func call(arguments: Arguments) async throws -> String {
    await route(
      bridge: bridge,
      name: name,
      arguments: [
        "query": .string(arguments.query),
        "limit": .number(Double(arguments.limit)),
      ]
    )
  }
}

private struct RoutedMailListRecentTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "mail_list_recent"
  let description = "List recent messages from the user's Apple Mail inbox with bounded metadata."

  @Generable
  struct Arguments {
    @Guide(description: "Maximum number of recent inbox messages", .range(1...25))
    var limit: Int
  }

  func call(arguments: Arguments) async throws -> String {
    await route(
      bridge: bridge,
      name: name,
      arguments: ["limit": .number(Double(arguments.limit))]
    )
  }
}

private struct RoutedMailReadMessageTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "mail_read_message"
  let description = "Read one Apple Mail inbox message by the numeric ID returned by mail_list_recent."

  @Generable
  struct Arguments {
    @Guide(description: "Numeric Apple Mail message ID")
    var messageID: Int

    @Guide(description: "Maximum body characters", .range(500...12_000))
    var maximumCharacters: Int
  }

  func call(arguments: Arguments) async throws -> String {
    await route(
      bridge: bridge,
      name: name,
      arguments: [
        "message_id": .number(Double(arguments.messageID)),
        "maximum_characters": .number(Double(arguments.maximumCharacters)),
      ]
    )
  }
}

private struct RoutedCalendarCreateEventTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "calendar_create_event"
  let description = "Create a macOS Calendar event from explicit local calendar components. Never convert the user's local wall-clock time to UTC before calling this tool."

  @Generable
  struct Arguments {
    @Guide(description: "Event title")
    var title: String

    @Guide(description: "Start year", .range(2000...2100))
    var startYear: Int

    @Guide(description: "Start month", .range(1...12))
    var startMonth: Int

    @Guide(description: "Start day of month", .range(1...31))
    var startDay: Int

    @Guide(description: "Start hour in local Mac time", .range(0...23))
    var startHour: Int

    @Guide(description: "Start minute", .range(0...59))
    var startMinute: Int

    @Guide(description: "End year", .range(2000...2100))
    var endYear: Int

    @Guide(description: "End month", .range(1...12))
    var endMonth: Int

    @Guide(description: "End day of month", .range(1...31))
    var endDay: Int

    @Guide(description: "End hour in local Mac time", .range(0...23))
    var endHour: Int

    @Guide(description: "End minute", .range(0...59))
    var endMinute: Int

    @Guide(description: "Exact writable calendar title, or an empty string for the default")
    var calendar: String

    @Guide(description: "Location, or an empty string")
    var location: String

    @Guide(description: "Notes, or an empty string")
    var notes: String

    @Guide(description: "Whether this is an all-day event")
    var isAllDay: Bool
  }

  func call(arguments: Arguments) async throws -> String {
    let timeZone = TimeZone.current
    do {
      let start = try localDate(
        year: arguments.startYear,
        month: arguments.startMonth,
        day: arguments.startDay,
        hour: arguments.startHour,
        minute: arguments.startMinute,
        timeZone: timeZone
      )
      let end = try localDate(
        year: arguments.endYear,
        month: arguments.endMonth,
        day: arguments.endDay,
        hour: arguments.endHour,
        minute: arguments.endMinute,
        timeZone: timeZone
      )
      guard end > start else {
        return "TOOL_ERROR: Calendar end must be later than start."
      }

      return await route(
        bridge: bridge,
        name: name,
        arguments: [
          "title": .string(arguments.title),
          "start": .string(localISO8601(start, timeZone: timeZone)),
          "end": .string(localISO8601(end, timeZone: timeZone)),
          "calendar": .string(arguments.calendar),
          "location": .string(arguments.location),
          "notes": .string(arguments.notes),
          "is_all_day": .bool(arguments.isAllDay),
        ]
      )
    } catch {
      return "TOOL_ERROR: \(error.localizedDescription)"
    }
  }
}

private struct RoutedCalendarUpdateEventTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "calendar_update_event"
  let description = "Update an existing macOS Calendar event by the exact event identifier returned by calendar_list_events. Empty text values leave fields unchanged."

  @Generable
  struct Arguments {
    @Guide(description: "Exact event identifier")
    var eventID: String

    @Guide(description: "New title, or an empty string")
    var title: String

    @Guide(description: "New ISO-8601 start date with explicit offset, or an empty string")
    var start: String

    @Guide(description: "New ISO-8601 end date with explicit offset, or an empty string")
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
    var values: [String: JSONValue] = [
      "event_id": .string(arguments.eventID),
      "title": .string(arguments.title),
      "start": .string(arguments.start),
      "end": .string(arguments.end),
      "calendar": .string(arguments.calendar),
      "location": .string(arguments.location),
      "notes": .string(arguments.notes),
    ]
    switch arguments.allDayMode.lowercased() {
    case "true": values["is_all_day"] = .bool(true)
    case "false": values["is_all_day"] = .bool(false)
    default: break
    }
    return await route(bridge: bridge, name: name, arguments: values)
  }
}

private struct RoutedCalendarDeleteEventTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "calendar_delete_event"
  let description = "Delete one macOS Calendar event by its exact event identifier. Use only when the user explicitly requests deletion."

  @Generable
  struct Arguments {
    @Guide(description: "Exact event identifier")
    var eventID: String
  }

  func call(arguments: Arguments) async throws -> String {
    await route(
      bridge: bridge,
      name: name,
      arguments: ["event_id": .string(arguments.eventID)]
    )
  }
}

private struct RoutedContactsCreateTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "contacts_create"
  let description = "Create a new macOS Contact only when the user explicitly asks to save it."

  @Generable
  struct Arguments {
    @Guide(description: "Given name")
    var givenName: String
    @Guide(description: "Family name, or an empty string")
    var familyName: String
    @Guide(description: "Organization, or an empty string")
    var organization: String
    @Guide(description: "Email, or an empty string")
    var email: String
    @Guide(description: "Phone number, or an empty string")
    var phone: String
  }

  func call(arguments: Arguments) async throws -> String {
    await route(
      bridge: bridge,
      name: name,
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

private struct RoutedContactsUpdateTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "contacts_update"
  let description = "Update a macOS Contact by the exact contact identifier returned by contacts_search. Empty values leave fields unchanged."

  @Generable
  struct Arguments {
    @Guide(description: "Exact contact identifier")
    var contactID: String
    @Guide(description: "New given name, or an empty string")
    var givenName: String
    @Guide(description: "New family name, or an empty string")
    var familyName: String
    @Guide(description: "New organization, or an empty string")
    var organization: String
    @Guide(description: "New email, or an empty string")
    var email: String
    @Guide(description: "New phone number, or an empty string")
    var phone: String
  }

  func call(arguments: Arguments) async throws -> String {
    await route(
      bridge: bridge,
      name: name,
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

private struct RoutedMailCreateDraftTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "mail_create_draft"
  let description = "Create and save an Apple Mail draft without sending it."

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
    @Guide(description: "Complete plain-text body")
    var body: String
  }

  func call(arguments: Arguments) async throws -> String {
    await route(bridge: bridge, name: name, arguments: mailArguments(arguments))
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

private struct RoutedMailSendTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "mail_send"
  let description = "Immediately send a new Apple Mail message. Use only when the user explicitly asks to send it."

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
    @Guide(description: "Complete plain-text body")
    var body: String
  }

  func call(arguments: Arguments) async throws -> String {
    await route(
      bridge: bridge,
      name: name,
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

private struct RoutedMailReplyTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "mail_reply"
  let description = "Reply to an Apple Mail message by ID. send_now=false saves a draft; send_now=true sends immediately."

  @Generable
  struct Arguments {
    @Guide(description: "Numeric message ID returned by mail_list_recent")
    var messageID: Int
    @Guide(description: "Reply body")
    var body: String
    @Guide(description: "true sends immediately; false saves a draft")
    var sendNow: Bool
  }

  func call(arguments: Arguments) async throws -> String {
    await route(
      bridge: bridge,
      name: name,
      arguments: [
        "message_id": .number(Double(arguments.messageID)),
        "body": .string(arguments.body),
        "send_now": .bool(arguments.sendNow),
      ]
    )
  }
}

private func route(
  bridge: AgentToolExecutionBridge,
  name: String,
  arguments: [String: JSONValue]
) async -> String {
  await bridge.execute(
    ProviderToolCall(
      function: ProviderToolCall.Function(
        name: name,
        arguments: arguments
      )
    )
  )
}

private func localDate(
  year: Int,
  month: Int,
  day: Int,
  hour: Int,
  minute: Int,
  timeZone: TimeZone
) throws -> Date {
  var calendar = Calendar(identifier: .gregorian)
  calendar.locale = Locale(identifier: "en_US_POSIX")
  calendar.timeZone = timeZone

  var components = DateComponents()
  components.calendar = calendar
  components.timeZone = timeZone
  components.year = year
  components.month = month
  components.day = day
  components.hour = hour
  components.minute = minute
  components.second = 0

  guard let date = calendar.date(from: components) else {
    throw RoutedCalendarDateError.invalid
  }
  let resolved = calendar.dateComponents(
    [.year, .month, .day, .hour, .minute],
    from: date
  )
  guard
    resolved.year == year,
    resolved.month == month,
    resolved.day == day,
    resolved.hour == hour,
    resolved.minute == minute
  else {
    throw RoutedCalendarDateError.invalid
  }
  return date
}

private func localISO8601(_ date: Date, timeZone: TimeZone) -> String {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  formatter.timeZone = timeZone
  return formatter.string(from: date)
}

private enum RoutedCalendarDateError: LocalizedError {
  case invalid

  var errorDescription: String? {
    "Invalid local calendar date components."
  }
}
