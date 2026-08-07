# AgenTM5N 0.9.0 Build 21

## Document Studio

AgenTM5N kann Dokumente nun vollständig lokal erzeugen, verwalten und über den normalen macOS-Speicherdialog exportieren.

## Formate

- **DOCX** – Text und einfaches Markdown mit Titel, Überschriften und Aufzählungen.
- **PDF** – mehrseitige lokale PDF-Erzeugung mit Core Graphics/Core Text; Titel, Überschriften und Aufzählungen werden formatiert.
- **XLSX** – Tabellen aus TSV oder CSV; erste Zeile als Kopfzeile, eingefrorene Kopfzeile und begrenzte Spaltenbreiten.
- **PPTX** – 16:9-Präsentationen; Folien werden durch eine Zeile `---` getrennt, erste Zeile je Abschnitt ist der Folientitel.

Legacy-Binärdateien im Format `.xls` werden in diesem Milestone nicht erzeugt; AgenTM5N verwendet das moderne OOXML-Format `.xlsx`.

## Lokaler Dokument-Store

- interne Ablage unter `Application Support/AgenTM5N/GeneratedDocuments`
- Ablageverzeichnis mit Berechtigung `0700`
- Registry und verwaltete Dokumente mit Berechtigung `0600`
- stabile Dokument-IDs
- generierte Dateien können aus dem lokalen Store gelöscht werden
- interne verwaltete Pfade werden nicht an Sprachmodelle ausgegeben

## Export

- Export über `NSSavePanel`
- Ziel kann Schreibtisch, Downloads oder ein beliebiger vom Benutzer gewählter Ordner sein
- der sichtbare Exportdateiname ist unabhängig vom internen verwalteten Dateinamen

## Agent-Werkzeuge

- `document_generate`
- `document_list_generated`
- `document_delete_generated`

`document_generate` und `document_delete_generated` sind Schreiboperationen. `document_list_generated` ist eine reine Leseoperation.

## Sicherheitsgrenzen

- keine Office-Makros
- keine externen Dokumentlinks
- XLSX-Zellen werden als Inline-Strings geschrieben; Inhalte werden nicht als Formeln ausgeführt
- maximal 240.000 Inhaltszeichen pro Dokument
- maximal 20.000 XLSX-Zellen
- maximal 40 PPTX-Folien
- keine Cloud-Dateidienste für die Dateierzeugung erforderlich

## Version

- App-Version: 0.9.0
- Build: 21
