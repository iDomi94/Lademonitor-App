# Lademonitor App

**Language:** English | [Deutsch](README.md)

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](LICENSE)

SwiftUI app for [Lademonitor](https://github.com/iDomi94/Lademonitor-Server) –
a self-hosted charging session tracking app for an EV. The app is a
pure REST client against the Lademonitor backend; there is no local
data storage (no SwiftData/CoreData) – without a connection to your own
server the app doesn't work, and that's intentional: the database lives
centrally on the server, so the web UI and the app always show the same
state.

## Features

- Dashboard with cost/kWh statistics per month
- View, create, and edit charging sessions
- Manage vehicles, charging providers, and known charging locations
- Consumption display (kWh/100km) per charging session
- Login/registration against your own server, token stored securely in the
  iOS Keychain (the server address itself is not sensitive information and
  is stored in UserDefaults)

## Requirement

A running [Lademonitor-Server](https://github.com/iDomi94/Lademonitor-Server)
(self-hosted, via Docker). On first launch, enter the server address
(domain, e.g. `lademonitor.example.com` – `https://` is automatically added
if no scheme is specified) as well as the username/password of an account
registered on the server.

## Project structure

```
Lademonitor/
  Models/Models.swift          - Codable counterpart to the server schemas
  Networking/
    APIClient.swift            - REST calls, attaches the Authorization header
    AppSettings.swift          - Server address (UserDefaults)
    KeychainStore.swift        - Token storage (Keychain)
    SessionManager.swift       - Login/session state
    CurrentLocationProvider.swift
  Views/                       - Dashboard, SessionsList, AddEditSession,
                                  Vehicles-/Providers-/LocationsSettings, Auth
```

## Build

Open the Xcode project (`Lademonitor-App.xcodeproj`) and run it on a
device/simulator. No CocoaPods/SPM setup needed beyond the standard
frameworks.

## License

AGPL-3.0, see [LICENSE](LICENSE) – matching the server repo.
