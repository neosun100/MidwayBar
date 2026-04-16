import AppKit
import Foundation

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

        let user = json["user_name"] as? String ?? "?"
        let exp = json["expires_at"] as? TimeInterval ?? 0
        let auth = json["auth_time"] as? TimeInterval ?? 0
        let amr = (json["amr"] as? [String])?.joined(separator: " + ") ?? ""

        return MidwaySession(user: user, authMethod: amr, authTime: auth, expiresAt: exp)
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

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var view: StatusBarView!
    var timer: Timer?
    let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: 32)
        view = StatusBarView(frame: NSRect(x: 0, y: 0, width: 32, height: 22))
        statusItem.button?.addSubview(view)
        statusItem.button?.frame = view.frame
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        DispatchQueue.global().async {
            let s = MidwaySession.fetch()
            DispatchQueue.main.async { [self] in
                if let s {
                    view.topText = "MW"
                    view.bottomText = "\(s.percent)%"
                    view.color = s.statusColor
                    statusItem.menu = menu(s)
                } else {
                    view.topText = "MW"
                    view.bottomText = "N/A"
                    view.color = .systemRed
                    statusItem.menu = menu(nil)
                }
            }
        }
    }

    func menu(_ s: MidwaySession?) -> NSMenu {
        let m = NSMenu()
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
        }
        m.addItem(.separator())
        let r = NSMenuItem(title: "↻ Refresh", action: #selector(doRefresh), keyEquivalent: "r"); r.target = self; m.addItem(r)
        let w = NSMenuItem(title: "⌨ mwinit -f -s -o", action: #selector(doMwinit), keyEquivalent: "m"); w.target = self; m.addItem(w)
        m.addItem(.separator())
        let q = NSMenuItem(title: "Quit", action: #selector(doQuit), keyEquivalent: "q"); q.target = self; m.addItem(q)
        return m
    }

    func add(_ m: NSMenu, _ t: String) { let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false; m.addItem(i) }
    @objc func doRefresh() { refresh() }
    @objc func doMwinit() { Process.launchedProcess(launchPath: "/usr/bin/open", arguments: ["-a", "Terminal"]) }
    @objc func doQuit() { NSApp.terminate(nil) }
}

// MARK: - Main
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let d = AppDelegate()
app.delegate = d
app.run()
