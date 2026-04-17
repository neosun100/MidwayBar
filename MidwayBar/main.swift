import AppKit
import Foundation
import ServiceManagement

// MARK: - Midway Session

struct MidwaySession {
    let user: String
    let authMethod: String
    let authTime: TimeInterval
    let expiresAt: TimeInterval

    var remaining: TimeInterval { max(expiresAt - Date().timeIntervalSince1970, 0) }
    var total: TimeInterval { expiresAt - authTime }
    var percent: Int { total > 0 ? min(Int(remaining / total * 100), 100) : 0 }
    var expired: Bool { remaining <= 0 }

    var remainingShort: String {
        let h = Int(remaining) / 3600
        let m = (Int(remaining) % 3600) / 60
        return "\(h)h\(m)m"
    }

    var statusColor: NSColor {
        if expired { return .systemRed }
        if percent > 50 { return .systemGreen }
        if percent > 20 { return .systemYellow }
        return .systemRed
    }

    static func fetch() -> MidwaySession? {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        proc.arguments = ["-sf", "-b", NSHomeDirectory() + "/.midway/cookie",
                          "https://midway-auth.amazon.com/api/session-status"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["authenticated"] as? Bool == true else { return nil }

        return MidwaySession(
            user: json["user_name"] as? String ?? "?",
            authMethod: (json["amr"] as? [String])?.joined(separator: " + ") ?? "",
            authTime: json["auth_time"] as? TimeInterval ?? 0,
            expiresAt: json["expires_at"] as? TimeInterval ?? 0
        )
    }
}

// MARK: - Two-Line Status Bar View

class StatusBarView: NSView {
    var topText: String = "MW" { didSet { needsDisplay = true } }
    var bottomText: String = "--" { didSet { needsDisplay = true } }
    var color: NSColor = .systemGray { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: 32, height: 22) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let ps = NSMutableParagraphStyle()
        ps.alignment = .center

        let top: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            .paragraphStyle: ps
        ]
        let bot: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: color,
            .paragraphStyle: ps
        ]
        (topText as NSString).draw(in: NSRect(x: 0, y: 10, width: bounds.width, height: 12), withAttributes: top)
        (bottomText as NSString).draw(in: NSRect(x: 0, y: -1, width: bounds.width, height: 12), withAttributes: bot)
    }
}

// MARK: - Local HTTP API Server

class StatusAPIServer {
    let port: UInt16 = 19527
    var serverSocket: Int32 = -1
    var running = false

    func start() {
        guard !running else { return }
        running = true
        DispatchQueue.global(qos: .background).async { [self] in
            serverSocket = socket(AF_INET, SOCK_STREAM, 0)
            guard serverSocket >= 0 else { return }

            var opt: Int32 = 1
            setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            let bindResult = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            guard bindResult == 0 else { NSLog("API: bind failed on port \(port)"); return }
            guard listen(serverSocket, 5) == 0 else { return }
            NSLog("API: listening on http://127.0.0.1:\(port)/status")

            while running {
                let client = accept(serverSocket, nil, nil)
                guard client >= 0 else { continue }
                DispatchQueue.global().async { self.handleClient(client) }
            }
        }
    }

    func stop() {
        running = false
        if serverSocket >= 0 { close(serverSocket); serverSocket = -1 }
        NSLog("API: stopped")
    }

