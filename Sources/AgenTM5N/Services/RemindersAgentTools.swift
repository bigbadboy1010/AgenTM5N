import EventKit
import Foundation

public enum RemindersAgentToolError: LocalizedError {
  case accessDenied
  case reminderNotFound(String)
  case noDefaultList
  case invalidDueDate(String)

  public var errorDescription: String? {
    switch self {
    case .accessDenied:
      return "AgenTM5N hat keinen vollständigen Zugriff auf Erinnerungen. Erlaube den Zugriff in den macOS-Datenschutzeinstellungen."
    case .reminderNotFound(let value):
      return "Erinnerung nicht gefunden: \(value)"
    case .noDefaultList:
      return "Es ist keine Standardliste für neue Erinnerungen verfügbar."
    case .invalidDueDate(let value):
      return "Ungültiges Fälligkeitsdatum: \(value). Verwende ISO-8601 oder lasse es weg."
    }
  }
}

public struct ReminderDescriptor: Codable, Equatable, Sendable {
  public let identifier: String
  public let title: String
  public let list: String
  public let dueDate: Date?
  public let completed: Bool
  public let priority: Int
  public let notes: String?
}

public actor RemindersToolService {
  public static let shared = RemindersToolService()
  private let eventStore: EKEventStore

  public init(eventStore: EKEventStore = EKEventStore()) {
    self.eventStore = eventStore
  }

  public func list(limit: Int) async throws -> [ReminderDescriptor] {
    try await ensureAccess()
    let predicate = eventStore.predicateForIncompleteReminders(
      withDueDateStarting: nil,
      ending: nil,
      calendars: nil
    )
    let reminders = try await fetch(predicate: predicate)
    return reminders
      .sorted { lhs, rhs in
        let left = dueDate(lhs) ?? .distantFuture
        let right = dueDate(rhs) ?? .distantFuture
        if left == right {
          return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return left < right
      }
      .prefix(max(1, min(limit, 100)))
      .map(descriptor)
  }

  public func create(
    title: String,
    notes: String?,
    dueDateText: String?,
    listName: String?
  ) async throws -> ReminderDescriptor {
    try await ensureAccess()
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedTitle.isEmpty else {
      throw MacNativeToolError.invalidArgument(tool: "reminders_create", name: "title")
    }

    let calendar: EKCalendar
    if let listName,
      !listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let matched = eventStore.calendars(for: .reminder).first(where: {
        $0.title.caseInsensitiveCompare(listName) == .orderedSame
      })
    {
      calendar = matched
    } else if let defaultCalendar = eventStore.defaultCalendarForNewReminders() {
      calendar = defaultCalendar
    } else {
      throw RemindersAgentToolError.noDefaultList
    }

    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = normalizedTitle
    reminder.calendar = calendar
    if let notes {
      let normalized = notes.trimmingCharacters(in: .whitespacesAndNewlines)
      reminder.notes = normalized.isEmpty ? nil : normalized
    }
    if let dueDateText,
      !dueDateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      let dueDate = try parseDate(dueDateText)
      reminder.dueDateComponents = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute, .second, .timeZone],
        from: dueDate
      )
    }

    try eventStore.save(reminder, commit: true)
    return descriptor(reminder)
  }

  public func complete(query: String) async throws -> ReminderDescriptor {
    try await ensureAccess()
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let reminder: EKReminder?
    if let byID = eventStore.calendarItem(withIdentifier: normalized) as? EKReminder {
      reminder = byID
    } else {
      let predicate = eventStore.predicateForIncompleteReminders(
        withDueDateStarting: nil,
        ending: nil,
        calendars: nil
      )
      let candidates = try await fetch(predicate: predicate).filter {
        $0.title.caseInsensitiveCompare(normalized) == .orderedSame
      }
      reminder = candidates.count == 1 ? candidates.first : nil
    }

    guard let reminder else {
      throw RemindersAgentToolError.reminderNotFound(query)
    }
    reminder.isCompleted = true
    reminder.completionDate = Date()
    try eventStore.save(reminder, commit: true)
    return descriptor(reminder)
  }

  private func ensureAccess() async throws {
    switch EKEventStore.authorizationStatus(for: .reminder) {
    case .fullAccess:
      return
    case .notDetermined:
      let granted = try await eventStore.requestFullAccessToReminders()
      guard granted else { throw RemindersAgentToolError.accessDenied }
    case .authorized:
      return
    case .denied, .restricted, .writeOnly:
      throw RemindersAgentToolError.accessDenied
    @unknown default:
      throw RemindersAgentToolError.accessDenied
    }
  }

  private func fetch(predicate: NSPredicate) async throws -> [EKReminder] {
    try await withCheckedThrowingContinuation { continuation in
      eventStore.fetchReminders(matching: predicate) { reminders in
        continuation.resume(returning: reminders ?? [])
      }
    }
  }

  private func descriptor(_ reminder: EKReminder) -> ReminderDescriptor {
    ReminderDescriptor(
      identifier: reminder.calendarItemIdentifier,
      title: reminder.title,
      list: reminder.calendar.title,
      dueDate: dueDate(reminder),
      completed: reminder.isCompleted,
      priority: reminder.priority,
      notes: reminder.notes
    )
  }

  private func dueDate(_ reminder: EKReminder) -> Date? {
    guard let components = reminder.dueDateComponents else { return nil }
    return Calendar.current.date(from: components)
  }

  private func parseDate(_ value: String) throws -> Date {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: normalized) {
      return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: normalized) {
      return date
    }
    throw RemindersAgentToolError.invalidDueDate(value)
  }
}

