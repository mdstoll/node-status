import XCTest

/// Loopt de app door en legt elk scherm vast. Dit is geen assertie-test maar
/// een visuele verificatie: de screenshots worden weggeschreven zodat ze
/// naast de referentiebeelden gelegd kunnen worden.
final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!
    private let outputDir = "/tmp/serverinfo-shots"

    override func setUpWithError() throws {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(atPath: outputDir,
                                                withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launch()
    }

    private func snap(_ name: String, wait: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: wait)
        let shot = XCUIScreen.main.screenshot()
        let url = URL(fileURLWithPath: outputDir).appendingPathComponent("\(name).png")
        try? shot.pngRepresentation.write(to: url)
    }

    /// De tabbar klapt in bij scrollen (.tabBarMinimizeBehavior). Eerst naar
    /// boven scrollen, anders is de knop niet raakbaar.
    private func tab(_ label: String) {
        // De tabbar klapt in bij scrollen (.tabBarMinimizeBehavior). Eerst
        // helemaal naar boven, anders bestaat de knop niet eens.
        for _ in 0..<4 {
            let button = app.tabBars.buttons[label]
            if button.exists && button.isHittable {
                button.tap()
                Thread.sleep(forTimeInterval: 0.5)
                return
            }
            app.swipeDown(velocity: .fast)
            Thread.sleep(forTimeInterval: 0.5)
        }
        let button = app.tabBars.buttons[label]
        if button.exists { button.tap() }
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testWalkthrough() throws {
        // Metrics: bovenkant, dan doorscrollen naar netwerk en sensoren.
        tab("Metrics")
        snap("01-metrics-top", wait: 6)
        app.swipeUp(velocity: .slow)
        snap("02-metrics-network")
        app.swipeUp(velocity: .slow)
        snap("03-metrics-sensors")
        app.swipeUp(velocity: .slow)
        snap("04-metrics-bottom")

        // Server-tab
        tab("Server")
        snap("05-server-list")

        // Tools-lijst en een paar detailschermen
        tab("Tools")
        snap("06-tools-list")

        openTool("CPU Information", as: "07-cpu")
        openTool("Opslag & SMART", as: "08-smart")
        openTool("Locale & Region", as: "09-locale")
        openTool("Device Uptime", as: "10-uptime")
        openTool("System & Updates", as: "11-updates")
        openTool("Processen", as: "12-processes")
        openTool("Network Speed", as: "13-speedtest")
        openTool("Ping", as: "14-ping")
        openTool("Log Analyzer", as: "15-logs")
        openTool("Hardware-overzicht", as: "16-hardware")
        openTool("Sensoren", as: "17-sensors")
        openTool("Netwerkinterfaces", as: "18-network")

        // Settings
        tab("Settings")
        snap("19-settings")
    }

    /// Opent een rij in de Tools-lijst, maakt een screenshot en gaat terug.
    /// Scrollt zo nodig omlaag tot de rij daadwerkelijk raakbaar is.
    private func openTool(_ label: String, as name: String) {
        tab("Tools")
        var found = false
        for _ in 0..<6 {
            let cell = app.buttons[label].firstMatch
            if cell.exists && cell.isHittable {
                cell.tap()
                found = true
                break
            }
            app.swipeUp(velocity: .slow)
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard found else {
            XCTFail("tool \(label) niet bereikbaar")
            return
        }
        snap(name, wait: 2.5)
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
        Thread.sleep(forTimeInterval: 0.6)
    }
}
