# AgenTM5N 0.8.0 Build 20

## Unified Context Engine

AgenTM5N besitzt nun einen gemeinsamen Retrieval-Layer über drei lokale Kontextquellen:

- **Workspace Memory** – bestehender persistenter Workspace-Index
- **Conversation Attachments** – extrahierter Text aus Anhängen abgeschlossener Chat-Turns
- **Knowledge Library** – persistente aktivierte Wissenssammlungen und Dokumente

## Neue Agent-Werkzeuge

### `context_search`

- durchsucht standardmäßig alle drei Quellen gemeinsam
- optionaler Scope: `all`, `attachments`, `knowledge` oder `workspace`
- maximal 20 Gesamttreffer
- einheitliches lexikalisches Ranking über Phrase, Suchbegriffe, Titel und Locator
- liefert `source_id`, Quellentyp, Titel, Locator, Score und begrenzten Textausschnitt
- meldet nicht verfügbare Quellen als Warnung, statt die gesamte Suche abzubrechen

### `context_read_source`

- liest eine exakte `source_id` aus `context_search` erneut lokal auf
- maximal 12.000 Zeichen
- unterstützt Workspace-Chunks, Knowledge-Abschnitte und persistierte Conversation-Attachments
- liefert keine Binärdaten oder internen Speicherpfade

## Stabile Source-IDs

Source-IDs sind lokalisierbare AgenTM5N-Bezeichner:

- `context://workspace/...`
- `context://knowledge/...`
- `context://attachment/...`

Sie enthalten keine absoluten Workspace-Pfade, Knowledge-Storage-Pfade, SHA-256-Werte oder Embedding-Vektoren.

## Workspace

- der bestehende Workspace-Memory-Index wird ausschließlich gelesen
- auch ein semantisch erzeugter Index kann vom Unified Context Engine lexikalisch über seine gespeicherten, bereits begrenzten Chunks durchsucht werden
- ausgegeben werden ausschließlich relative Workspace-Pfade und Zeilenbereiche
- es erfolgt kein zusätzlicher Dateisystem-Scan

## Knowledge Library

- nur aktivierte Collections und aktivierte Dokumente werden berücksichtigt
- gelesen werden ausschließlich die verwaltete Registry und Dokumentrecords
- interne `sourceRelativePath`-, `documentRelativePath`- und SHA-256-Felder werden niemals ausgegeben

## Conversation Attachments

- extrahierter Text aus bereits persistierten Benutzer-Nachrichten wird durchsucht
- strukturierte `[Datei: ...]`-Quellenmarker werden in einzelne adressierbare Quellen zerlegt
- Bilder ohne extrahierten Text erzeugen keine künstlichen Suchtreffer
- Anhänge des gerade laufenden, noch nicht persistierten Benutzer-Turns werden nicht doppelt indexiert; ihr Inhalt befindet sich bereits direkt im Modellkontext des laufenden Turns

## Ranking

Das gemeinsame Ranking ist bewusst deterministisch und lokal:

- exakte Phrase im Inhalt: hoher Boost
- exakte Phrase im Titel oder Locator: hoher Metadaten-Boost
- einzelne Suchbegriffe: gewichtete Häufigkeit
- Treffer im Titel und Locator: zusätzliche Gewichtung
- kein Netzwerkzugriff und keine Cloud-Embeddings

Damit lassen sich Ergebnisse aus Workspace, Wissensbibliothek und Anhängen in einer einzigen sortierten Trefferliste vergleichen.

## Sicherheit

- beide Unified-Context-Werkzeuge sind reine Leseoperationen
- keine Erweiterung der bestehenden Berechtigungsgrenzen
- keine absoluten Workspace-Pfade
- keine Knowledge-Storage-Pfade
- keine SHA-256-Werte
- keine Embedding-Vektoren
- keine Base64- oder Original-Binärdaten
- deaktivierte Knowledge-Collections und -Dokumente bleiben ausgeschlossen
- Workspace Memory wird nur über den bereits vorhandenen Index gelesen

## Version

- App-Version: 0.8.0
- Build: 20
