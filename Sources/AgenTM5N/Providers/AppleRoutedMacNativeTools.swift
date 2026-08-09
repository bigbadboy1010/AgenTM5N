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

    @Guide(description: "Optional exact writable calendar title. Omit for default calendar.")
    var calendar: String? = nil

    @Guide(description: "Optional location")
    var location: String? = nil

    @Guide(description: "Optional notes")
    var notes: String? = nil

    @Guide(description: "Optional all-day flag. Defaults to false.")
    var isAllDay: Bool? = nil
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

      var values: [String: JSONValue] = [
        "title": .string(arguments.title),
        "start": .string(localISO8601(start, timeZone: timeZone)),
        "end": .string(localISO8601(end, timeZone: timeZone)),
      ]
      if let calendar = normalizedMac(arguments.calendar) {
        values["calendar"] = .string(calendar)
      }
      if let location = normalizedMac(arguments.location, preserveWhitespace: true) {
        values["location"] = .string(location)
      }
      if let notes = normalizedMac(arguments.notes, preserveWhitespace: true) {
        values["notes"] = .string(notes)
      }
      if let isAllDay = arguments.isAllDay {
        values["is_all_day"] = .bool(isAllDay)
      }

      return await route(bridge: bridge, name: name, arguments: values)
    } catch {
      return "TOOL_ERROR: \(error.localizedDescription)"
    }
  }
}

private struct RoutedCalendarUpdateEventTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "calendar_update_event"
  let description = "Update an existing macOS Calendar event by the exact event identifier returned by calendar_list_events. Omitted values leave fields unchanged."

  @Generable
  struct Arguments {
    @Guide(description: "Exact event identifier")
    var eventID: String

    @Guide(description: "Optional new title")
    var title: String? = nil

    @Guide(description: "Optional new ISO-8601 start date with explicit offset")
    var start: String? = nil

    @Guide(description: "Optional new ISO-8601 end date with explicit offset")
    var end: String? = nil

    @Guide(description: "Optional new exact calendar title")
    var calendar: String? = nil

    @Guide(description: "Optional new location")
    var location: String? = nil

    @Guide(description: "Optional new notes")
    var notes: String? = nil

    @Guide(description: "Optional all-day mode: true or false. Omit to preserve current value.")
    var allDayMode: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = ["event_id": .string(arguments.eventID)]
    if let title = normalizedMac(arguments.title, preserveWhitespace: true) {
      values["title"] = .string(title)
    }
    if let start = normalizedMac(arguments.start) {
      values["start"] = .string(start)
    }
    if let end = normalizedMac(arguments.end) {
      values["end"] = .string(end)
    }
    if let calendar = normalizedMac(arguments.calendar) {
      values["calendar"] = .string(calendar)
    }
    if let location = normalizedMac(arguments.location, preserveWhitespace: true) {
      values["location"] = .string(location)
    }
    if let notes = normalizedMac(arguments.notes, preserveWhitespace: true) {
      values["notes"] = .string(notes)
    }
    switch normalizedMac(arguments.allDayMode)?.lowercased() {
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

    @Guide(description: "Optional family name")
    var familyName: String? = nil

    @Guide(description: "Optional organization")
    var organization: String? = nil

    @Guide(description: "Optional email")
    var email: String? = nil

    @Guide(description: "Optional phone number")
    var phone: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = ["given_name": .string(arguments.givenName)]
    if let familyName = normalizedMac(arguments.familyName) {
      values["family_name"] = .string(familyName)
    }
    if let organization = normalizedMac(arguments.organization) {
      values["organization"] = .string(organization)
    }
    if let email = normalizedMac(arguments.email) {
      values["email"] = .string(email)
    }
    if let phone = normalizedMac(arguments.phone) {
      values["phone"] = .string(phone)
    }
    return await route(bridge: bridge, name: name, arguments: values)
  }
}

private struct RoutedContactsUpdateTool: Tool {
  let bridge: AgentToolExecutionBridge
  let name = "contacts_update"
  let description = "Update a macOS Contact by the exact contact identifier returned by contacts_search. Omitted values leave fields unchanged."

  @Generable
  struct Arguments {
    @Guide(description: "Exact contact identifier")
    var contactID: String

    @Guide(description: "Optional new given name")
    var givenName: String? = nil

    @Guide(description: "Optional new family name")
    var familyName: String? = nil

    @Guide(description: "Optional new organization")
    var organization: String? = nil

    @Guide(description: "Optional new email")
    var email: String? = nil

    @Guide(description: "Optional new phone number")
    var phone: String? = nil
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = ["contact_id": .string(arguments.contactID)]
    if let givenName = normalizedMac(arguments.givenName) {
      values["given_name"] = .string(givenName)
    }
    if let familyName = normalizedMac(arguments.familyName) {
      values["family_name"] = .string(familyName)
    }
    if let organization = normalizedMac(arguments.organization) {
      values["organization"] = .string(organization)
    }
    if let email = normalizedMac(arguments.email) {
      values["email"] = .string(email)
    }
    if let phone = normalizedMac(arguments.phone) {
      values["phone"] = .string(phone)
    }
    return await route(bridge: bridge, name: name, arguments: values)
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

    @Guide(description: "Optional CC recipients")
    var cc: String? = nil

    @Guide(description: "Optional BCC recipients")
    var bcc: String? = nil

    @Guide(description: "Message subject")
    var subject: String

    @Guide(description: "Complete plain-text body")
    var body: String
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "to": .string(arguments.to),
      "subject": .string(arguments.subject),
      "body": .string(arguments.body),
    ]
    if let cc = normalizedMac(arguments.cc) { values["cc"] = .string(cc) }
    if let bcc = normalizedMac(arguments.bcc) { values["bcc"] = .string(bcc) }
    return await route(bridge: bridge, name: name, arguments: values)
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

    @Guide(description: "Optional CC recipients")
    var cc: String? = nil

    @Guide(description: "Optional BCC recipients")
    var bcc: String? = nil

    @Guide(description: "Message subject")
    var subject: String

    @Guide(description: "Complete plain-text body")
    var body: String
  }

  func call(arguments: Arguments) async throws -> String {
    var values: [String: JSONValue] = [
      "to": .string(arguments.to),
      "subject": .string(arguments.subject),
      "body": .string(arguments.body),
    ]
    if let cc = normalizedMac(arguments.cc) { values["cc"] = .string(cc) }
    if let bcc = normalizedMac(arguments.bcc) { values["bcc"] = .string(bcc) }
    return await route(bridge: bridge, name: name, arguments: values)
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

private func normalizedMac(
  _ value: String?,
  preserveWhitespace: Bool = false
) -> String? {
  guard let value else { return nil }
  if preserveWhitespace {
    return value.isEmpty ? nil : value
  }
  let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
  return normalized.isEmpty ? nil : normalized
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
