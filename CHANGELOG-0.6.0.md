# AgenTM5N 0.6.0 Build 16

## Neu

- Lokale Extraktion von DOCX-, XLSX- und PPTX-Dokumenten.
- Seitenbezogene PDF-Extraktion mit Apple-Vision-OCR-Fallback für gescannte PDFs.
- Lokale OCR für Bildanhänge.
- Strukturierte Quellenmarker für Dokumentabschnitte:
  - Word: Abschnitt
  - Excel: Arbeitsblatt und Zeilenbereich
  - PowerPoint: Folie und Sprechernotizen
  - PDF: Seite
- SHA-256-basierter Extraktionscache.
- Attachment Inspector mit Extraktionsdetails und Inhaltsvorschau.

## Office-Verarbeitung

- Office-Dateien werden als Open-XML-Archive gelesen.
- Es werden nur explizit benötigte XML-Einträge verarbeitet.
- Archive werden nicht in den Workspace entpackt.
- Word extrahiert Dokumenttext, Kopf-/Fußzeilen, Fußnoten, Endnoten und Kommentare.
- Excel extrahiert Blattnamen, Zellreferenzen, Werte und Formeln.
- PowerPoint extrahiert Folientext und Sprechernotizen.
- Makros, eingebettete Programme und externe Links werden nicht ausgeführt.

## OCR

- OCR verwendet ausschließlich Apples lokales Vision Framework.
- Gescannte PDFs werden nur dann per OCR verarbeitet, wenn keine brauchbare Textebene vorhanden ist.
- Maximal 40 PDF-Seiten werden per OCR verarbeitet.
- Bild-OCR ist ergänzend; ein OCR-Fehler blockiert einen normalen Vision-Bildanhang nicht.

## Cache und Sicherheit

- Cache-Schlüssel ist der SHA-256-Hash der Originaldatei.
- Originaldokumente werden nicht in den Cache kopiert.
- Cache-Verzeichnis: `0700`.
- Cachedateien: `0600`.
- Maximal 25 MiB pro Office-/PDF-Quelldatei.
- Maximal 5.000 Archiveinträge.
- Maximal 8 MiB pro gelesener OOXML-Komponente.
- Maximal 100 Excel-Arbeitsblätter.
- Maximal 300 PowerPoint-Folien.
- Pfadtraversal und absolute Archiveinträge werden abgelehnt.
- Dokumentinhalte bleiben nicht vertrauenswürdige Benutzerdaten.

## Version

- App-Version: 0.6.0
- Build: 16
