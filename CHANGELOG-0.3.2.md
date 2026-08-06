# AgenTM5N 0.3.2 Build 11

## Behoben

- Bestehende SSH-Profile mit mehrfach verwendeter UUID werden beim App-Start automatisch repariert.
- Das erste Profil behält seine UUID; jedes weitere Profil mit derselben UUID erhält eine neue eindeutige UUID.
- SwiftUI kann dadurch jede SSH-Zeile wieder eindeutig identifizieren und zeigt Hostname beziehungsweise IP pro Profil korrekt an.
- Vor der Reparatur wird eine lokale Sicherung der ursprünglichen `ssh-hosts.json` angelegt.
- Hostname, IP, Port, Benutzername, Authentifizierungsart und Vault-Referenzen bleiben bei der Migration unverändert.

## Enthalten

- isolierter Core-ML-Prediction-Runner für Swift 6.4 und Xcode 27
- getrennte SSH-Editor-Sitzungen für neue und bestehende Profile
- Schutz gegen doppelte SSH-Profilnamen

## Version

- App-Version: 0.3.2
- Build: 11
