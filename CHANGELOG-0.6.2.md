# AgenTM5N 0.6.2 Build 18

## Dokument-Agent-Werkzeuge

- `attachment_list` listet Dokumente und Bilder aus der aktuellen Unterhaltung mit stabilen Anhangs-IDs und begrenzten Metadaten.
- `attachment_describe` beschreibt einen Anhang und liefert die verfügbaren Quellen-Locators.
- `attachment_search` durchsucht lokal extrahierten Dokumenttext und OCR-Text.
- `attachment_read_section` liest einen begrenzten Dokumentabschnitt anhand seines Quellen-Locators.
- Alle vier Werkzeuge sind reine Leseoperationen und benötigen im Bestätigungsmodus keine Schreibfreigabe.

## Laufzeitintegration

- Die Werkzeugdefinitionen werden ausschließlich bei aktivierter Agent-Laufzeit an Ollama übergeben.
- Werkzeugaufrufe werden gegen den Nachrichtenverlauf der aktuellen Unterhaltung ausgeführt.
- Tool-Ergebnisse erscheinen in den vorhandenen Ausführungskarten des Chats.
- Die bestehende maximale Anzahl von Agent-Runden bleibt wirksam.

## Sicherheit

- Keine Ausgabe von Original-Binärdaten oder Base64-Bildern.
- Keine Ausgabe interner Cachepfade.
- Keine Ausgabe von SHA-256-Cache-Schlüsseln.
- Keine Suche außerhalb der Anhänge der aktuellen Unterhaltung.
- Maximal 20 Suchtreffer.
- Maximal 12.000 Zeichen pro Abschnittslesung.
- Dokumentinhalte bleiben nicht vertrauenswürdige Benutzerdaten und umgehen keine Werkzeugfreigaben.

## Version

- App-Version: 0.6.2
- Build: 18
