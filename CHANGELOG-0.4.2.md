# AgenTM5N 0.4.2 Build 14

## Behoben

- Core-ML-Modelle werden für das Workspace-Gedächtnis nach ihrer tatsächlichen Eingabe-/Ausgabe-Schnittstelle klassifiziert.
- Tokenisierte Modelle mit `inputIds`, `input_ids`, `causalMask` oder `attentionMask` werden nicht mehr als direkte Text-Embedding-Modelle angeboten.
- Ein bestehender ungeeigneter Modellwert wird beim Öffnen des Workspace-Gedächtnisses automatisch auf den lexikalischen Modus zurückgesetzt.
- Nur Modelle mit genau einer `String`-Eingabe und genau einer `MultiArray`-Ausgabe erscheinen im Embedding-Picker.

## Modellklassen

- direktes Text-Embedding-Modell
- tokenisiertes generatives Sprachmodell
- tokenisiertes Transformer-Modell
- Bild-/Vision-Modell
- allgemeines Core-ML-Modell

## Verhalten für `inputIds` + `causalMask`

Ein solches Modell wird als tokenisiertes generatives Sprachmodell erkannt. Es bleibt im allgemeinen Neural-Engine-/Core-ML-Bereich registriert, wird jedoch nicht für Workspace-Embeddings angeboten.

Ein Tokenizer allein genügt für semantische Suche nicht zwingend. Zusätzlich muss das Modell eine geeignete Hidden-State- oder Embedding-Ausgabe liefern, oder es muss eine definierte Pooling-Schicht vorhanden sein. Modelle, die ausschließlich Token-Logits ausgeben, sind keine geeigneten Satz-Embedding-Modelle.

## Workspace-Gedächtnis

- Der lexikalische Index funktioniert weiterhin ohne Core ML.
- Nicht kompatible Modelle werden in einem separaten Informationsbereich mit ihrer Klasse und einer konkreten Erklärung angezeigt.
- Der vorhandene Textindex bleibt unverändert nutzbar.

## Version

- App-Version: 0.4.2
- Build: 14
