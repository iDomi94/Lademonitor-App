# Changelog

Der Abschnitt einer Version landet beim Release-Tag `vX.Y.Z` automatisch als
„Was testen“ in TestFlight (siehe `.github/workflows/testflight.yml`). Die
Überschrift muss `## X.Y.Z` lauten (optional mit Datum dahinter), der Text
bis zur nächsten `## `-Überschrift wird übernommen – höchstens 4000 Zeichen.
Fehlt der Abschnitt, gehen stattdessen die Commit-Titel seit dem letzten Tag
nach TestFlight.

## 1.4.0

- Anbieter haben einen Ladeort: Zuhause, Arbeit oder Unterwegs (Standard).
  Das Dashboard zeigt dann kWh, Kosten und Preis je kWh getrennt nach
  Ladeort – sobald im Zeitraum mindestens ein Ladevorgang zuhause oder bei der
  Arbeit liegt. Der Ladeort wird mit dem Server synchronisiert (ab 0.31.0).
- Tarifrechner: der automatische Preis ohne Tarif zählt jetzt alle Anbieter
  mit Ladeort „Unterwegs“. Die frühere Auswahl „Öffentliche Anbieter“ entfällt;
  dort abgewählte Anbieter werden beim ersten Start einmalig auf „Zuhause“
  gestellt.
- Ladevorgangsliste: unter dem SoC-Text zeigt ein schmaler Ladebalken (0–100 %)
  den geladenen Bereich in Grün, dazu zwei rote Markierungen – standardmäßig
  bei 10 % und 100 %. In den Einstellungen unter „Darstellung → Ladebalken“
  lassen sich beide Markierungen einzeln abschalten und in 5-%-Schritten
  verschieben, mit Vorschau. Die Einstellung gilt nur auf diesem Gerät.
- Fahrzeugkosten: unter „Fahrzeuge → Fahrzeug → Kosten“ lassen sich
  Versicherung, Kfz-Steuer, Wartung, Reparaturen, Reifen, Wallbox, Parken,
  Maut, Wäsche und Sonstiges eintragen – einmalig, monatlich oder jährlich,
  mit optionaler letzter Zahlung. Dazu eine Übersicht der Kosten je Jahr.
- Kauf oder Leasing am Fahrzeug: beim Kauf schätzt die App den heutigen Wert
  und schlägt einen monatlichen Wertverlust vor (überschreibbar), beim
  Leasing zählt die Monatsrate plus anteilige Sonderzahlung.
- Dashboard: neuer Abschnitt „Gesamtkosten“ mit Laden, sonstigen Kosten und
  Wertverlust bzw. Leasing, Kosten je km, Anteil des Ladens und einem Balken
  je Kategorie. Er erscheint, sobald es Kosten oder eine Kauf-/Leasingangabe
  gibt. Funktioniert auch ohne Server; synchronisiert wird ab Server 0.32.0.
- Erinnerungen: unter „Fahrzeuge → Fahrzeug → Erinnerungen“ an HU,
  Inspektion, Bremsflüssigkeit, Reifenwechsel, Versicherung, Kfz-Steuer,
  THG-Quote oder Eigenes erinnern lassen – fällig nach Datum und/oder
  km-Stand, mit Wiederholung und Vorlauf. Den km-Stand nimmt die App aus den
  Ladevorgängen und schätzt aus der Fahrleistung, wann er erreicht ist.
  „Erledigt“ setzt die nächste Fälligkeit und bietet danach einen passenden
  Kosteneintrag an.
- Dashboard: bald fällige und überfällige Erinnerungen stehen ganz oben.
- Mitteilungen für Erinnerungen zu Beginn des Vorlaufs und am Fälligkeitstag
  um 9 Uhr, auch ohne Server; abschaltbar in den Einstellungen. Erinnerungen
  funktionieren auch ohne Server; synchronisiert wird ab Server 0.33.0.

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
