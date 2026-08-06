# AgenTM5N 0.5.0 Build 15

## Neu

- Echte Bildanhänge für visionfähige Ollama-Modelle.
- Auswahl von Text-, PDF- und Bilddateien über die Büroklammer.
- Drag-and-drop von Dateien und Bildern direkt in den Chat-Composer.
- Lokale Bildvorschau vor dem Senden.
- Persistente Bildvorschau im Nachrichtenverlauf.
- Prüfung der Ollama-Modellfähigkeit über `/api/show` vor dem Bildversand.
- Bildübertragung über das offizielle Ollama-Nachrichtenfeld `images`.

## Bildverarbeitung

- Unterstützte Quellen: JPEG, PNG, HEIC/HEIF, TIFF, BMP, GIF und WebP, sofern macOS sie dekodieren kann.
- Bilder werden lokal dekodiert und auf maximal 2048 Pixel Kantenlänge reduziert.
- Der Payload wird als kontrolliertes JPEG mit Qualitätsfaktor 0,86 erzeugt.
- Transparente Bildbereiche werden vor der JPEG-Erzeugung auf weißem Hintergrund gerendert.
- Im sichtbaren Prompttext und im Chatverlauf werden keine Base64-Daten angezeigt.

## Persistenz und Sicherheit

- Normalisierte Bilder werden unter `~/Library/Application Support/AgenTM5N/PromptAttachments/Images` gespeichert.
- Der Anhangsordner erhält Berechtigung `0700`.
- Persistierte Bilddateien erhalten Berechtigung `0600`.
- Nachrichten speichern ausschließlich validierte relative Bildreferenzen.
- Pfadtraversal außerhalb des geschützten Anhangsordners wird blockiert.
- Interne Bild-IDs und Speicherpfade werden vor der Übertragung aus dem Modellprompt entfernt.
- Eine neue Chat-Sitzung löscht die persistierten Bildanhänge der bisherigen Sitzung.
- Anhangsinhalte bleiben nicht vertrauenswürdige Benutzerdaten und umgehen keine Werkzeugfreigaben.

## Provider-Verhalten

- Ollama Local und Ollama Cloud akzeptieren Bilder nur, wenn `/api/show` die Capability `vision` meldet.
- Bei einem nicht visionfähigen Ollama-Modell bleibt die Nachricht mit Bildreferenz erhalten und AgenTM5N zeigt eine konkrete Fehlermeldung.
- Der Apple-On-Device-Provider lehnt Bildanhänge vor der Persistierung ab; der Entwurf bleibt im Composer erhalten.
- Bestehende Text-, Quellcode-, Konfigurations-, Log-, CSV-, JSON-, YAML-, XML-, Markdown- und PDF-Anhänge bleiben kompatibel.

## Grenzen

- maximal 8 Anhänge pro Prompt
- maximal 4 Bilder pro Prompt
- maximal 12 MiB Quelldatei pro Bild
- maximal 2048 Pixel Kantenlänge
- maximal 6 MiB normalisierter Payload pro Bild
- maximal 20 MiB normalisierte Bilddaten pro Prompt
- maximal 2 MiB pro Text- oder PDF-Anhang
- maximal 120.000 extrahierte Textzeichen pro Prompt

## Version

- App-Version: 0.5.0
- Build: 15
