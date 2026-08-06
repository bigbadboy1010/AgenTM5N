# AgenTM5N 0.4.1 Build 13

## Behoben

- Der Workspace-Index wird nicht mehr erst nach Abschluss aller Core-ML-Vorhersagen gespeichert.
- Nach dem Dateiscan wird sofort ein persistenter lexikalischer Textindex angelegt.
- Ein inkompatibles oder fehlerhaftes Core-ML-Modell verhindert den Indexaufbau nicht mehr.
- Modelle mit `input_ids` und `attention_mask` werden als tokenizerpflichtig diagnostiziert, statt scheinbar ohne Ergebnis abzubrechen.
- Die Suche funktioniert im lexikalischen Modus auch ohne Embedding-Modell.
- Bestehende Indexdateien aus Version 0.4.0 werden beim Laden in das neue Schema migriert.

## Sichtbarer Fortschritt

Die Oberfläche zeigt nun:

- aktuelle Aufbauphase
- Anzahl fertig verarbeiteter und gesamter Abschnitte
- Indexmodus
- Anzahl Dateien und Abschnitte
- indexierte Zeichen
- Embedding-Dimension, sofern vorhanden
- persistente Warnung bei einem Core-ML-Fallback

## Indexmodi

### Lexikalisch

- benötigt kein Core-ML-Modell
- wird sofort lokal gespeichert
- liefert gewichtete Treffer anhand von Suchbegriffen, Pfaden und Textphrasen

### Core ML semantisch

- verwendet den lexikalischen Index als sichere Basis
- ergänzt Embedding-Vektoren nur bei einem kompatiblen Modell
- benötigt genau eine String-Eingabe und eine MultiArray-Ausgabe

## Version

- App-Version: 0.4.1
- Build: 13
