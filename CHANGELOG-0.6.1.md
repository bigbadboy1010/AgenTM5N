# AgenTM5N 0.6.1 Build 17

## Attachment Inspector

- Jeder Anhangschip im Chat-Composer besitzt eine Info-Schaltfläche.
- Der Inspector zeigt Dateiname, Medientyp, Größe, Extraktionsmethode, Abschnittsanzahl, Seiten, Tabellenblätter, Folien, OCR-Nutzung, Cache-Treffer und Kürzungsstatus.
- Strukturierte Dokumentabschnitte werden mit ihrem Quellen-Locator und einer lokalen Textvorschau angezeigt.
- Bildanhänge zeigen eine lokale Vorschau sowie vorhandenen OCR-Text.

## Agent-Werkzeuge

- `attachment_list` listet Anhänge der aktuellen Unterhaltung mit stabilen IDs und begrenzten Metadaten.
- `attachment_describe` beschreibt einen Anhang und liefert verfügbare Quellen-Locators.
- `attachment_search` durchsucht extrahierten Dokument- und OCR-Text.
- `attachment_read_section` liest einen begrenzten Abschnitt über seinen Quellen-Locator.
- Alle vier Werkzeuge sind als reine Leseoperationen klassifiziert.

## Sicherheit

- Werkzeuge arbeiten ausschließlich auf Anhängen der aktuellen Unterhaltung.
- Keine Ausgabe von Original-Binärdaten oder Base64-Bildern.
- Keine Ausgabe interner Cache- oder Dateipfade.
- Keine Ausgabe von SHA-256-Cache-Schlüsseln.
- Maximal 20 Suchtreffer und 12.000 Zeichen pro Abschnittslesung.
- Dokumentinhalte bleiben nicht vertrauenswürdige Benutzerdaten.

## Version

- App-Version: 0.6.1
- Build: 17
