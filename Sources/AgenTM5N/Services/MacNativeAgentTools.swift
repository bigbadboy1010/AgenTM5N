import AppKit
import Contacts
import EventKit
import Foundation

public enum MacNativeToolError: LocalizedError {
  case invalidArgument(tool: String, name: String)
  case calendarAccessDenied
  case calendarFullAccessRequired
  case contactsAccessDenied
  case mailAutomationFailed(String)
  case mailMessageNotFound(Int)

  public var errorDescription: String? {
    switch self {
    case .invalidArgument(let tool, let name):
      return L10n.text(
        de: "Werkzeug \(tool) erhielt ein ungültiges Argument: \(name).",
        en: "Tool \(tool) received an invalid argument: \(name).",
        fr: "L’outil \(tool) a reçu un argument invalide : \(name)."
      )
    case .calendarAccessDenied:
      return L10n.text(
        de: "AgenTM5N hat keinen Zugriff auf Kalenderdaten. Erlaube den Zugriff in den macOS-Datenschutzeinstellungen.",
        en: "AgenTM5N does not have access to calendar data. Allow access in macOS Privacy settings.",
        fr: "AgenTM5N n’a pas accès aux données du calendrier. Autorisez l’accès dans les réglages de confidentialité de macOS."
      )
    case .calendarFullAccessRequired:
      return L10n.text(
        de: "Für das Lesen von Kalenderereignissen ist vollständiger Kalenderzugriff erforderlich.",
        en: "Full calendar access is required to read calendar events.",
        fr: "L’accès complet au calendrier est requis pour lire les événements."
      )
    case .contactsAccessDenied:
      return L10n.text(
        de: "AgenTM5N hat keinen Zugriff auf Kontakte. Erlaube den Zugriff in den macOS-Datenschutzeinstellungen.",
        en: "AgenTM5N does not have access to Contacts. Allow access in macOS Privacy settings.",
        fr: "AgenTM5N n’a pas accès aux contacts. Autorisez l’accès dans les réglages de confidentialité de macOS."
      )
    case .mailAutomationFailed(let reason):
      return L10n.text(
        de: "Apple-Mail-Automation fehlgeschlagen: \(reason)",
        en: "Apple Mail automation failed: \(reason)",
        fr: "L’automatisation d’Apple Mail a échoué : \(reason)"
      )
    case .mailMessageNotFound(let identifier):
      return L10n.text(
        de: "Die Apple-Mail-Nachricht mit ID \(identifier) wurde im Posteingang nicht gefunden.",
        en: "The Apple Mail message with ID \(identifier) was not found in the inbox.",
        fr: "Le message Apple Mail avec l’identifiant \(identifier) est introuvable dans la boîte de réception."
      )
    }
  }
}

public struct MacCalendarEventDescriptor: Codable, Equatable, Sendable {
  public let identifier: String
  public let title: String
  public let startDate: Date
  public let endDate: Date
  public let isAllDay: Bool
  public let calendarTitle: String
  public let location: String?

  public init(
    identifier: String,
    title: String,
    startDate: Date,
    endDate: Date,
    isAllDay: Bool,
    calendarTitle: String,
    location: String?
  ) {
    self.identifier = identifier
    self.title = title
    self.startDate = startDate
    self.endDate = endDate
    self.isAllDay = isAllDay
    self.calendarTitle = calendarTitle
    self.location = location
  }
}

public struct MacContactDescriptor: Codable, Equatable, Sendable {
  public let identifier: String
  public let displayName: String
  public let givenName: String
  public let familyName: String
  public let organizationName: String
  public let emailAddresses: [String]
  public let phoneNumbers: [String]

  public init(
    identifier: String,
    displayName: String,
    givenName: String,
    familyName: String,
    organizationName: String,
    emailAddresses: [String],
    phoneNumbers: [String]
  ) {
    self.identifier = identifier
    self.displayName = displayName
    self.givenName = givenName
    self.familyName = familyName
    self.organizationName = organizationName
    self.emailAddresses = emailAddresses
    self.phoneNumbers = phoneNumbers
  }
}

public struct MacMailMessageDescriptor: Codable, Equatable, Sendable {
  public let identifier: Int
  public let subject: String
  public let sender: String
  public let receivedAt: String
  public let content: String?
  public let truncated: Bool

  public init(
    identifier: Int,
    subject: String,
    sender: String,
    receivedAt: String,
    content: String?,
    truncated: Bool
  ) {
    self.identifier = identifier
    self.subject = subject
    self.sender = sender
    self.receivedAt = receivedAt
    self.content = content
    self.truncated = truncated
  }
}

