# Changelog

Der Abschnitt einer Version landet beim Release-Tag `vX.Y.Z` automatisch als
„Was testen“ in TestFlight (siehe `.github/workflows/testflight.yml`). Die
Überschrift muss `## X.Y.Z` lauten (optional mit Datum dahinter), der Text
bis zur nächsten `## `-Überschrift wird übernommen – höchstens 4000 Zeichen.
Fehlt der Abschnitt, gehen stattdessen die Commit-Titel seit dem letzten Tag
nach TestFlight.

## 1.1.0

- Neues Tool „Vergleich mit Verbrenner“: was deine gefahrenen Kilometer mit
  Benzin oder Diesel gekostet hätten und wie viel CO₂ dabei entstanden wäre.
  Verbrauch, Spritpreis und CO₂ des Stroms lassen sich per Regler anpassen.
- Neues Tool „Akku und Ladeverluste“ (nur mit Server ab 0.28.0): Akku-Index
  je Quartal und der Mehrbedarf beim Laden, getrennt nach AC/DC und Anbieter.
- Homescreen-Widget mit Kosten und kWh des laufenden Monats, in der mittleren
  Größe zusätzlich mit dem letzten Ladevorgang. Auch für den Sperrbildschirm.

## 1.0.0

Erste Version mit automatischem TestFlight-Upload.

- Ladevorgänge erfassen, bearbeiten und auswerten – lokal auf dem Gerät oder
  synchronisiert mit dem eigenen Lademonitor-Server
- Dashboard mit Kosten, kWh und Verbrauch je Monat
- Außentemperatur, Reifensätze und Grundgebühren der Anbieter
- Reiter „Tools“ mit dem Rechner „Lohnt sich der Tarif?“