    func handleClient(_ client: Int32) {
        defer { close(client) }

        var buf = [UInt8](repeating: 0, count: 1024)
        recv(client, &buf, buf.count, 0)
        let req = String(bytes: buf, encoding: .utf8) ?? ""

        // Only respond to GET /status
        guard req.hasPrefix("GET /status") || req.hasPrefix("GET / ") else {
            let r = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
            send(client, r, r.utf8.count, 0)
            return
        }

        let session = MidwaySession.fetch()
        let json: String
        if let s = session {
            json = """
            {"authenticated":true,"user":"\(s.user)","auth_method":"\(s.authMethod)","percent":\(s.percent),"remaining_seconds":\(Int(s.remaining)),"remaining":"\(s.remainingShort)","expires_at":\(Int(s.expiresAt)),"status":"\(s.percent > 50 ? "healthy" : s.percent > 20 ? "warning" : "critical")"}
            """
        } else {
            json = """
            {"authenticated":false,"user":null,"percent":0,"remaining_seconds":0,"remaining":"0h0m","status":"expired"}
            """
        }

        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: \(json.utf8.count)\r\n\r\n\(json)"
        send(client, response, response.utf8.count, 0)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var view: StatusBarView!
    var timer: Timer?
    var lastSession: MidwaySession?
    let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    let version = "1.4.0"
    let apiServer = StatusAPIServer()

    // Settings keys
    let launchAtLoginKey = "launchAtLogin"
    let apiEnabledKey = "apiEnabled"

    var launchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: launchAtLoginKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: launchAtLoginKey)
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("Failed to update login item: \(error)")
                }
            }
        }
    }

    var apiEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: apiEnabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: apiEnabledKey)
            if newValue {
                apiServer.start()
            } else {
                apiServer.stop()
            }
        }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: 32)
        view = StatusBarView(frame: NSRect(x: 0, y: 0, width: 32, height: 22))
        statusItem.button?.addSubview(view)
        statusItem.button?.frame = view.frame
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        if apiEnabled { apiServer.start() }
    }

    func refresh() {
        DispatchQueue.global().async {
            let s = MidwaySession.fetch()
            DispatchQueue.main.async { [self] in
                lastSession = s
                if let s {
                    view.topText = "MW"
                    view.bottomText = "\(s.percent)%"
                    view.color = s.statusColor
                } else {
                    view.topText = "MW"
                    view.bottomText = "N/A"
                    view.color = .systemRed
                }
                statusItem.menu = buildMenu(s)
            }
        }
    }

    func buildMenu(_ s: MidwaySession?) -> NSMenu {
        let m = NSMenu()

        // Session info
        if let s {
            let ico = s.percent > 50 ? "🟢" : s.percent > 20 ? "🟡" : "🔴"
            add(m, "\(ico) Midway — \(s.percent)%")
            m.addItem(.separator())
            add(m, "  User:      \(s.user)")
            add(m, "  Auth:      \(s.authMethod)")
            add(m, "  Login:     \(fmt.string(from: Date(timeIntervalSince1970: s.authTime)))")
            add(m, "  Expires:   \(fmt.string(from: Date(timeIntervalSince1970: s.expiresAt)))")
            add(m, "  Left:      \(s.remainingShort) (\(s.percent)%)")
            let f = s.percent * 20 / 100
            add(m, "  [\(String(repeating: "█", count: f))\(String(repeating: "░", count: 20 - f))]")
        } else {
            add(m, "🔴 Not authenticated")
            add(m, "  Run mwinit -f -s -o to authenticate")
        }

        m.addItem(.separator())

        // Actions
        let refresh = NSMenuItem(title: "↻ Refresh Now", action: #selector(doRefresh), keyEquivalent: "r")
        refresh.target = self
        m.addItem(refresh)

        let mwinit = NSMenuItem(title: "⌨ Run mwinit -f -s -o", action: #selector(doMwinit), keyEquivalent: "m")
        mwinit.target = self
        m.addItem(mwinit)

        m.addItem(.separator())

        // Settings
        let settingsHeader = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsHeader.isEnabled = false
        m.addItem(settingsHeader)

        let loginItem = NSMenuItem(title: "  Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "l")
        loginItem.target = self
        loginItem.state = launchAtLogin ? .on : .off
        m.addItem(loginItem)

        let apiItem = NSMenuItem(title: "  HTTP API (:19527)", action: #selector(toggleAPI), keyEquivalent: "a")
        apiItem.target = self
        apiItem.state = apiEnabled ? .on : .off
        m.addItem(apiItem)

        m.addItem(.separator())

        // About & Quit
        add(m, "MidwayBar v\(version)")

        let quit = NSMenuItem(title: "Quit MidwayBar", action: #selector(doQuit), keyEquivalent: "q")
        quit.target = self
        m.addItem(quit)

        return m
    }

    func add(_ m: NSMenu, _ t: String) {
        let i = NSMenuItem(title: t, action: nil, keyEquivalent: "")
        i.isEnabled = false
        m.addItem(i)
    }

    @objc func doRefresh() { refresh() }

    @objc func doMwinit() {
        // Open Terminal and run mwinit
        let script = "tell application \"Terminal\" to do script \"mwinit -f -s -o\""
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    @objc func toggleLaunchAtLogin() {
        launchAtLogin = !launchAtLogin
    }

    @objc func toggleAPI() {
        apiEnabled = !apiEnabled
    }

    @objc func doQuit() { NSApp.terminate(nil) }
}

// MARK: - Main
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let d = AppDelegate()
app.delegate = d
app.run()