public enum RemindersAgentTools {
  public static let definitions: [ProviderToolDefinition] = [
    ProviderToolDefinition(
      name: "reminders_list",
      description: "List incomplete macOS Reminders with title, list, due date, priority, and stable identifier. Requires Reminders full access.",
      parameters: objectSchema(
        properties: [
          "limit": integerSchema(
            description: "Maximum reminders from 1 to 100. Defaults to 25.",
            minimum: 1,
            maximum: 100
          )
        ]
      )
    ),
    ProviderToolDefinition(
      name: "reminders_create",
      description: "Create a macOS Reminder. This is a personal-data mutation and requires AgenTM5N confirmation unless Full Access is active.",
      parameters: objectSchema(
        required: ["title"],
        properties: [
          "title": stringSchema("Reminder title."),
          "notes": stringSchema("Optional notes."),
          "due_date": stringSchema("Optional ISO-8601 due date/time."),
          "list": stringSchema("Optional exact Reminders list name. Defaults to the system default list.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "reminders_complete",
      description: "Mark one incomplete macOS Reminder complete by exact identifier or unique exact title.",
      parameters: objectSchema(
        required: ["reminder"],
        properties: [
          "reminder": stringSchema("Exact reminder identifier or unique exact title.")
        ]
      )
    )
  ]

  public static func handles(_ call: ProviderToolCall) -> Bool {
    definitions.contains { $0.function.name == call.function.name }
  }

  public static func risk(for call: ProviderToolCall) -> ToolRisk {
    call.function.name == "reminders_list" ? .read : .write
  }

  public static func summary(for call: ProviderToolCall) -> String {
    let arguments = call.function.arguments.keys.sorted().compactMap { key -> String? in
      guard let value = call.function.arguments[key] else { return nil }
      let rendered = value.compactDescription
      return "\(key): \(rendered.count > 180 ? String(rendered.prefix(180)) + "…" : rendered)"
    }
    return arguments.isEmpty
      ? call.function.name
      : "\(call.function.name) — \(arguments.joined(separator: ", "))"
  }

  private static func objectSchema(
    required: [String] = [],
    properties: [String: JSONValue]
  ) -> JSONValue {
    var schema: [String: JSONValue] = [
      "type": .string("object"),
      "properties": .object(properties),
      "additionalProperties": .bool(false),
    ]
    if !required.isEmpty {
      schema["required"] = .array(required.map(JSONValue.string))
    }
    return .object(schema)
  }

  private static func stringSchema(_ description: String) -> JSONValue {
    .object([
      "type": .string("string"),
      "description": .string(description),
    ])
  }

  private static func integerSchema(
    description: String,
    minimum: Int,
    maximum: Int
  ) -> JSONValue {
    .object([
      "type": .string("integer"),
      "description": .string(description),
      "minimum": .number(Double(minimum)),
      "maximum": .number(Double(maximum)),
    ])
  }
}
