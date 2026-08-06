# AgenTM5N 0.4.0 Build 12

## Neu

- Lokales semantisches Workspace-Gedächtnis.
- Persistenter Workspace-Index unter `~/Library/Application Support/AgenTM5N/WorkspaceMemory`.
- Isolierter Core-ML-Text-Embedding-Runner für Xcode 27 und Swift 6.4.
- Neuer Bereich **Workspace-Gedächtnis** mit Modellwahl, Indexstatus, Neuaufbau, Suche und Löschung.
- Agent-Werkzeuge:
  - `workspace_index_status`
  - `workspace_index_build`
  - `workspace_semantic_search`
  - `workspace_index_clear`

## Sicherheit

- Es werden nur reguläre UTF-8-Dateien innerhalb des ausgewählten Workspace indexiert.
- Symlinks, versteckte Dateien sowie typische Build-, Dependency-, Credential- und Secret-Verzeichnisse werden ausgelassen.
- Modellpfade, Indexpfade und Embedding-Vektoren werden nicht an das Sprachmodell zurückgegeben.
- Der Index wird atomar gespeichert und erhält Dateiberechtigung `0600`.
- In diesem Milestone erfolgt keine automatische Kontextinjektion in Benutzerprompts.

## Grenzen

- 1 MiB pro Datei
- 2.000.000 indexierte Zeichen
- 1.200 Textabschnitte
- 20 Suchtreffer
- ungefähr 1.600 Zeichen pro Abschnitt mit drei Zeilen Überlappung

## Modellanforderung

Das verwendete Core-ML-Modell muss genau eine Eingabe vom Typ `String` und genau eine Ausgabe vom Typ `MultiArray` besitzen. Andere Modelle werden mit einer eindeutigen Diagnose abgelehnt.

## Version

- App-Version: 0.4.0
- Build: 12
