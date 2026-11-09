import XCTest
import UIKit

/// Erzeugt die App-Store-Screenshots mit den Beispieldaten aus
/// `ScreenshotDemoData` (Launch-Argument `-screenshotDemo`).
///
/// Die Bilder landen als Attachments im Testergebnis; `scripts/screenshots.sh`
/// startet den Test fuer alle Geraete/Sprachen und exportiert sie als PNG.
/// Sprache per Umgebungsvariable `SCREENSHOT_LANG` (Standard: de) - beim
/// Aufruf ueber xcodebuild als `TEST_RUNNER_SCREENSHOT_LANG`.
///
/// Sind zusaetzlich `SCREENSHOT_SERVER_URL`, `SCREENSHOT_USER` und
/// `SCREENSHOT_PASSWORD` gesetzt, meldet sich die App im Server-Modus mit
/// diesem Testkonto an, statt die lokalen Beispieldaten zu zeigen.
final class ScreenshotTests: XCTestCase {
    private static let serverKeys = ["SCREENSHOT_SERVER_URL", "SCREENSHOT_USER", "SCREENSHOT_PASSWORD"]

    private var app: XCUIApplication!
    private var usesServer = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        let language = environment["SCREENSHOT_LANG"] ?? "de"
        let region = language == "de" ? "DE" : "US"

        app = XCUIApplication()
        app.launchArguments += [
            "-screenshotDemo",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", "\(language)_\(region)"
        ]
        for key in Self.serverKeys {
            if let value = environment[key], !value.isEmpty {
                app.launchEnvironment[key] = value
            }
        }
        usesServer = Self.serverKeys.allSatisfy { app.launchEnvironment[$0] != nil }
    }

    @MainActor
    func testAppStoreScreenshots() throws {
        XCUIDevice.shared.orientation = .portrait
        app.launch()

        // Im Server-Modus erscheinen die Tabs erst nach der Anmeldung.
        XCTAssertTrue(
            waitForTabs(timeout: usesServer ? 30 : 10),
            usesServer ? "Anmeldung am Testkonto fehlgeschlagen?" : "App nicht gestartet"
        )
        // Erster Sync mit dem Server.
        if usesServer { settle(seconds: 6) }

        // 1. Dashboard
        tab(0).tap()
        settle()
        collapseLargeTitle()
        snapshot("01-Dashboard")

        // 2. Ladevorgaenge + 3. Detail des neuesten Vorgangs. Auf dem iPad
        // zeigt 03 die Liste ohnehin neben dem Detail - 02 entfaellt dort.
        tab(1).tap()
        settle()
        if !isPad {
            collapseLargeTitle()
            snapshot("02-Ladevorgaenge")
        }

        let firstSession = app.descendants(matching: .any).matching(identifier: "session.row").firstMatch
        if firstSession.waitForExistence(timeout: 5) {
            firstSession.tap()
            settle()
            snapshot("03-Ladevorgang")
            goBack()
        } else {
            dumpHierarchy("03-Ladevorgang")
        }

        // 4. Karte - Kacheln brauchen etwas laenger
        tab(2).tap()
        settle(seconds: 4)
        snapshot("04-Karte")

        // 5. Tools, 6. Rueckblick, 7. Verbrenner-Vergleich,
        // 8. Akku (nur im Server-Modus vorhanden)
        // Auf dem iPad steht die Tool-Liste in 06-08 als Seitenleiste mit
        // drauf - 05 entfaellt dort.
        tab(3).tap()
        settle()
        if !isPad {
            collapseLargeTitle()
            snapshot("05-Tools")
        }

        openTool("tool.review", name: "06-Rueckblick")
        openTool("tool.combustion", name: "07-Verbrenner")
        if usesServer {
            openTool("tool.battery", name: "08-Akku", seconds: 4)
        }
    }

    // MARK: - Helfer

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// Rollt die Liste ein kleines Stueck nach oben, bis der grosse Titel
    /// zur kompakten Leiste zusammenklappt - sonst steht ueber jedem
    /// Screenshot viel leerer Raum. Langsam und mit Halten am Ende, damit
    /// nichts nachschwingt.
    @MainActor
    private func collapseLargeTitle() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.54))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        settle(seconds: 1)
    }

    /// SF-Symbole der Tabs (ContentView.mainTabView) - auf dem iPad ist das
    /// der Identifier der Tab-Buttons oben, unabhaengig von der Sprache.
    private static let tabSymbols = ["chart.bar.fill", "bolt.fill", "map.fill", "wrench.and.screwdriver.fill", "gearshape.fill"]

    /// Wartet, bis die Tabs da sind - egal ob als Leiste (iPhone) oder oben (iPad).
    @MainActor
    private func waitForTabs(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.tabBars.buttons.count > 0 || app.buttons[Self.tabSymbols[0]].exists {
                return true
            }
            settle(seconds: 0.5)
        }
        return false
    }

    /// iPhone: Tab-Leiste unten, iPad: schwebende Tabs oben.
    @MainActor
    private func tab(_ index: Int) -> XCUIElement {
        let tabBar = app.tabBars.buttons
        if tabBar.count > index {
            return tabBar.element(boundBy: index)
        }
        return app.buttons.matching(identifier: Self.tabSymbols[index]).firstMatch
    }

    @MainActor
    private func openTool(_ identifier: String, name: String, seconds: TimeInterval = 2) {
        let link = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        guard link.waitForExistence(timeout: 5) else {
            dumpHierarchy(name)
            return
        }
        link.tap()
        settle(seconds: seconds)
        snapshot(name)
        goBack()
    }

    /// Zurueck per Wisch vom linken Rand - unabhaengig davon, welche Buttons
    /// die Navigationsleiste gerade zeigt.
    @MainActor
    private func goBack() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        settle(seconds: 1)
    }

    /// Haengt den Elementbaum ans Ergebnis, wenn etwas nicht gefunden wurde -
    /// zur Fehlersuche, landet nicht bei den Screenshots.
    @MainActor
    private func dumpHierarchy(_ step: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = "debug-\(step)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Wartet, bis Animationen und das asynchrone Laden durch sind.
    private func settle(seconds: TimeInterval = 2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor
    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
