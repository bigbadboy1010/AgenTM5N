# AgenTM5N 0.6.1 Build 17

## Attachment Center

- Neuer Toolbar-Button `Anhangscenter` im Chat.
- Übersicht aller Dateien und Bilder des aktuellen Promptentwurfs.
- Lokale Bildvorschau sowie Dokumenttyp, Medientyp, Größe und Bildabmessungen.
- Anzeige von Extraktionsumfang, OCR-Nutzung, Cache-Treffer und Kürzungsstatus.
- Einzelne Anhänge können geprüft oder aus dem Promptentwurf entfernt werden.
- Anhänge bleiben beim Wechsel zwischen Chat und Attachment Center im gemeinsamen Entwurf erhalten.

## Attachment Inspector

- Der bestehende Inspector ist direkt aus dem Attachment Center erreichbar.
- Er zeigt Dateiname, Medientyp, Größe, Extraktionsmethode, Abschnittsanzahl, Seiten, Tabellenblätter, Folien, OCR-Nutzung, Cache-Treffer und Kürzungsstatus.
- Strukturierte Dokumentabschnitte werden mit Quellen-Locator und lokaler Textvorschau angezeigt.
- Bildanhänge zeigen eine lokale Vorschau sowie vorhandenen OCR-Text.

## Sicherheit

- Keine Ausgabe oder zusätzliche Kopie von Original-Binärdaten.
- Keine Anzeige interner Cachepfade oder SHA-256-Schlüssel.
- Der Inspector verarbeitet ausschließlich bereits lokal extrahierte Inhalte.
- Dokumentinhalte bleiben nicht vertrauenswürdige Benutzerdaten.

## Geplant für 0.6.2

- Aktivierung von `attachment_list`.
- Aktivierung von `attachment_describe`.
- Aktivierung von `attachment_search`.
- Aktivierung von `attachment_read_section`.

## Version

- App-Version: 0.6.1
- Build: 17