public actor MacNativeToolService {
  public static let shared = MacNativeToolService()

  private let eventStore: EKEventStore
  private let contactStore: CNContactStore

  public init(
    eventStore: EKEventStore = EKEventStore(),
    contactStore: CNContactStore = CNContactStore()
  ) {
    self.eventStore = eventStore
    self.contactStore = contactStore
  }

  public func calendarEvents(
    days: Int,
    limit: Int
  ) async throws -> [MacCalendarEventDescriptor] {
    let boundedDays = max(1, min(days, 30))
    let boundedLimit = max(1, min(limit, 100))
    try await ensureCalendarReadAccess()

    let start = Date()
    guard let end = Calendar.current.date(byAdding: .day, value: boundedDays, to: start) else {
      throw MacNativeToolError.invalidArgument(tool: "calendar_list_events", name: "days")
    }

    let predicate = eventStore.predicateForEvents(
      withStart: start,
      end: end,
      calendars: nil
    )
    return eventStore.events(matching: predicate)
      .sorted { lhs, rhs in
        if lhs.startDate == rhs.startDate {
          return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return lhs.startDate < rhs.startDate
      }
      .prefix(boundedLimit)
      .map { event in
        MacCalendarEventDescriptor(
          identifier: event.eventIdentifier ?? "",
          title: event.title ?? "",
          startDate: event.startDate,
          endDate: event.endDate,
          isAllDay: event.isAllDay,
          calendarTitle: event.calendar.title,
          location: normalizedOptional(event.location)
        )
      }
  }

  public func searchContacts(
    query: String,
    limit: Int
  ) async throws -> [MacContactDescriptor] {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty else {
      throw MacNativeToolError.invalidArgument(tool: "contacts_search", name: "query")
    }
    let boundedLimit = max(1, min(limit, 100))
    try await ensureContactsAccess()

    let keys: [any CNKeyDescriptor] = [
      CNContactIdentifierKey as CNKeyDescriptor,
      CNContactGivenNameKey as CNKeyDescriptor,
      CNContactFamilyNameKey as CNKeyDescriptor,
      CNContactOrganizationNameKey as CNKeyDescriptor,
      CNContactEmailAddressesKey as CNKeyDescriptor,
      CNContactPhoneNumbersKey as CNKeyDescriptor,
    ]
    let predicate = CNContact.predicateForContacts(matchingName: normalizedQuery)
    return try contactStore
      .unifiedContacts(matching: predicate, keysToFetch: keys)
      .prefix(boundedLimit)
      .map { contact in
        let personName = [contact.givenName, contact.familyName]
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
          .joined(separator: " ")
        let displayName = !personName.isEmpty
          ? personName
          : (!contact.organizationName.isEmpty ? contact.organizationName : contact.identifier)

        return MacContactDescriptor(
          identifier: contact.identifier,
          displayName: displayName,
          givenName: contact.givenName,
          familyName: contact.familyName,
          organizationName: contact.organizationName,
          emailAddresses: contact.emailAddresses.map { String($0.value) },
          phoneNumbers: contact.phoneNumbers.map { $0.value.stringValue }
        )
      }
  }

  public func recentMail(limit: Int) throws -> [MacMailMessageDescriptor] {
    let boundedLimit = max(1, min(limit, 25))
    let script = """
      on cleanText(rawValue)
        set sourceText to rawValue as text
        set AppleScript's text item delimiters to {return, linefeed, tab, ASCII character 30, ASCII character 31}
        set sourceParts to text items of sourceText
        set AppleScript's text item delimiters to " "
        set cleanedText to sourceParts as text
        set AppleScript's text item delimiters to ""
        return cleanedText
      end cleanText

      tell application id "com.apple.mail"
        set inboxMessages to messages of inbox
        set availableCount to count of inboxMessages
        set requestedCount to \(boundedLimit)
        if availableCount < requestedCount then set requestedCount to availableCount
        set fieldSeparator to ASCII character 31
        set recordSeparator to ASCII character 30
        set resultText to ""

        repeat with messageIndex from 1 to requestedCount
          set currentMessage to item messageIndex of inboxMessages
          set messageIdentifier to id of currentMessage as integer
          set messageSubject to my cleanText(subject of currentMessage)
          set messageSender to my cleanText(sender of currentMessage)
          set messageReceived to my cleanText(date received of currentMessage as text)
          set resultText to resultText & messageIdentifier & fieldSeparator & messageSubject & fieldSeparator & messageSender & fieldSeparator & messageReceived & recordSeparator
        end repeat

        return resultText
      end tell
      """

    let raw = try executeAppleScript(script)
    return raw
      .split(separator: Character(UnicodeScalar(30)!))
      .compactMap { record -> MacMailMessageDescriptor? in
        let fields = record.split(
          separator: Character(UnicodeScalar(31)!),
          omittingEmptySubsequences: false
        )
        guard fields.count >= 4, let identifier = Int(fields[0]) else { return nil }
        return MacMailMessageDescriptor(
          identifier: identifier,
          subject: String(fields[1]),
          sender: String(fields[2]),
          receivedAt: String(fields[3]),
          content: nil,
          truncated: false
        )
      }
  }

  public func readMailMessage(
    identifier: Int,
    maximumCharacters: Int
  ) throws -> MacMailMessageDescriptor {
    guard identifier > 0 else {
      throw MacNativeToolError.invalidArgument(tool: "mail_read_message", name: "message_id")
    }
    let boundedMaximum = max(500, min(maximumCharacters, 12_000))
    let script = """
      on cleanText(rawValue)
        set sourceText to rawValue as text
        set AppleScript's text item delimiters to {ASCII character 30, ASCII character 31}
        set sourceParts to text items of sourceText
        set AppleScript's text item delimiters to " "
        set cleanedText to sourceParts as text
        set AppleScript's text item delimiters to ""
        return cleanedText
      end cleanText

      tell application id "com.apple.mail"
        set matchingMessages to every message of inbox whose id is \(identifier)
        if (count of matchingMessages) is 0 then return ""

        set currentMessage to item 1 of matchingMessages
        set messageSubject to my cleanText(subject of currentMessage)
        set messageSender to my cleanText(sender of currentMessage)
        set messageReceived to my cleanText(date received of currentMessage as text)
        set messageContent to content of currentMessage as text
        set wasTruncated to false
        if (length of messageContent) > \(boundedMaximum) then
          set messageContent to text 1 thru \(boundedMaximum) of messageContent
          set wasTruncated to true
        end if
        set messageContent to my cleanText(messageContent)
        set fieldSeparator to ASCII character 31
        return (id of currentMessage as integer) & fieldSeparator & messageSubject & fieldSeparator & messageSender & fieldSeparator & messageReceived & fieldSeparator & wasTruncated & fieldSeparator & messageContent
      end tell
      """

    let raw = try executeAppleScript(script)
    guard !raw.isEmpty else {
      throw MacNativeToolError.mailMessageNotFound(identifier)
    }
    let fields = raw.split(
      separator: Character(UnicodeScalar(31)!),
      omittingEmptySubsequences: false
    )
    guard fields.count >= 6, let parsedIdentifier = Int(fields[0]) else {
      throw MacNativeToolError.mailAutomationFailed("Ungültige Antwort von Apple Mail.")
    }

    return MacMailMessageDescriptor(
      identifier: parsedIdentifier,
      subject: String(fields[1]),
      sender: String(fields[2]),
      receivedAt: String(fields[3]),
      content: String(fields[5]),
      truncated: String(fields[4]).caseInsensitiveCompare("true") == .orderedSame
    )
  }

  private func ensureCalendarReadAccess() async throws {
    switch EKEventStore.authorizationStatus(for: .event) {
    case .fullAccess:
      return
    case .notDetermined:
      let granted = try await eventStore.requestFullAccessToEvents()
      guard granted else { throw MacNativeToolError.calendarAccessDenied }
    case .writeOnly:
      throw MacNativeToolError.calendarFullAccessRequired
    case .denied, .restricted:
      throw MacNativeToolError.calendarAccessDenied
    @unknown default:
      throw MacNativeToolError.calendarAccessDenied
    }
  }

  private func ensureContactsAccess() async throws {
    switch CNContactStore.authorizationStatus(for: .contacts) {
    case .authorized, .limited:
      return
    case .notDetermined:
      let granted = try await contactStore.requestAccess(for: .contacts)
      guard granted else { throw MacNativeToolError.contactsAccessDenied }
    case .denied, .restricted:
      throw MacNativeToolError.contactsAccessDenied
    @unknown default:
      throw MacNativeToolError.contactsAccessDenied
    }
  }

  private func executeAppleScript(_ source: String) throws -> String {
    guard let script = NSAppleScript(source: source) else {
      throw MacNativeToolError.mailAutomationFailed("AppleScript konnte nicht kompiliert werden.")
    }
    var errorInfo: NSDictionary?
    let result = script.executeAndReturnError(&errorInfo)
    if let errorInfo {
      let message = errorInfo[NSAppleScript.errorMessage] as? String
        ?? errorInfo.description
      throw MacNativeToolError.mailAutomationFailed(message)
    }
    return result.stringValue ?? ""
  }

  private func normalizedOptional(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }
}

public enum MacNativeAgentTools {
  public static let definitions: [ProviderToolDefinition] = [
    ProviderToolDefinition(
      name: "calendar_list_events",
      description: "Read upcoming events from the user's macOS Calendar through EventKit. Use for questions about today's or upcoming schedule. Requires macOS Calendar permission.",
      parameters: objectSchema(
        required: ["days", "limit"],
        properties: [
          "days": integerSchema(
            description: "Number of days to inspect from now, from 1 to 30.",
            minimum: 1,
            maximum: 30
          ),
          "limit": integerSchema(
            description: "Maximum number of events to return, from 1 to 100.",
            minimum: 1,
            maximum: 100
          ),
        ]
      )
    ),
    ProviderToolDefinition(
      name: "contacts_search",
      description: "Search the user's macOS Contacts by name and return bounded contact details. Requires macOS Contacts permission.",
      parameters: objectSchema(
        required: ["query", "limit"],
        properties: [
          "query": stringSchema("Contact name or organization to search for."),
          "limit": integerSchema(
            description: "Maximum number of contacts to return, from 1 to 100.",
            minimum: 1,
            maximum: 100
          ),
        ]
      )
    ),
    ProviderToolDefinition(
      name: "mail_list_recent",
      description: "List recent messages from the Apple Mail inbox with message ID, subject, sender and received date. Uses macOS Apple Events automation and never returns credentials.",
      parameters: objectSchema(
        required: ["limit"],
        properties: [
          "limit": integerSchema(
            description: "Maximum number of inbox messages to return, from 1 to 25.",
            minimum: 1,
            maximum: 25
          )
        ]
      )
    ),
    ProviderToolDefinition(
      name: "mail_read_message",
      description: "Read one Apple Mail inbox message by the numeric message ID returned by mail_list_recent. The message body is bounded and credentials are never exposed.",
      parameters: objectSchema(
        required: ["message_id", "maximum_characters"],
        properties: [
          "message_id": integerSchema(
            description: "Numeric Apple Mail message ID returned by mail_list_recent.",
            minimum: 1,
            maximum: Int(Int32.max)
          ),
          "maximum_characters": integerSchema(
            description: "Maximum message-body characters to return, from 500 to 12000.",
            minimum: 500,
            maximum: 12_000
          ),
        ]
      )
    ),
  ]

  public static func handles(_ call: ProviderToolCall) -> Bool {
    definitions.contains { $0.function.name == call.function.name }
  }

  public static func risk(for _: ProviderToolCall) -> ToolRisk {
    .read
  }

  public static func summary(for call: ProviderToolCall) -> String {
    let values = call.function.arguments.keys.sorted().compactMap { key -> String? in
      guard let value = call.function.arguments[key] else { return nil }
      let rendered = value.compactDescription
      return "\(key): \(rendered.count > 180 ? String(rendered.prefix(180)) + "…" : rendered)"
    }
    return values.isEmpty
      ? call.function.name
      : "\(call.function.name) — \(values.joined(separator: ", "))"
  }

  public static func execute(
    call: ProviderToolCall,
    service: MacNativeToolService = .shared
  ) async -> ToolExecutionResult {
    do {
      switch call.function.name {
      case "calendar_list_events":
        let days = try requiredInt("days", in: call, range: 1...30)
        let limit = try requiredInt("limit", in: call, range: 1...100)
        return encoded(try await service.calendarEvents(days: days, limit: limit))
      case "contacts_search":
        let query = try requiredString("query", in: call)
        let limit = try requiredInt("limit", in: call, range: 1...100)
        return encoded(try await service.searchContacts(query: query, limit: limit))
      case "mail_list_recent":
        let limit = try requiredInt("limit", in: call, range: 1...25)
        return encoded(try await service.recentMail(limit: limit))
      case "mail_read_message":
        let identifier = try requiredInt("message_id", in: call, range: 1...Int(Int32.max))
        let maximum = try requiredInt("maximum_characters", in: call, range: 500...12_000)
        return encoded(
          try await service.readMailMessage(
            identifier: identifier,
            maximumCharacters: maximum
          )
        )
      default:
        return ToolExecutionResult(
          success: false,
          output: "Unsupported macOS native tool: \(call.function.name)"
        )
      }
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }

  private static func requiredString(
    _ name: String,
    in call: ProviderToolCall
  ) throws -> String {
    guard let value = call.function.arguments[name]?.stringValue else {
      throw AgentRuntimeError.missingArgument(tool: call.function.name, name: name)
    }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      throw MacNativeToolError.invalidArgument(tool: call.function.name, name: name)
    }
    return normalized
  }

  private static func requiredInt(
    _ name: String,
    in call: ProviderToolCall,
    range: ClosedRange<Int>
  ) throws -> Int {
    guard
      let value = call.function.arguments[name],
      case .number(let number) = value,
      number.isFinite,
      number.rounded(.towardZero) == number
    else {
      throw AgentRuntimeError.missingArgument(tool: call.function.name, name: name)
    }
    let integer = Int(number)
    guard range.contains(integer) else {
      throw MacNativeToolError.invalidArgument(tool: call.function.name, name: name)
    }
    return integer
  }

  private static func encoded<T: Encodable>(_ value: T) -> ToolExecutionResult {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(value)
      return ToolExecutionResult(
        success: true,
        output: String(decoding: data, as: UTF8.self)
      )
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
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
