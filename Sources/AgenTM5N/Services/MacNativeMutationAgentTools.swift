import AppKit
import Contacts
import EventKit
import Foundation

public enum MacNativeMutationToolError: LocalizedError {
  case invalidArgument(tool: String, name: String)
  case eventNotFound(String)
  case calendarNotFound(String)
  case calendarAmbiguous(String)
  case noWritableCalendar
  case contactNotFound(String)
  case contactWriteAccessDenied
  case recipientMissing
  case invalidRecipient(String)
  case mailAutomationFailed(String)

  public var errorDescription: String? {
    switch self {
    case .invalidArgument(let tool, let name):
      return L10n.text(
        de: "Werkzeug \(tool) erhielt ein ungültiges Argument: \(name).",
        en: "Tool \(tool) received an invalid argument: \(name).",
        fr: "L’outil \(tool) a reçu un argument invalide : \(name)."
      )
    case .eventNotFound(let identifier):
      return L10n.text(
        de: "Kalenderereignis nicht gefunden: \(identifier)",
        en: "Calendar event not found: \(identifier)",
        fr: "Événement de calendrier introuvable : \(identifier)"
      )
    case .calendarNotFound(let title):
      return L10n.text(
        de: "Kein schreibbarer Kalender mit dem Titel \(title) gefunden.",
        en: "No writable calendar named \(title) was found.",
        fr: "Aucun calendrier modifiable nommé \(title) n’a été trouvé."
      )
    case .calendarAmbiguous(let title):
      return L10n.text(
        de: "Mehrere schreibbare Kalender heißen \(title). Bitte verwende einen eindeutigen Titel.",
        en: "Multiple writable calendars are named \(title). Use an unambiguous title.",
        fr: "Plusieurs calendriers modifiables portent le nom \(title). Utilisez un titre non ambigu."
      )
    case .noWritableCalendar:
      return L10n.text(
        de: "Es ist kein schreibbarer Standardkalender verfügbar.",
        en: "No writable default calendar is available.",
        fr: "Aucun calendrier par défaut modifiable n’est disponible."
      )
    case .contactNotFound(let identifier):
      return L10n.text(
        de: "Kontakt nicht gefunden: \(identifier)",
        en: "Contact not found: \(identifier)",
        fr: "Contact introuvable : \(identifier)"
      )
    case .contactWriteAccessDenied:
      return L10n.text(
        de: "AgenTM5N hat keinen Schreibzugriff auf Kontakte.",
        en: "AgenTM5N does not have write access to Contacts.",
        fr: "AgenTM5N ne dispose pas d’un accès en écriture aux contacts."
      )
    case .recipientMissing:
      return L10n.text(
        de: "Mindestens ein E-Mail-Empfänger ist erforderlich.",
        en: "At least one email recipient is required.",
        fr: "Au moins un destinataire e-mail est requis."
      )
    case .invalidRecipient(let recipient):
      return L10n.text(
        de: "Ungültige E-Mail-Adresse: \(recipient)",
        en: "Invalid email address: \(recipient)",
        fr: "Adresse e-mail invalide : \(recipient)"
      )
    case .mailAutomationFailed(let reason):
      return L10n.text(
        de: "Apple-Mail-Automation fehlgeschlagen: \(reason)",
        en: "Apple Mail automation failed: \(reason)",
        fr: "L’automatisation d’Apple Mail a échoué : \(reason)"
      )
    }
  }
}

public struct MacCalendarMutationDescriptor: Codable, Equatable, Sendable {
  public let action: String
  public let identifier: String
  public let title: String
  public let startDate: Date
  public let endDate: Date
  public let calendarTitle: String

  public init(
    action: String,
    identifier: String,
    title: String,
    startDate: Date,
    endDate: Date,
    calendarTitle: String
  ) {
    self.action = action
    self.identifier = identifier
    self.title = title
    self.startDate = startDate
    self.endDate = endDate
    self.calendarTitle = calendarTitle
  }
}

