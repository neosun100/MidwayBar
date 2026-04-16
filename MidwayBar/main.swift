import AppKit
import Foundation

// MARK: - Midway Session Model

struct MidwaySession {
    let user: String
    let authMethod: String
    let loginTime: Date
    let expiresAt: Date
    let authenticated: Bool

    var remaining: TimeInterval { max(expiresAt.timeIntervalSince(Date()), 0) }
    var total: TimeInterval { expiresAt.timeIntervalSince(loginTime) }
    var percent: Int { total > 0 ? Int(remaining / total * 100) : 0 }
    var expired: Bool { remaining <= 0 }

    var remainingText: String {
        let h = Int(remaining) / 3600
        let m = (Int(remaining) % 3600) / 60
        return "\(h)h \(m)m"
    }

    var statusEmoji: String {
        if expired { return "🔴" }
        if percent > 50 { return "🟢" }
        if percent > 20 { return "🟡" }
        return "🔴"
    }

    var menuBarTitle: String {
        if expired { return "🔐 Expired" }
        return "🔐 \(percent)%"
    }
}

// MARK: - Midway API Client

class MidwayClient {
    private let url = URL(string: "https://midway-auth.amazon.com/api/session-status")!
    private let cookiePath = NSHomeDirectory() + "/.midway/cookie"

    func fetch() -> MidwaySession? {
        loadCookies()
        let sem = DispatchSemaphore(value: 0)
        var session: MidwaySession?

        var req = URLRequest(url: url, timeoutInterval: 5)
        req.httpMethod = "GET"

        URLSession.shared.dataTask(with: req) { data, _, _ in
            defer { sem.signal() }
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["authenticated"] as? Bool == true else { return }

            let user = json["user_name"] as? String ?? "unknown"
            let expiresEpoch = json["expires_at"] as? TimeInterval ?? 0
            let authEpoch = json["auth_time"] as? TimeInterval ?? 0
            let amr = (json["amr"] as? [String])?.map { $0.replacingOccurrences(of: "amr:", with: "") }.joined(separator: " + ") ?? ""

            session = MidwaySession(
                user: user, authMethod: amr,
                loginTime: Date(timeIntervalSince1970: authEpoch),
                expiresAt: Date(timeIntervalSince1970: expiresEpoch),
                authenticated: true
            )
        }.resume()

        sem.wait()
        return session
    }

    private func loadCookies() {
        guard let content = try? String(contentsOfFile: cookiePath, encoding: .utf8) else { return }
        let storage = HTTPCookieStorage.shared
        for line in content.components(separatedBy: "\n") {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.components(separatedBy: "\t")
            if parts.count >= 7 {
                let props: [HTTPCookiePropertyKey: Any] = [
                    .domain: parts[0], .path: parts[2],
                    .name: parts[5], .value: parts[6],
                    .secure: parts[3] == "TRUE" ? "TRUE" : "FALSE",
                    .expires: Date(timeIntervalSince1970: Double(parts[4]) ?? 0)
                ]
                if let cookie = HTTPCookie(properties: props) { storage.setCookie(cookie) }
            }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private let client = MidwayClient()
    private var lastSession: MidwaySession?
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        DispatchQueue.global().async { [weak self] in
            let session = self?.client.fetch()
            DispatchQueue.main.async {
                self?.lastSession = session
                self?.updateUI(session)
            }
        }
    }

    private func updateUI(_ session: MidwaySession?) {
        let title = session?.menuBarTitle ?? "🔐 ?"
        statusItem.button?.title = title
        statusItem.menu = buildMenu(session)
    }

    private func buildMenu(_ session: MidwaySession?) -> NSMenu {
        let menu = NSMenu()

        if let s = session {
            let header = NSMenuItem(title: "\(s.statusEmoji) Midway Session", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(NSMenuItem.separator())

            let items: [(String, String)] = [
                ("User", s.user),
                ("Auth", s.authMethod),
                ("Login", formatter.string(from: s.loginTime)),
                ("Expires", formatter.string(from: s.expiresAt)),
                ("Remaining", "\(s.remainingText) (\(s.percent)%)"),
            ]
            for (label, value) in items {
                let item = NSMenuItem(title: "  \(label):  \(value)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }

            // Progress bar text
            let barLen = 20
            let filled = s.percent * barLen / 100
            let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: barLen - filled)
            let barItem = NSMenuItem(title: "  [\(bar)]", action: nil, keyEquivalent: "")
            barItem.isEnabled = false
            menu.addItem(barItem)
        } else {
            let item = NSMenuItem(title: "🔴 Not authenticated", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "↻ Refresh", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let mwinitItem = NSMenuItem(title: "⌨ Run mwinit -s -o", action: #selector(runMwinit), keyEquivalent: "m")
        mwinitItem.target = self
        menu.addItem(mwinitItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit MidwayBar", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func refreshClicked() { refresh() }

    @objc private func runMwinit() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Terminal", "--args", "-e", "mwinit -s -o"]
        try? task.run()
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
