import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let port: UInt16 = 24_680
    private let api = APIController()
    private var server: HTTPServer?
    private var statusItem: NSStatusItem?
    private var started = false

    private var dockURL: URL {
        URL(string: "http://127.0.0.1:\(port)/")!
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        start()
    }

    func start() {
        guard !started else { return }
        started = true
        configureStatusItem()
        startServer()

        NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rescanCamera() }
        }
        NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rescanCamera() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    private func startServer() {
        let server = HTTPServer(port: port) { [weak self] method, path, body in
            guard let self else {
                return .json(status: "503 Service Unavailable", ["error": "Helper se ukončuje."])
            }
            return self.api.route(method: method, path: path, body: body)
        }

        do {
            try server.start()
            self.server = server
        } catch {
            fputs("OBS Camera Dock server nelze spustit: \(error.localizedDescription)\n", stderr)
            let alert = NSAlert()
            alert.messageText = "OBS Camera Dock nelze spustit"
            alert.informativeText = "Port \(port) není dostupný: \(error.localizedDescription)"
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: "OBS Camera Dock")
        item.menu = NSMenu()
        statusItem = item
        updateStatusMenu()
    }

    private func updateStatusMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        let state = api.state()
        let status = NSMenuItem(title: state.connected ? "● \(state.cameraName ?? "Kamera")" : "○ Kamera nepřipojena", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Otevřít ovládání", action: #selector(openDock), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "Kopírovat URL doku", action: #selector(copyDockURL), keyEquivalent: "c").target = self
        menu.addItem(withTitle: "Znovu vyhledat kameru", action: #selector(rescanCamera), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ukončit OBS Camera Dock", action: #selector(quit), keyEquivalent: "q").target = self
    }

    @objc private func openDock() {
        NSWorkspace.shared.open(dockURL)
    }

    @objc private func copyDockURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(dockURL.absoluteString, forType: .string)
    }

    @objc private func rescanCamera() {
        _ = api.rescan()
        updateStatusMenu()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

@main
struct CameraDockApplication {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--diagnose-usb") {
            runUSBDiagnostics()
            return
        }

        if CommandLine.arguments.contains("--diagnose") {
            let state = APIController().state()
            if let data = try? JSONEncoder().encode(state),
               let json = String(data: data, encoding: .utf8) {
                print(json)
            }
            return
        }

        if CommandLine.arguments.contains("--headless") {
            runHeadless()
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        delegate.start()
        app.run()
    }

    private static func runHeadless() {
        let api = APIController()
        let server = HTTPServer(port: 24_680, handler: api.route)
        do {
            try server.start()
            RunLoop.current.run()
        } catch {
            fputs("OBS Camera Dock server nelze spustit: \(error.localizedDescription)\n", stderr)
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
