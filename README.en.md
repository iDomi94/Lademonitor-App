# Lademonitor App

**Language:** English | [Deutsch](README.md)

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](LICENSE)

SwiftUI app for [Lademonitor](https://github.com/iDomi94/Lademonitor-Server) –
a charging session tracking app for an EV. The app supports two modes,
chosen on first launch: a **local-only mode** (all data stays on the
device via SwiftData, no server needed) and a **server mode** acting as a
REST client against the self-hosted Lademonitor backend with bidirectional
sync, so the web UI and the app always show the same state. The mode can
be switched later at any time; local data can be uploaded to a server when
switching.

## Features

- Dashboard with cost/kWh statistics per month
- View, create, and edit charging sessions
- Manage vehicles, charging providers, and known charging locations
- Consumption display (kWh/100km) per charging session
- Login/registration against your own server – with either your username
  **or** your email address. Token stored securely in the iOS Keychain (the
  server address itself is not sensitive information and is stored in
  UserDefaults)
- Account settings: store and confirm an email address, change your own
  password, and toggle the server's notifications (failed backup, MyŠkoda
  errors, monthly report, digest of charging sessions awaiting review).
  Requires Lademonitor-Server 0.14.0 or newer – against an older server the
  section stays hidden
- "Forgot password": the app requests the link, the new password is then set
  through the link in the email, in a browser
- When you sign in to an account this device has never synced with, and data is
  already stored locally, **the app asks first**: upload it, or delete it from
  the device. Previously it silently went into whichever account you had just
  signed in to – on an account switch that included your own charging locations
  and their coordinates. Nothing is ever deleted on the server

## Deployment options

- **Standalone locally:** runs entirely offline on the device, no server
  needed (see local-only mode above)
- **Self-hosted:** your own
  [Lademonitor-Server](https://github.com/iDomi94/Lademonitor-Server), open
  source and run via Docker – full control over your own data
- **Public server** (coming soon at `lademonitor.cloud`): no server operation
  of your own, updates and backups are handled by the operator, ready to go
  instantly without a Docker/domain setup

Server mode (self-hosted or public) additionally provides automatic charging
session detection via Home Assistant and access from the web UI, with
bidirectional synchronization between the app, web UI, and other devices.

## Requirement

None in local-only mode – the app runs entirely offline on the device.

For server mode, a running
[Lademonitor-Server](https://github.com/iDomi94/Lademonitor-Server)
(self-hosted, via Docker). On first launch, enter the server address
(domain, e.g. `lademonitor.example.com` – `https://` is automatically added
if no scheme is specified) as well as the username or email address and the
password of an account registered on the server.

**Note:** Resetting or changing the password signs out every device on the
server. After a change made in the app's own settings this app stays signed in
(the server returns the new token directly, from server 0.14.1); after a reset
via the email link a fresh login is required.

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
                                  Vehicles-/Providers-/LocationsSettings, Auth,
                                  AccountSettings (email, password,
                                  notifications)
```

## Build

Open the Xcode project (`Lademonitor-App.xcodeproj`) and run it on a
device/simulator. No CocoaPods/SPM setup needed beyond the standard
frameworks.

## License

AGPL-3.0, see [LICENSE](LICENSE) – matching the server repo.
