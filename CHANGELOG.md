# Changelog

Der Abschnitt einer Version landet beim Release-Tag `vX.Y.Z` automatisch als
„Was testen“ in TestFlight (siehe `.github/workflows/testflight.yml`). Die
Überschrift muss `## X.Y.Z` lauten (optional mit Datum dahinter), der Text
bis zur nächsten `## `-Überschrift wird übernommen – höchstens 4000 Zeichen.
Fehlt der Abschnitt, gehen stattdessen die Commit-Titel seit dem letzten Tag
nach TestFlight.

## 1.3.0

- Reifen (nur mit Server ab 0.30.0): DOT-Nummer je Achse eintragen, die
  Reifensätze zeigen daraus das Reifenalter ab Produktion – ab 6 Jahren mit
  „prüfen“, ab 10 Jahren mit „tauschen“.
- Profiltiefe: Messungen zwischendurch (in der Liste der Reifenwechsel nach
  rechts wischen oder „Messung eintragen“) und direkt beim Reifenwechsel für
  den aufgezogenen und den abgenommenen Satz – als geringste Tiefe oder je
  Reifen. Die Reifensätze zeigen die jüngste Messung, mit Hinweis unter der
  Empfehlung (3 mm Sommer, 4 mm Winter/Ganzjahr) und ab 1,6 mm.

## 1.1.0

- Neues Tool „Vergleich mit Verbrenner“ mit drei Ansichten oben im Tool:
  „Zeitraum“ (was deine gefahrenen Kilometer mit Benzin oder Diesel gekostet
  hätten), „Pro 100 km“ (Kosten und CO₂ je 100 km) und „Lebenszyklus“ (CO₂
  inklusive Herstellung von Fahrzeug und Akku sowie der Kraftstoff-Vorkette,
  mit dem Kilometerstand, ab dem der Herstellungs-Rucksack eingeholt ist).
  Verbrauch, Spritpreis, CO₂ des Stroms, Laufleistung und Akku-CO₂ lassen
  sich per Regler anpassen.
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
