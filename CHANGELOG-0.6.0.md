# AgenTM5N 0.6.0 Build 16

## Document Intelligence

- DOCX-Extraktion aus Office Open XML mit Dokumenttext, Kopf- und Fußzeilen, Fußnoten, Endnoten und Kommentaren.
- XLSX-Extraktion mit Blattnamen, Zeilenbereichen, Zellreferenzen, Werten und Formeln.
- PPTX-Extraktion mit Folientext und Sprechernotizen.
- PDF-Textebene mit Quellenangaben pro Seite.
- Lokaler Apple-Vision-OCR-Fallback für gescannte PDFs.
- Lokale OCR für Bildanhänge.
- Strukturierte Quellenmarker werden bei der Extraktion erzeugt und nicht nachträglich vom Sprachmodell erfunden.

## Attachment Inspector

- Jeder Anhangschip besitzt eine Info-Schaltfläche.
- Der Inspector zeigt Dateityp, Extraktionsmethode, Dateigröße, Seiten, Folien oder Tabellenblätter, Anzahl Abschnitte, OCR-Nutzung, Cache-Treffer und Kürzungsstatus.
- Strukturierte Dokumentabschnitte werden mit Quellen-Locator und lokaler Inhaltsvorschau angezeigt.

## Agent-Werkzeuge

- `attachment_list` listet Anhänge der aktuellen Unterhaltung mit stabilen IDs und begrenzten Metadaten.
- `attachment_describe` beschreibt einen Anhang und liefert verfügbare Quellen-Locators.
- `attachment_search` durchsucht lokal extrahierten Text und OCR-Text in Anhängen der aktuellen Unterhaltung.
- `attachment_read_section` liest einen begrenzten Dokumentabschnitt anhand eines Quellen-Locators.
- Alle vier Werkzeuge sind reine Leseoperationen.
- Binärdaten, Base64-Bilder, interne Cachepfade und SHA-256-Werte werden nicht an das Sprachmodell ausgegeben.

## Cache und Sicherheit

- Extraktionsergebnisse werden anhand des SHA-256-Inhaltswerts wiederverwendet.
- Originaldokumente werden nicht in den Cache kopiert.
- Cache-Verzeichnisse erhalten Berechtigung `0700`, Cachedateien `0600`.
- Office-Makros und eingebettete Programme werden nicht ausgeführt.
- Dokumente lösen keine externen Links oder Netzwerkzugriffe aus.
- OOXML-Dateien werden nur über explizit erlaubte Archiveinträge gelesen und nicht in den Workspace entpackt.
- Pfadtraversal, absolute Archiveinträge und unkontrollierte ZIP-Expansion werden blockiert.

## Grenzen

- maximal 25 MiB Quelldatei für PDF und Office-Dokumente
- maximal 5.000 ZIP-Einträge
- maximal 8 MiB pro gelesener OOXML-Komponente
- maximal 100 Excel-Arbeitsblätter
- maximal 300 PowerPoint-Folien
- maximal 40 PDF-Seiten für OCR
- maximal 240.000 extrahierte Zeichen pro Dokument

## Version

- App-Version: 0.6.0
- Build: 16