public struct MacContactMutationDescriptor: Codable, Equatable, Sendable {
  public let action: String
  public let identifier: String
  public let displayName: String

  public init(action: String, identifier: String, displayName: String) {
    self.action = action
    self.identifier = identifier
    self.displayName = displayName
  }
}

public struct MacMailMutationDescriptor: Codable, Equatable, Sendable {
  public let action: String
  public let messageIdentifier: String?
  public let sent: Bool
  public let subject: String
  public let recipients: [String]

  public init(
    action: String,
    messageIdentifier: String?,
    sent: Bool,
    subject: String,
    recipients: [String]
  ) {
    self.action = action
    self.messageIdentifier = messageIdentifier
    self.sent = sent
    self.subject = subject
    self.recipients = recipients
  }
}

public actor MacNativeMutationService {
  public static let shared = MacNativeMutationService()

  private let eventStore: EKEventStore
  private let contactStore: CNContactStore

  public init(
    eventStore: EKEventStore = EKEventStore(),
    contactStore: CNContactStore = CNContactStore()
  ) {
    self.eventStore = eventStore
    self.contactStore = contactStore
  }

  public func createCalendarEvent(
    title: String,
    startDate: Date,
    endDate: Date,
    calendarTitle: String?,
    location: String?,
    notes: String?,
    isAllDay: Bool
  ) async throws -> MacCalendarMutationDescriptor {
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw MacNativeMutationToolError.invalidArgument(
        tool: "calendar_create_event",
        name: "title"
      )
    }
    guard endDate > startDate else {
      throw MacNativeMutationToolError.invalidArgument(
        tool: "calendar_create_event",
        name: "end"
      )
    }

    try await ensureCalendarWriteAccess()
    let calendar = try resolveWritableCalendar(title: calendarTitle)
    let event = EKEvent(eventStore: eventStore)
    event.title = title
    event.startDate = startDate
    event.endDate = endDate
    event.calendar = calendar
    event.location = normalizedOptional(location)
    event.notes = normalizedOptional(notes)
    event.isAllDay = isAllDay
    try eventStore.save(event, span: .thisEvent, commit: true)

    return MacCalendarMutationDescriptor(
      action: "created",
      identifier: event.eventIdentifier ?? "",
      title: event.title ?? title,
      startDate: event.startDate,
      endDate: event.endDate,
      calendarTitle: event.calendar.title
    )
  }

  public func updateCalendarEvent(
    identifier: String,
    title: String?,
    startDate: Date?,
    endDate: Date?,
    calendarTitle: String?,
    location: String?,
    notes: String?,
    allDay: Bool?
  ) async throws -> MacCalendarMutationDescriptor {
    try await ensureCalendarWriteAccess()
    guard let event = eventStore.event(withIdentifier: identifier) else {
      throw MacNativeMutationToolError.eventNotFound(identifier)
    }

    if let title = normalizedOptional(title) {
      event.title = title
    }
    if let startDate {
      event.startDate = startDate
    }
    if let endDate {
      event.endDate = endDate
    }
    if event.endDate <= event.startDate {
      throw MacNativeMutationToolError.invalidArgument(
        tool: "calendar_update_event",
        name: "start/end"
      )
    }
    if let calendarTitle = normalizedOptional(calendarTitle) {
      event.calendar = try resolveWritableCalendar(title: calendarTitle)
    }
    if let location = normalizedOptional(location) {
      event.location = location
    }
    if let notes = normalizedOptional(notes) {
      event.notes = notes
    }
    if let allDay {
      event.isAllDay = allDay
    }

    try eventStore.save(event, span: .thisEvent, commit: true)
    return MacCalendarMutationDescriptor(
      action: "updated",
      identifier: event.eventIdentifier ?? identifier,
      title: event.title ?? "",
      startDate: event.startDate,
      endDate: event.endDate,
      calendarTitle: event.calendar.title
    )
  }

  public func deleteCalendarEvent(
    identifier: String
  ) async throws -> MacCalendarMutationDescriptor {
    try await ensureCalendarWriteAccess()
    guard let event = eventStore.event(withIdentifier: identifier) else {
      throw MacNativeMutationToolError.eventNotFound(identifier)
    }
    let descriptor = MacCalendarMutationDescriptor(
      action: "deleted",
      identifier: identifier,
      title: event.title ?? "",
      startDate: event.startDate,
      endDate: event.endDate,
      calendarTitle: event.calendar.title
    )
    try eventStore.remove(event, span: .thisEvent, commit: true)
    return descriptor
  }

  public func createContact(
    givenName: String,
    familyName: String?,
    organizationName: String?,
    email: String?,
    phone: String?
  ) async throws -> MacContactMutationDescriptor {
    let normalizedGivenName = givenName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedGivenName.isEmpty else {
      throw MacNativeMutationToolError.invalidArgument(
        tool: "contacts_create",
        name: "given_name"
      )
    }
    try await ensureContactsWriteAccess()

    let contact = CNMutableContact()
    contact.givenName = normalizedGivenName
    contact.familyName = normalizedOptional(familyName) ?? ""
    contact.organizationName = normalizedOptional(organizationName) ?? ""
    if let email = normalizedOptional(email) {
      contact.emailAddresses = [
        CNLabeledValue(label: CNLabelWork, value: email as NSString)
      ]
    }
    if let phone = normalizedOptional(phone) {
      contact.phoneNumbers = [
        CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))
      ]
    }

    let request = CNSaveRequest()
    request.add(contact, toContainerWithIdentifier: nil)
    try contactStore.execute(request)

    return MacContactMutationDescriptor(
      action: "created",
      identifier: contact.identifier,
      displayName: displayName(for: contact)
    )
  }

  public func updateContact(
    identifier: String,
    givenName: String?,
    familyName: String?,
    organizationName: String?,
    email: String?,
    phone: String?
  ) async throws -> MacContactMutationDescriptor {
    try await ensureContactsWriteAccess()
    let keys: [any CNKeyDescriptor] = [
      CNContactIdentifierKey as CNKeyDescriptor,
      CNContactGivenNameKey as CNKeyDescriptor,
      CNContactFamilyNameKey as CNKeyDescriptor,
      CNContactOrganizationNameKey as CNKeyDescriptor,
      CNContactEmailAddressesKey as CNKeyDescriptor,
      CNContactPhoneNumbersKey as CNKeyDescriptor,
    ]

    let source: CNContact
    do {
      source = try contactStore.unifiedContact(
        withIdentifier: identifier,
        keysToFetch: keys
      )
    } catch {
      throw MacNativeMutationToolError.contactNotFound(identifier)
    }
    guard let mutable = source.mutableCopy() as? CNMutableContact else {
      throw MacNativeMutationToolError.contactNotFound(identifier)
    }

    if let givenName = normalizedOptional(givenName) {
      mutable.givenName = givenName
    }
    if let familyName = normalizedOptional(familyName) {
      mutable.familyName = familyName
    }
    if let organizationName = normalizedOptional(organizationName) {
      mutable.organizationName = organizationName
    }
    if let email = normalizedOptional(email) {
      mutable.emailAddresses = [
        CNLabeledValue(label: CNLabelWork, value: email as NSString)
      ]
    }
    if let phone = normalizedOptional(phone) {
      mutable.phoneNumbers = [
        CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))
      ]
    }

    let request = CNSaveRequest()
    request.update(mutable)
    try contactStore.execute(request)
    return MacContactMutationDescriptor(
      action: "updated",
      identifier: mutable.identifier,
      displayName: displayName(for: mutable)
    )
  }

  public func createMailDraft(
    to: String,
    cc: String?,
    bcc: String?,
    subject: String,
    body: String
  ) throws -> MacMailMutationDescriptor {
    let recipients = try parseRecipients(to)
    let ccRecipients = try parseOptionalRecipients(cc)
    let bccRecipients = try parseOptionalRecipients(bcc)
    let script = makeOutgoingMessageScript(
      to: recipients,
      cc: ccRecipients,
      bcc: bccRecipients,
      subject: subject,
      body: body,
      sendNow: false
    )
    let identifier = try executeAppleScript(script)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    return MacMailMutationDescriptor(
      action: "draft_created",
      messageIdentifier: identifier.isEmpty ? nil : identifier,
      sent: false,
      subject: subject,
      recipients: recipients + ccRecipients + bccRecipients
    )
  }

  public func sendMail(
    to: String,
    cc: String?,
    bcc: String?,
    subject: String,
    body: String
  ) throws -> MacMailMutationDescriptor {
    let recipients = try parseRecipients(to)
    let ccRecipients = try parseOptionalRecipients(cc)
    let bccRecipients = try parseOptionalRecipients(bcc)
    let script = makeOutgoingMessageScript(
      to: recipients,
      cc: ccRecipients,
      bcc: bccRecipients,
      subject: subject,
      body: body,
      sendNow: true
    )
    let identifier = try executeAppleScript(script)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    return MacMailMutationDescriptor(
      action: "sent",
      messageIdentifier: identifier.isEmpty ? nil : identifier,
      sent: true,
      subject: subject,
      recipients: recipients + ccRecipients + bccRecipients
    )
  }

  public func replyToMail(
    identifier: Int,
    body: String,
    sendNow: Bool
  ) throws -> MacMailMutationDescriptor {
    guard identifier > 0 else {
      throw MacNativeMutationToolError.invalidArgument(
        tool: "mail_reply",
        name: "message_id"
      )
    }
    let bodyLiteral = appleScriptString(body)
    let script = """
      tell application id "com.apple.mail"
        set matchingMessages to every message of inbox whose id is \(identifier)
        if (count of matchingMessages) is 0 then error "Message not found"
        set sourceMessage to item 1 of matchingMessages
        set replyMessage to reply sourceMessage opening window false
        set content of replyMessage to \(bodyLiteral) & return & return & content of replyMessage
        set sourceSubject to subject of sourceMessage as text
        set sourceSender to sender of sourceMessage as text
        if \(sendNow ? "true" : "false") then
          send replyMessage
        else
          save replyMessage
        end if
        return (id of replyMessage as text) & (ASCII character 31) & sourceSubject & (ASCII character 31) & sourceSender
      end tell
      """
    let raw = try executeAppleScript(script)
    let fields = raw.split(
      separator: Character(UnicodeScalar(31)!),
      omittingEmptySubsequences: false
    )
    let replyIdentifier = fields.isEmpty ? nil : String(fields[0])
    let sourceSubject = fields.count > 1 ? String(fields[1]) : ""
    let sourceSender = fields.count > 2 ? String(fields[2]) : ""
    return MacMailMutationDescriptor(
      action: sendNow ? "reply_sent" : "reply_draft_created",
      messageIdentifier: replyIdentifier,
      sent: sendNow,
      subject: sourceSubject,
      recipients: sourceSender.isEmpty ? [] : [sourceSender]
    )
  }

  private func ensureCalendarWriteAccess() async throws {
    switch EKEventStore.authorizationStatus(for: .event) {
    case .fullAccess:
      return
    case .writeOnly:
      return
    case .notDetermined:
      let granted = try await eventStore.requestFullAccessToEvents()
      guard granted else { throw MacNativeToolError.calendarAccessDenied }
    case .denied, .restricted:
      throw MacNativeToolError.calendarAccessDenied
    @unknown default:
      throw MacNativeToolError.calendarAccessDenied
    }
  }

  private func resolveWritableCalendar(title: String?) throws -> EKCalendar {
    if let title = normalizedOptional(title) {
      let matches = eventStore.calendars(for: .event).filter {
        $0.allowsContentModifications
          && $0.title.caseInsensitiveCompare(title) == .orderedSame
      }
      guard !matches.isEmpty else {
        throw MacNativeMutationToolError.calendarNotFound(title)
      }
      guard matches.count == 1, let match = matches.first else {
        throw MacNativeMutationToolError.calendarAmbiguous(title)
      }
      return match
    }

    guard
      let calendar = eventStore.defaultCalendarForNewEvents,
      calendar.allowsContentModifications
    else {
      throw MacNativeMutationToolError.noWritableCalendar
    }
    return calendar
  }

  private func ensureContactsWriteAccess() async throws {
    switch CNContactStore.authorizationStatus(for: .contacts) {
    case .authorized:
      return
    case .notDetermined:
      let granted = try await contactStore.requestAccess(for: .contacts)
      guard granted else { throw MacNativeMutationToolError.contactWriteAccessDenied }
    case .limited, .denied, .restricted:
      throw MacNativeMutationToolError.contactWriteAccessDenied
    @unknown default:
      throw MacNativeMutationToolError.contactWriteAccessDenied
    }
  }

  private func displayName(for contact: CNContact) -> String {
    let name = [contact.givenName, contact.familyName]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    if !name.isEmpty {
      return name
    }
    if !contact.organizationName.isEmpty {
      return contact.organizationName
    }
    return contact.identifier
  }

  private func makeOutgoingMessageScript(
    to: [String],
    cc: [String],
    bcc: [String],
    subject: String,
    body: String,
    sendNow: Bool
  ) -> String {
    let toLines = recipientAppleScriptLines(to, recipientType: "to recipient", collection: "to recipients")
    let ccLines = recipientAppleScriptLines(cc, recipientType: "cc recipient", collection: "cc recipients")
    let bccLines = recipientAppleScriptLines(bcc, recipientType: "bcc recipient", collection: "bcc recipients")
    return """
      tell application id "com.apple.mail"
        set outgoingMessage to make new outgoing message with properties {subject:\(appleScriptString(subject)), content:\(appleScriptString(body)), visible:false}
        tell outgoingMessage
      \(toLines)
      \(ccLines)
      \(bccLines)
        end tell
        if \(sendNow ? "true" : "false") then
          send outgoingMessage
        else
          save outgoingMessage
        end if
        return id of outgoingMessage as text
      end tell
      """
  }

  private func recipientAppleScriptLines(
    _ recipients: [String],
    recipientType: String,
    collection: String
  ) -> String {
    recipients.map { recipient in
      "      make new \(recipientType) at end of \(collection) with properties {address:\(appleScriptString(recipient))}"
    }.joined(separator: "\n")
  }

  private func parseRecipients(_ value: String) throws -> [String] {
    let recipients = try parseOptionalRecipients(value)
    guard !recipients.isEmpty else {
      throw MacNativeMutationToolError.recipientMissing
    }
    return recipients
  }

  private func parseOptionalRecipients(_ value: String?) throws -> [String] {
    guard let value = normalizedOptional(value) else { return [] }
    let recipients = value
      .split(whereSeparator: { $0 == "," || $0 == ";" })
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    for recipient in recipients {
      guard
        recipient.contains("@"),
        !recipient.contains("\n"),
        !recipient.contains("\r")
      else {
        throw MacNativeMutationToolError.invalidRecipient(recipient)
      }
    }
    return Array(Set(recipients)).sorted()
  }

  private func appleScriptString(_ value: String) -> String {
    var escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
    escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
    escaped = escaped.replacingOccurrences(of: "\r\n", with: "\\n")
    escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
    escaped = escaped.replacingOccurrences(of: "\r", with: "\\n")
    return "\"\(escaped)\""
  }

  private func executeAppleScript(_ source: String) throws -> String {
    guard let script = NSAppleScript(source: source) else {
      throw MacNativeMutationToolError.mailAutomationFailed(
        "AppleScript konnte nicht kompiliert werden."
      )
    }
    var errorInfo: NSDictionary?
    let result = script.executeAndReturnError(&errorInfo)
    if let errorInfo {
      let message = errorInfo[NSAppleScript.errorMessage] as? String
        ?? errorInfo.description
      throw MacNativeMutationToolError.mailAutomationFailed(message)
    }
    return result.stringValue ?? ""
  }

  private func normalizedOptional(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }
}

