import Foundation

public struct SystemLanguage: Equatable, Sendable {
  public let identifier: String
  public let code: String
  public let displayName: String

  public static var current: SystemLanguage {
    let identifier = Locale.preferredLanguages.first
      ?? Locale.autoupdatingCurrent.identifier
    let locale = Locale(identifier: identifier)
    let code = locale.language.languageCode?.identifier.lowercased()
      ?? identifier.split(separator: "-").first.map(String.init)?.lowercased()
      ?? "en"
    let displayName = Locale.autoupdatingCurrent.localizedString(
      forLanguageCode: code
    ) ?? code

    return SystemLanguage(
      identifier: identifier,
      code: code,
      displayName: displayName
    )
  }

  public var agentInstruction: String {
    switch code {
    case "de":
      return """
        Antworte dem Benutzer ausschließlich auf Deutsch. Übersetze technische Erläuterungen, Statusmeldungen und Zusammenfassungen ins Deutsche. Werkzeugnamen, Befehle, Dateipfade, API-Bezeichner und unveränderte Programm-Ausgaben dürfen in ihrer technischen Originalform bleiben. Wechsle nicht eigenständig ins Englische.
        """
    case "fr":
      return """
        Réponds exclusivement en français. Traduis en français les explications techniques, les messages d’état et les résumés. Les noms d’outils, commandes, chemins de fichiers, identifiants d’API et sorties de programmes inchangées peuvent rester dans leur forme technique d’origine. Ne passe pas spontanément à l’anglais.
        """
    case "es":
      return """
        Responde exclusivamente en español. Traduce al español las explicaciones técnicas, los mensajes de estado y los resúmenes. Los nombres de herramientas, comandos, rutas, identificadores de API y salidas de programas sin modificar pueden conservar su forma técnica original. No cambies al inglés por iniciativa propia.
        """
    case "it":
      return """
        Rispondi esclusivamente in italiano. Traduci in italiano spiegazioni tecniche, messaggi di stato e riepiloghi. Nomi degli strumenti, comandi, percorsi, identificatori API e output dei programmi non modificati possono restare nella forma tecnica originale. Non passare autonomamente all’inglese.
        """
    case "pt":
      return """
        Responda exclusivamente em português. Traduza explicações técnicas, mensagens de estado e resumos para português. Nomes de ferramentas, comandos, caminhos, identificadores de API e saídas de programas inalteradas podem permanecer na forma técnica original. Não mude espontaneamente para inglês.
        """
    default:
      return """
        Respond exclusively in \(displayName). Translate technical explanations, status messages, and summaries into \(displayName). Tool names, commands, file paths, API identifiers, and unchanged program output may remain in their original technical form. Do not switch languages unless the user explicitly asks.
        """
    }
  }

  public func text(
    german: String,
    english: String,
    french: String? = nil
  ) -> String {
    switch code {
    case "de":
      return german
    case "fr":
      return french ?? english
    default:
      return english
    }
  }
}

public enum L10n {
  public static var language: SystemLanguage {
    .current
  }

  public static func text(
    de german: String,
    en english: String,
    fr french: String? = nil
  ) -> String {
    language.text(german: german, english: english, french: french)
  }
}
