# AgenTM5N 0.7.0 Build 19

## Knowledge Library

- Neue dauerhafte lokale Wissensbibliothek mit mehreren Collections beziehungsweise Projekten.
- Erste Installation erzeugt die Standardsammlung `Allgemein`.
- Collections können erstellt, umbenannt, aktiviert, deaktiviert und gelöscht werden.
- Wissensdokumente können pro Collection importiert, aktualisiert, aktiviert, deaktiviert und gelöscht werden.
- Ein erneuter Import derselben Datei in dieselbe Collection wird über SHA-256 als Dublette erkannt.
- Eine geänderte Datei mit demselben Dateinamen aktualisiert den bestehenden Dokumentdatensatz und behält seine stabile Dokument-ID.

## Dokumentformate

- PDF, DOCX, XLSX und PPTX verwenden die bestehende Document-Intelligence-Pipeline.
- Text-, Markdown-, Quellcode-, JSON-, YAML-, XML-, CSV-, Log- und Konfigurationsdateien werden lokal als UTF-8 extrahiert.
- Strukturierte Quellen-Locators aus PDF, Word, Excel und PowerPoint bleiben erhalten.
- Textdateien werden in begrenzte, adressierbare Quellenabschnitte zerlegt.

## Speicherung und Sicherheit

- Bibliothek: `Application Support/AgenTM5N/KnowledgeLibrary`.
- Verzeichnisse erhalten `0700`, Registry, Dokumentrecords und verwaltete Quelldateien `0600`.
- Originale Importdateien werden als geschützte verwaltete Kopien gespeichert, damit das Wissen unabhängig vom ursprünglichen Dateipfad erhalten bleibt.
- Interne Quelldateipfade, Dokumentrecord-Pfade und SHA-256-Werte werden nicht über Agent-Werkzeuge ausgegeben.
- Verwaltete Pfade werden gegen absolute Pfade und `..`-Traversal validiert.
- Maximal 25 MiB Quelldatei und maximal 240.000 extrahierte Zeichen pro Dokument.

## Suche

- Lokale lexikalische Suche über alle aktivierten Dokumente aktivierter Collections.
- Optional kann die Suche auf eine einzelne Collection eingeschränkt werden.
- Ranking berücksichtigt exakte Phrasen, Begriffe, Dokumentnamen und Quellen-Locators.
- Maximal 20 Treffer mit begrenzten Textausschnitten.

## Knowledge Center

- Neuer Toolbar-Einstieg `Wissensbibliothek` im Chat.
- Drei Bereiche für Collections, Dokumente/Suche und Quelleninspektor.
- Importstatus unterscheidet neue Dokumente, Updates und Dubletten.
- Dokumentdetails zeigen Typ, Größe, Extraktionsmethode, Abschnitte, Seiten, Tabellenblätter, Folien und OCR-Status.
- Interne Pfade und Hashwerte werden in der Oberfläche nicht angezeigt.

## Agent-Werkzeuge

- `knowledge_list_collections`
- `knowledge_list_documents`
- `knowledge_search`
- `knowledge_read_source`
- `knowledge_import_document`
- Lese-Werkzeuge sind als `read` klassifiziert.
- `knowledge_import_document` ist eine Schreiboperation und importiert ausschließlich Dateien innerhalb des konfigurierten Workspace.
- Pfade außerhalb des Workspace und Symlink-Ausbrüche werden abgelehnt.
- Tool-Ergebnisse enthalten keine verwalteten Binärdaten, internen Pfade oder SHA-256-Werte.

## Version

- App-Version: 0.7.0
- Build: 19
