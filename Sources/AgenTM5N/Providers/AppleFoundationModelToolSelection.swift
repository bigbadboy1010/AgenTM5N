import Foundation

/// Deterministic, prompt-aware tool routing for the Apple on-device provider.
/// The selector never executes a tool and never expands the configured
/// capability scope. It only chooses the smallest relevant native tool pack.
public struct AppleFoundationModelToolSelection: Equatable, Sendable {
  public enum Focused: Equatable, Sendable {
    case document
    case clipboard
    case calendarCreate
  }

  public let focused: Focused?
  public let browser: Bool
  public let edge: Bool
  public let knowledgeMemory: Bool
  public let macNative: Bool
  public let persistentAgents: Bool

  public init(
    focused: Focused? = nil,
    browser: Bool = false,
    edge: Bool = false,
    knowledgeMemory: Bool = false,
    macNative: Bool = false,
    persistentAgents: Bool = false
  ) {
    self.focused = focused
    self.browser = browser
    self.edge = edge
    self.knowledgeMemory = knowledgeMemory
    self.macNative = macNative
    self.persistentAgents = persistentAgents
  }

  public static func make(
    messages: [ProviderMessage],
    operatingConfiguration: AgentOperatingLayerConfiguration
  ) -> AppleFoundationModelToolSelection {
    let text = messages.last(where: { $0.role == .user })?.content
      .lowercased() ?? ""
    let capabilities = operatingConfiguration.enabledCapabilities

    if capabilities.contains(.documents),
      containsAny(text, [
        "docx", "xlsx", "pptx", "powerpoint", "word-datei", "word datei",
        "excel-datei", "excel datei", "pdf erstellen", "pdf generieren",
        "dokument erstellen", "dokument generieren", "dokument erzeugen",
        "create document", "generate document", "create pdf",
      ])
    {
      return .init(focused: .document)
    }

    if capabilities.contains(.system),
      containsAny(text, ["zwischenablage", "clipboard"]),
      containsAny(text, ["lies", "lese", "lesen", "inhalt", "zeige", "read", "show", "inspect"])
    {
      return .init(focused: .clipboard)
    }

    if capabilities.contains(.macPersonal),
      containsAny(text, ["kalender", "calendar", "termin", "event"]),
      containsAny(text, ["erstell", "anleg", "hinzuf", "create", "add", "schedule"])
    {
      return .init(focused: .calendarCreate)
    }

    let browser = capabilities.contains(.http)
      && containsAny(text, [
        "browser", "microsoft edge", "edge browser", "webseite", "website",
        "browser_open", "browser_read", "browser_action", "browser_batch",
      ])

    let edge = capabilities.contains(.edge)
      && (text.hasPrefix("edge ") || containsAny(text, [
        "/data/edge", "edge host", "edge-host", "edge node", "edge-node",
        "edge server", "edge-server", "edge control",
      ]))

    let knowledgeMemory = !capabilities.intersection([
      .memory, .knowledge, .attachments, .documents, .coreML,
    ]).isEmpty
      && containsAny(text, [
        "workspace memory", "semantic search", "semantische suche", "embedding",
        "knowledge", "wissen", "wissensbibliothek", "kontextsuche", "context search",
        "anhang", "anhänge", "anhaenge", "attachment", "core ml", "coreml",
      ])

    let macNative = capabilities.contains(.macPersonal)
      && containsAny(text, [
        "kalender", "calendar", "termin", "event", "kontakt", "contact",
        "adressbuch", "address book", "mail", "email", "e-mail",
      ])

    let persistentAgents = capabilities.contains(.agents)
      && containsAny(text, [
        "agent erstellen", "agent anlegen", "agent speichern", "agent ändern",
        "agent aktualisieren", "agent löschen", "agent auflisten", "agenten",
        "gespeicherter agent", "specialist", "spezialist",
      ])

    return .init(
      browser: browser,
      edge: edge,
      knowledgeMemory: knowledgeMemory,
      macNative: macNative,
      persistentAgents: persistentAgents
    )
  }

  private static func containsAny(_ text: String, _ terms: [String]) -> Bool {
    terms.contains { text.contains($0) }
  }
}
