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

## TestFlight

Öffentlicher Beta-Zugang über TestFlight:
[testflight.apple.com/join/NMbyFTEK](https://testflight.apple.com/join/NMbyFTEK)

## Features

- Dashboard mit Kosten-/kWh-Statistiken pro Monat
- Ladevorgänge ansehen, anlegen und bearbeiten
- Fahrzeuge, Ladeanbieter und bekannte Ladeorte verwalten
- Verbrauchsanzeige (kWh/100km) pro Ladevorgang
- Login/Registrierung gegen den eigenen Server – wahlweise mit Nutzername
  **oder** E-Mail-Adresse. Token sicher im iOS-Keychain (die Server-Adresse
  selbst ist keine sensible Information und liegt in UserDefaults)
- Konto-Einstellungen: E-Mail-Adresse hinterlegen und bestätigen, eigenes
  Passwort ändern, Benachrichtigungen des Servers ein-/ausschalten
  (fehlgeschlagenes Backup, MyŠkoda-Fehler, Monatsbericht, Sammelmeldung über
  zu prüfende Ladevorgänge). Braucht Lademonitor-Server 0.14.0 oder neuer –
  gegen einen älteren Server bleibt der Bereich ausgeblendet
- „Passwort vergessen“: die App fordert den Link an, gesetzt wird das neue
  Passwort über den Link in der Mail im Browser
- Außentemperatur je Ladevorgang erfassen und ansehen – Grundlage der
  Auswertung „Verbrauch nach Außentemperatur" im Server-Dashboard (ab
  Lademonitor-Server 0.23.0). Gemeint ist der Wert **beim Ladebeginn**: der
  Verbrauch, den der Server einem Ladevorgang zurechnet, stammt von der Fahrt
  davor. Wer Home Assistant nutzt, bekommt ihn automatisch; hier lässt er sich
  nachtragen. Funktioniert auch im Local-Only-Modus
- Reifen (Einstellungen → Reifen): jeden Reifenwechsel mit Art, Datum, Größe,
  Marke und Modell eintragen. Dazu die Übersicht, wie lange ein Satz aufgezogen
  war, wie viele Kilometer und Fahrten auf ihm liegen und wie alt er seit der
  ersten Montage ist, plus den temperaturbereinigten Vergleich Winter gegen
  Sommer. Braucht Lademonitor-Server 0.26.0 oder neuer und ist **nur im
  Server-Modus** verfügbar: die Zuordnung der Fahrten und die Bereinigung
  rechnet der Server, damit App und Web nicht unterschiedliche Zahlen zeigen
- Auf dem Server gelöschte Ladevorgänge, Fahrzeuge, Anbieter und Ladeorte
  verschwinden beim nächsten Abgleich auch aus der App. Vorher blieben sie als
  „Geisterzeilen" stehen, bis man sie auch hier löschte – die App durfte aus dem
  bloßen Fehlen eines Eintrags in der Server-Antwort nicht auf eine Löschung
  schließen, weil jede unvollständige Antwort sonst still lokale Daten
  vernichtet hätte. Der Server meldet Löschungen jetzt ausdrücklich. Braucht
  Lademonitor-Server 0.22.0 oder neuer; gegen einen älteren Server verhält sich
  die App wie bisher
- Die Ladevorgangs-Liste zeigte bis Server 0.22.0 nur die 200 neuesten Einträge
  (eine Grenze auf Serverseite, die kein Client je aufgehoben hat) – mit einem
  aktuellen Server kommen alle an, ohne dass in der App etwas einzustellen wäre
- Meldest du dich an einem Konto an, mit dem dieses Gerät noch nie
  synchronisiert hat, und liegen schon Daten auf dem Gerät, **fragt die App
  nach**: hochladen oder vom Gerät löschen. Vorher wanderten sie stillschweigend
  in das gerade angemeldete Konto – beim Kontowechsel also auch die eigenen
  Ladeorte samt Koordinaten. Auf dem Server wird dabei nie etwas gelöscht

## Einsatzmöglichkeiten

- **Standalone lokal:** läuft komplett offline auf dem Gerät, kein Server nötig
  (siehe Local-Only-Modus oben)
- **Selbst gehostet:** eigener
  [Lademonitor-Server](https://github.com/iDomi94/Lademonitor-Server), Open
  Source und per Docker betrieben – volle Kontrolle über die eigenen Daten
- **Öffentlicher Server** (in Kürze unter `lademonitor.cloud`): kein eigener
  Serverbetrieb nötig, Updates und Backups übernimmt der Betreiber, sofort
  startklar ohne Docker/Domain-Setup

Server-Modus (selbst gehostet oder öffentlich) bringt zusätzlich automatische
Ladevorgangs-Erkennung über Home Assistant sowie Zugriff vom Web-UI aus, mit
bidirektionaler Synchronisierung zwischen App, Web-UI und weiteren Geräten.

## Voraussetzung

Im Local-Only-Modus keine – die App läuft komplett offline auf dem Gerät.

Für den Server-Modus ein laufender
[Lademonitor-Server](https://github.com/iDomi94/Lademonitor-Server)
(selbstgehostet, per Docker). Beim ersten Start der App die Server-Adresse
(Domain, z.B. `lademonitor.example.com` – `https://` wird automatisch ergänzt
falls kein Schema angegeben ist) sowie Nutzername oder E-Mail-Adresse und das
Passwort eines auf dem Server registrierten Kontos eingeben.

**Hinweis:** Wird das Passwort zurückgesetzt oder geändert, meldet der Server
alle Geräte ab. Bei einer Änderung in den eigenen Einstellungen bleibt diese App
angemeldet (der Server liefert den neuen Zugang direkt mit, ab Server 0.14.1);
nach einem Zurücksetzen über den Mail-Link ist eine neue Anmeldung nötig.

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
                                  Vehicles-/Providers-/LocationsSettings, Auth,
                                  AccountSettings (E-Mail, Passwort,
                                  Benachrichtigungen)
```

## Build

Xcode-Projekt öffnen (`Lademonitor-App.xcodeproj`) und auf Gerät/Simulator
ausführen. Kein CocoaPods/SPM-Setup jenseits der Standard-Frameworks nötig.

## Lizenz

AGPL-3.0, siehe [LICENSE](LICENSE) – passend zum Server-Repo.