@MainActor
public enum MacNativeMutationConfirmation {
  public static func confirm(
    action: String,
    details: String
  ) -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = L10n.text(
      de: "AgenTM5N-Aktion bestätigen",
      en: "Confirm AgenTM5N action",
      fr: "Confirmer l’action AgenTM5N"
    )
    alert.informativeText = "\(action)\n\n\(details)"
    alert.addButton(withTitle: L10n.text(de: "Ausführen", en: "Execute", fr: "Exécuter"))
    alert.addButton(withTitle: L10n.text(de: "Abbrechen", en: "Cancel", fr: "Annuler"))
    return alert.runModal() == .alertFirstButtonReturn
  }
}

public enum MacNativeMutationAgentTools {
  public static let definitions: [ProviderToolDefinition] = [
    ProviderToolDefinition(
      name: "calendar_create_event",
      description: "Create a macOS Calendar event. This changes personal calendar data and requires confirmation according to the active agent permission policy.",
      parameters: objectSchema(
        required: ["title", "start", "end"],
        properties: [
          "title": stringSchema("Event title."),
          "start": stringSchema("ISO-8601 start date and time, for example 2026-08-08T14:00:00+02:00."),
          "end": stringSchema("ISO-8601 end date and time."),
          "calendar": stringSchema("Optional exact writable calendar title. Empty uses the default calendar."),
          "location": stringSchema("Optional location."),
          "notes": stringSchema("Optional notes."),
          "is_all_day": boolSchema("Whether the event is all-day. Defaults to false."),
        ]
      )
    ),
    ProviderToolDefinition(
      name: "calendar_update_event",
      description: "Update an existing macOS Calendar event by event_id from calendar_list_events. Empty optional strings leave existing values unchanged.",
      parameters: objectSchema(
        required: ["event_id"],
        properties: [
          "event_id": stringSchema("Exact event identifier returned by calendar_list_events."),
          "title": stringSchema("Optional new title."),
          "start": stringSchema("Optional new ISO-8601 start date and time."),
          "end": stringSchema("Optional new ISO-8601 end date and time."),
          "calendar": stringSchema("Optional new exact writable calendar title."),
          "location": stringSchema("Optional new location."),
          "notes": stringSchema("Optional new notes."),
          "is_all_day": boolSchema("Optional all-day value. Omit to preserve the current value."),
        ]
      )
    ),
    ProviderToolDefinition(
      name: "calendar_delete_event",
      description: "Delete one macOS Calendar event by event_id returned by calendar_list_events.",
      parameters: objectSchema(
        required: ["event_id"],
        properties: [
          "event_id": stringSchema("Exact event identifier returned by calendar_list_events.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "contacts_create",
      description: "Create a new macOS Contact. given_name is required; other fields are optional.",
      parameters: objectSchema(
        required: ["given_name"],
        properties: [
          "given_name": stringSchema("Given name."),
          "family_name": stringSchema("Optional family name."),
          "organization": stringSchema("Optional organization name."),
          "email": stringSchema("Optional email address."),
          "phone": stringSchema("Optional phone number."),
        ]
      )
    ),
    ProviderToolDefinition(
      name: "contacts_update",
      description: "Update an existing macOS Contact by contact_id returned by contacts_search. Empty optional strings leave existing values unchanged.",
      parameters: objectSchema(
        required: ["contact_id"],
        properties: [
          "contact_id": stringSchema("Exact contact identifier returned by contacts_search."),
          "given_name": stringSchema("Optional new given name."),
          "family_name": stringSchema("Optional new family name."),
          "organization": stringSchema("Optional new organization."),
          "email": stringSchema("Optional replacement email address."),
          "phone": stringSchema("Optional replacement phone number."),
        ]
      )
    ),
    ProviderToolDefinition(
      name: "mail_create_draft",
      description: "Create and save an Apple Mail draft. Recipient strings may contain comma- or semicolon-separated email addresses.",
      parameters: objectSchema(
        required: ["to", "subject", "body"],
        properties: [
          "to": stringSchema("One or more To email addresses."),
          "cc": stringSchema("Optional CC email addresses."),
          "bcc": stringSchema("Optional BCC email addresses."),
          "subject": stringSchema("Message subject."),
          "body": stringSchema("Complete plain-text message body."),
        ]
      )
    ),
    ProviderToolDefinition(
      name: "mail_send",
      description: "Create and immediately send a new Apple Mail message. This is a high-impact action and must only be used when the user explicitly asks to send the message.",
      parameters: objectSchema(
        required: ["to", "subject", "body"],
        properties: [
          "to": stringSchema("One or more To email addresses."),
          "cc": stringSchema("Optional CC email addresses."),
          "bcc": stringSchema("Optional BCC email addresses."),
          "subject": stringSchema("Message subject."),
          "body": stringSchema("Complete plain-text message body."),
        ]
      )
    ),
    ProviderToolDefinition(
      name: "mail_reply",
      description: "Create a reply to an Apple Mail inbox message by message_id. send_now=false saves a reply draft; send_now=true immediately sends the reply.",
      parameters: objectSchema(
        required: ["message_id", "body", "send_now"],
        properties: [
          "message_id": integerSchema(
            description: "Numeric Apple Mail message ID returned by mail_list_recent.",
            minimum: 1,
            maximum: Int(Int32.max)
          ),
          "body": stringSchema("Reply body to prepend before the quoted original message."),
          "send_now": boolSchema("true sends immediately; false saves a draft reply."),
        ]
      )
    ),
  ]

  public static func handles(_ call: ProviderToolCall) -> Bool {
    definitions.contains { $0.function.name == call.function.name }
  }

  public static func risk(for call: ProviderToolCall) -> ToolRisk {
    switch call.function.name {
    case "mail_send":
      return .execute
    case "mail_reply":
      return call.function.arguments["send_now"]?.boolValue == true ? .execute : .write
    default:
      return .write
    }
  }

  public static func summary(for call: ProviderToolCall) -> String {
    let values = call.function.arguments.keys.sorted().compactMap { key -> String? in
      guard let value = call.function.arguments[key] else { return nil }
      let rendered: String
      if key == "body" || key == "notes" {
        rendered = "<\(value.compactDescription.utf8.count) Bytes>"
      } else {
        rendered = value.compactDescription
      }
      return "\(key): \(rendered.count > 180 ? String(rendered.prefix(180)) + "…" : rendered)"
    }
    return values.isEmpty
      ? call.function.name
      : "\(call.function.name) — \(values.joined(separator: ", "))"
  }

  public static func execute(
    call: ProviderToolCall,
    service: MacNativeMutationService = .shared
  ) async -> ToolExecutionResult {
    do {
      switch call.function.name {
      case "calendar_create_event":
        return encoded(
          try await service.createCalendarEvent(
            title: try requiredString("title", in: call),
            startDate: try requiredDate("start", in: call),
            endDate: try requiredDate("end", in: call),
            calendarTitle: optionalString("calendar", in: call),
            location: optionalString("location", in: call),
            notes: optionalString("notes", in: call),
            isAllDay: call.function.arguments["is_all_day"]?.boolValue ?? false
          )
        )
      case "calendar_update_event":
        return encoded(
          try await service.updateCalendarEvent(
            identifier: try requiredString("event_id", in: call),
            title: optionalString("title", in: call),
            startDate: try optionalDate("start", in: call),
            endDate: try optionalDate("end", in: call),
            calendarTitle: optionalString("calendar", in: call),
            location: optionalString("location", in: call),
            notes: optionalString("notes", in: call),
            allDay: call.function.arguments["is_all_day"]?.boolValue
          )
        )
      case "calendar_delete_event":
        return encoded(
          try await service.deleteCalendarEvent(
            identifier: try requiredString("event_id", in: call)
          )
        )
      case "contacts_create":
        return encoded(
          try await service.createContact(
            givenName: try requiredString("given_name", in: call),
            familyName: optionalString("family_name", in: call),
            organizationName: optionalString("organization", in: call),
            email: optionalString("email", in: call),
            phone: optionalString("phone", in: call)
          )
        )
      case "contacts_update":
        return encoded(
          try await service.updateContact(
            identifier: try requiredString("contact_id", in: call),
            givenName: optionalString("given_name", in: call),
            familyName: optionalString("family_name", in: call),
            organizationName: optionalString("organization", in: call),
            email: optionalString("email", in: call),
            phone: optionalString("phone", in: call)
          )
        )
      case "mail_create_draft":
        return encoded(
          try await service.createMailDraft(
            to: try requiredString("to", in: call),
            cc: optionalString("cc", in: call),
            bcc: optionalString("bcc", in: call),
            subject: try requiredString("subject", in: call),
            body: try requiredString("body", in: call)
          )
        )
      case "mail_send":
        return encoded(
          try await service.sendMail(
            to: try requiredString("to", in: call),
            cc: optionalString("cc", in: call),
            bcc: optionalString("bcc", in: call),
            subject: try requiredString("subject", in: call),
            body: try requiredString("body", in: call)
          )
        )
      case "mail_reply":
        return encoded(
          try await service.replyToMail(
            identifier: try requiredInt(
              "message_id",
              in: call,
              range: 1...Int(Int32.max)
            ),
            body: try requiredString("body", in: call),
            sendNow: try requiredBool("send_now", in: call)
          )
        )
      default:
        return ToolExecutionResult(
          success: false,
          output: "Unsupported macOS mutation tool: \(call.function.name)"
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
    guard let value = optionalString(name, in: call) else {
      throw AgentRuntimeError.missingArgument(tool: call.function.name, name: name)
    }
    return value
  }

  private static func optionalString(
    _ name: String,
    in call: ProviderToolCall
  ) -> String? {
    guard let value = call.function.arguments[name]?.stringValue else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func requiredBool(
    _ name: String,
    in call: ProviderToolCall
  ) throws -> Bool {
    guard let value = call.function.arguments[name]?.boolValue else {
      throw AgentRuntimeError.missingArgument(tool: call.function.name, name: name)
    }
    return value
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
      throw MacNativeMutationToolError.invalidArgument(tool: call.function.name, name: name)
    }
    return integer
  }

  private static func requiredDate(
    _ name: String,
    in call: ProviderToolCall
  ) throws -> Date {
    guard let date = try optionalDate(name, in: call) else {
      throw AgentRuntimeError.missingArgument(tool: call.function.name, name: name)
    }
    return date
  }

  private static func optionalDate(
    _ name: String,
    in call: ProviderToolCall
  ) throws -> Date? {
    guard let value = optionalString(name, in: call) else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) {
      return date
    }
    let standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]
    if let date = standard.date(from: value) {
      return date
    }
    throw MacNativeMutationToolError.invalidArgument(tool: call.function.name, name: name)
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

  private static func boolSchema(_ description: String) -> JSONValue {
    .object([
      "type": .string("boolean"),
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
