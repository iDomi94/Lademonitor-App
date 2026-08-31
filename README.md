# Lademonitor App

**Sprache:** Deutsch | [English](README.en.md)

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](LICENSE)

SwiftUI-App für [Lademonitor](https://github.com/iDomi94/Lademonitor-Server) –
eine Ladevorgang-Tracking-App für ein E-Auto. Die App unterstützt zwei Modi,
die beim ersten Start gewählt werden: einen **Local-Only-Modus** (alle Daten
bleiben ausschließlich per SwiftData auf dem Gerät, kein Server nötig) sowie
einen **Server-Modus** als REST-Client gegen das selbstgehostete
Lademonitor-Backend mit bidirektionaler Synchronisierung, damit Web-UI und
App immer denselben Stand zeigen. Der Modus lässt sich später jederzeit
wechseln, lokale Daten können dabei zu einem Server hochgeladen werden.

## Features

- Dashboard mit Kosten-/kWh-Statistiken pro Monat
- Ladevorgänge ansehen, anlegen und bearbeiten
- Fahrzeuge, Ladeanbieter und bekannte Ladeorte verwalten
- Verbrauchsanzeige (kWh/100km) pro Ladevorgang
- Login/Registrierung gegen den eigenen Server, Token sicher im iOS-Keychain
  (Server-Adresse selbst ist keine sensible Information und liegt in
  UserDefaults)

## Voraussetzung

Im Local-Only-Modus keine – die App läuft komplett offline auf dem Gerät.

Für den Server-Modus ein laufender
[Lademonitor-Server](https://github.com/iDomi94/Lademonitor-Server)
(selbstgehostet, per Docker). Beim ersten Start der App die Server-Adresse
(Domain, z.B. `lademonitor.example.com` – `https://` wird automatisch ergänzt
falls kein Schema angegeben ist) sowie Nutzername/Passwort eines auf dem
Server registrierten Kontos eingeben.

## Projektstruktur

```
Lademonitor/
  Models/Models.swift          - Codable-Pendant zu den Server-Schemas
  Networking/
    APIClient.swift            - REST-Aufrufe, haengt Authorization-Header an
    AppSettings.swift          - Server-Adresse (UserDefaults)
    KeychainStore.swift        - Token-Speicherung (Keychain)
    SessionManager.swift       - Login-/Session-State
    CurrentLocationProvider.swift
  Views/                       - Dashboard, SessionsList, AddEditSession,
                                  Vehicles-/Providers-/LocationsSettings, Auth
```

## Build

Xcode-Projekt öffnen (`Lademonitor-App.xcodeproj`) und auf Gerät/Simulator
ausführen. Kein CocoaPods/SPM-Setup jenseits der Standard-Frameworks nötig.

## Lizenz

AGPL-3.0, siehe [LICENSE](LICENSE) – passend zum Server-Repo.
