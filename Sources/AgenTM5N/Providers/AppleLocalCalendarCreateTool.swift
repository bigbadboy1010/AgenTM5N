import AppKit
import Foundation
import FoundationModels

struct AppleLocalCalendarCreateTool: Tool {
  let name = "calendar_create_event"
  let description = "Create a macOS Calendar event from explicit local calendar components. Use this tool for all new calendar events. Do not convert local dates to UTC or infer the current date from existing calendar entries."

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

    @Guide(description: "Start hour in local Mac time, 0 through 23", .range(0...23))
    var startHour: Int

    @Guide(description: "Start minute", .range(0...59))
    var startMinute: Int

    @Guide(description: "End year", .range(2000...2100))
    var endYear: Int

    @Guide(description: "End month", .range(1...12))
    var endMonth: Int

    @Guide(description: "End day of month", .range(1...31))
    var endDay: Int

    @Guide(description: "End hour in local Mac time, 0 through 23", .range(0...23))
    var endHour: Int

    @Guide(description: "End minute", .range(0...59))
    var endMinute: Int

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
    let timeZone = TimeZone.current

    do {
      let start = try Self.localDate(
        year: arguments.startYear,
        month: arguments.startMonth,
        day: arguments.startDay,
        hour: arguments.startHour,
        minute: arguments.startMinute,
        timeZone: timeZone,
        field: "start"
      )
      let end = try Self.localDate(
        year: arguments.endYear,
        month: arguments.endMonth,
        day: arguments.endDay,
        hour: arguments.endHour,
        minute: arguments.endMinute,
        timeZone: timeZone,
        field: "end"
      )

      guard end > start else {
        return Self.errorOutput(
          code: "dates_inverted",
          message: "The end date must be later than the start date.",
          start: start,
          end: end,
          timeZone: timeZone
        )
      }

      let startText = Self.localISO8601(start, timeZone: timeZone)
      let endText = Self.localISO8601(end, timeZone: timeZone)
      let allowed = await MainActor.run {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "AgenTM5N-Aktion bestätigen"
        alert.informativeText = "Kalenderereignis erstellen\n\n\(arguments.title)\n\(startText) → \(endText)\nZeitzone: \(timeZone.identifier)"
        alert.addButton(withTitle: "Erstellen")
        alert.addButton(withTitle: "Abbrechen")
        return alert.runModal() == .alertFirstButtonReturn
      }

      guard allowed else {
        return "CALENDAR_TOOL_CANCELLED_BY_USER"
      }

      let descriptor = try await MacNativeMutationService.shared.createCalendarEvent(
        title: arguments.title,
        startDate: start,
        endDate: end,
        calendarTitle: Self.normalized(arguments.calendar),
        location: Self.normalized(arguments.location),
        notes: Self.normalized(arguments.notes),
        isAllDay: arguments.isAllDay
      )

      return Self.successOutput(
        descriptor: descriptor,
        start: start,
        end: end,
        timeZone: timeZone
      )
    } catch {
      return Self.errorOutput(
        code: "calendar_create_failed",
        message: error.localizedDescription,
        start: nil,
        end: nil,
        timeZone: timeZone
      )
    }
  }

  private static func localDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    timeZone: TimeZone,
    field: String
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
      throw LocalCalendarDateError.invalid(field)
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
      throw LocalCalendarDateError.invalid(field)
    }

    return date
  }

  private static func normalized(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func localISO8601(_ date: Date, timeZone: TimeZone) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = timeZone
    return formatter.string(from: date)
  }

  private static func successOutput(
    descriptor: MacCalendarMutationDescriptor,
    start: Date,
    end: Date,
    timeZone: TimeZone
  ) -> String {
    let payload: [String: String] = [
      "status": "created",
      "event_id": descriptor.identifier,
      "title": descriptor.title,
      "calendar": descriptor.calendarTitle,
      "start_local": localISO8601(start, timeZone: timeZone),
      "end_local": localISO8601(end, timeZone: timeZone),
      "time_zone": timeZone.identifier,
      "source": "EventKit",
    ]
    return encoded(payload, fallback: "CALENDAR_TOOL_SUCCESS")
  }

  private static func errorOutput(
    code: String,
    message: String,
    start: Date?,
    end: Date?,
    timeZone: TimeZone
  ) -> String {
    var payload: [String: String] = [
      "status": "error",
      "code": code,
      "message": message,
      "time_zone": timeZone.identifier,
      "source": "AgenTM5N/EventKit",
    ]
    if let start {
      payload["start_local"] = localISO8601(start, timeZone: timeZone)
    }
    if let end {
      payload["end_local"] = localISO8601(end, timeZone: timeZone)
    }
    return encoded(payload, fallback: "CALENDAR_TOOL_ERROR|\(code)|\(message)")
  }

  private static func encoded(
    _ payload: [String: String],
    fallback: String
  ) -> String {
    guard JSONSerialization.isValidJSONObject(payload),
      let data = try? JSONSerialization.data(
        withJSONObject: payload,
        options: [.sortedKeys]
      )
    else {
      return fallback
    }
    return String(decoding: data, as: UTF8.self)
  }
}

private enum LocalCalendarDateError: LocalizedError {
  case invalid(String)

  var errorDescription: String? {
    switch self {
    case .invalid(let field):
      return "Invalid local \(field) date components."
    }
  }
}
