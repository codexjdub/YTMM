import AppKit
import WebKit

let musicURL = URL(string: "https://music.youtube.com")!
// A named store keeps this app's Google login apart from Safari and every other app.
let storeID = UUID(uuidString: "5C1B6E2A-3F4D-4A8B-9E7C-2D1F0A6B8C3E")!

// Lets the first click on the panel reach the page instead of only focusing the panel.
final class WebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 720),
        styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
        backing: .buffered, defer: true)
    let menu = NSMenu()
    var openTimer: Timer?
    var closeTimer: Timer?
    var ticksOutside = 0

    // Created on first open, so the app stays small until it's used.
    lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeID)
        // Google blocks sign-in from browsers it doesn't recognize, so identify as Safari.
        config.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        let webView = WebView(frame: panel.contentLayoutRect, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.uiDelegate = self
        webView.load(URLRequest(url: musicURL))
        panel.contentView!.addSubview(webView)
        return webView
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let button = statusItem.button!
        button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "YouTube Music")
        button.target = self
        button.action = #selector(iconClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))

        menu.addItem(withTitle: "Reload", action: #selector(reload), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Sign Out", action: #selector(signOut), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApp.terminate), keyEquivalent: "")

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.backgroundColor = .black
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(kind)?.isHidden = true
        }
        panel.setFrameAutosaveName("Panel")

        // Without an Edit menu, ⌘X/⌘C/⌘V/⌘A never reach the page.
        let edit = NSMenu()
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll), keyEquivalent: "a")
        NSApp.mainMenu = NSMenu()
        NSApp.mainMenu!.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
    }

    // Hovering the icon opens the panel after a short pause.
    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) {
        guard !panel.isVisible else { return }
        openTimer = .scheduledTimer(
            timeInterval: 0.3, target: self, selector: #selector(showPanel), userInfo: nil, repeats: false)
    }

    @objc(mouseExited:) func mouseExited(with event: NSEvent) {
        openTimer?.invalidate()
    }

    @objc func iconClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = menu
            statusItem.button!.performClick(nil)
            statusItem.menu = nil
        } else {
            showPanel()
        }
    }

    @objc func showPanel() {
        openTimer?.invalidate()
        guard !panel.isVisible, let bar = statusItem.button?.window,
              let screen = bar.screen?.visibleFrame else { return }
        _ = webView // first open loads the page

        var frame = panel.frame
        frame.size.width = min(frame.width, screen.width)
        frame.size.height = min(frame.height, screen.height)
        frame.origin.x = min(max(bar.frame.midX - frame.width / 2, screen.minX), screen.maxX - frame.width)
        frame.origin.y = screen.maxY - frame.height
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()

        ticksOutside = 0
        closeTimer = .scheduledTimer(
            timeInterval: 0.25, target: self, selector: #selector(checkMouse), userInfo: nil, repeats: true)
    }

    // Closes the panel once the mouse has been away from it and the icon for half a second.
    // The margin keeps it open while you grab an edge to resize.
    @objc func checkMouse() {
        let mouse = NSEvent.mouseLocation
        let near = panel.frame.insetBy(dx: -12, dy: -12).contains(mouse)
            || statusItem.button?.window?.frame.contains(mouse) == true
        ticksOutside = near ? 0 : ticksOutside + 1
        if ticksOutside >= 2 {
            closeTimer?.invalidate()
            panel.orderOut(nil)
        }
    }

    @objc func reload() {
        webView.reload()
    }

    @objc func signOut() {
        webView.configuration.websiteDataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast
        ) { [self] in
            webView.load(URLRequest(url: musicURL))
        }
    }

    // Links that want a new window open in your default browser.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
        return nil
    }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
