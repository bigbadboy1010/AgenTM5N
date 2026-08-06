# AgenTM5N 0.3.1 Build 10

## Behoben

- Der SSH-Editor verwendet für jedes Öffnen eine neue, eindeutig identifizierte Editor-Sitzung.
- Beim Hinzufügen eines weiteren Hosts werden die UUID und Formularwerte des zuvor bearbeiteten Profils nicht mehr wiederverwendet.
- Ein neues SSH-Profil kann dadurch kein vorhandenes Profil mehr unbeabsichtigt überschreiben.
- Abbrechen verwirft den aktuellen Entwurf vollständig.
- Nach erfolgreichem Speichern wird die Editor-Sitzung geschlossen und zurückgesetzt.

## Verbessert

- Eindeutige SSH-Profilnamen werden bereits im Formular geprüft.
- Doppelte Profilnamen werden blockiert, weil Agent-Werkzeuge Hosts sonst nicht eindeutig über den Namen auflösen könnten.
- Eingaben für Name, Hostname, Benutzername und Remote-Kommando werden vor dem Speichern normalisiert.
- Die SSH-Ansicht zeigt die Anzahl gespeicherter Profile.
- SSH-Ansicht und Editor folgen der bevorzugten macOS-Sprache.
- Neue Profile zeigen explizit an, dass eine neue eindeutige ID erzeugt wurde.

## Version

- App-Version: 0.3.1
- Build: 10
