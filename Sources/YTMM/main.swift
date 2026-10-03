import AppKit
import WebKit

let musicURL = URL(string: "https://music.youtube.com")!
// A named store keeps this app's Google login apart from Safari and every other app.
let storeID = UUID(uuidString: "5C1B6E2A-3F4D-4A8B-9E7C-2D1F0A6B8C3E")!

// YouTube's player <video>, or the first video if YouTube renames it.
let playerVideo = "(document.querySelector('video.html5-main-video') || document.querySelector('video'))"

// Runs in the page and tells the app when playback starts, pauses or changes song,
// and whether the lyrics are showing.
// The title and artist are read from the player bar, since the ones published for macOS can be shortened
// (e.g. "Zhong Shen Mei Li" for "終身美麗 - Zhong Shen Mei Li"). The published ones are the fallback,
// e.g. during ads, when the player bar has no title and its artist line says "Video will play after ad".
let playerScript = """
(() => {
    let last = '';
    // Watches an element for changes, moving on to its replacement if YouTube swaps it out.
    const watcher = options => {
        let watched = null;
        const observer = new MutationObserver(() => report());
        return element => {
            if (!element || element === watched) return;
            observer.disconnect();
            observer.observe(element, options);
            watched = element;
        };
    };
    const watchInfo = watcher({ childList: true, characterData: true, subtree: true });
    const watchLayout = watcher({ attributes: true, attributeFilter: ['player-page-open'] });
    const watchTabs = watcher({ attributes: true, attributeFilter: ['aria-selected'], subtree: true });
    const report = () => {
        const video = \(playerVideo);
        // Watch the song info, the now-playing view and its tabs themselves, so changes that come
        // without media events still get through.
        const info = document.querySelector('ytmusic-player-bar .content-info-wrapper');
        const layout = document.querySelector('ytmusic-app-layout');
        const tabs = document.querySelectorAll('ytmusic-player-page tp-yt-paper-tab.tab-header');
        watchInfo(info);
        watchLayout(layout);
        watchTabs(tabs[0]?.parentElement);
        const title = info?.querySelector('.title')?.textContent.trim();
        const published = navigator.mediaSession.metadata;
        // The artist line can go on with the album and year, or a video's views; keep what's before the first "•".
        const state = title
            ? { playing: !!video && !video.paused, title,
                artist: info.querySelector('.byline')?.textContent.split('•')[0].trim() || '' }
            : { playing: !!video && !video.paused, title: published?.title || '', artist: published?.artist || '' };
        // Lyrics is the second tab (by position, so any language works).
        state.lyrics = !!layout?.hasAttribute('player-page-open') && tabs[1]?.getAttribute('aria-selected') === 'true';
        const json = JSON.stringify(state);
        if (json !== last) { last = json; webkit.messageHandlers.player.postMessage(state); }
    };
    // Media events don't bubble, but a capturing listener on document still sees them.
    for (const type of ['play', 'playing', 'pause', 'loadeddata'])
        document.addEventListener(type, report, true);
})();
"""

// Lets the first click on the panel reach the page instead of only focusing the panel.
final class WebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// Same for the buttons in the panel's top strip, so one click works even before the panel has focus.
final class StripButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 720),
        styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
        backing: .buffered, defer: true)
    let menu = NSMenu()
    let pinButton = StripButton()
    let compactButton = StripButton()
    let lyricsButton = StripButton()
    lazy var store = WKWebsiteDataStore(forIdentifier: storeID)
    var webView: WKWebView?
    var openTimer: Timer?
    var closeTimer: Timer?
    var ticksOutside = 0
    var song = (playing: false, title: "", artist: "")
    var hasSong: Bool { !song.title.isEmpty }
    var scrollTotal: CGFloat = 0
    var scrollSkipped = false
    var lastWheelSkip: TimeInterval = 0

    // Created on first open, so the app stays small until it's used.
    func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        config.userContentController.addUserScript(
            WKUserScript(source: playerScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController.add(self, name: "player")
        // Google blocks sign-in from browsers it doesn't recognize, so identify as Safari.
        config.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        // macOS lets pages open windows on their own by default; require a click, so ads can't.
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WebView(frame: panel.contentLayoutRect, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.load(URLRequest(url: musicURL))
        panel.contentView!.addSubview(webView)
        return webView
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["showArtist": true])
        let button = statusItem.button!
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(iconClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
        updateStatus()

        // Scrolling on the icon changes songs. The icon lives in this app's own window,
        // so its scroll events reach this app even while another app is active.
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === statusItem.button?.window else { return event }
            scrolled(event)
            return nil
        }

        let artistItem = menu.addItem(withTitle: "Show Artist", action: #selector(toggleArtist), keyEquivalent: "")
        artistItem.target = self
        artistItem.state = UserDefaults.standard.bool(forKey: "showArtist") ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reload", action: #selector(reload), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Sign Out", action: #selector(signOut), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApp.terminate), keyEquivalent: "")

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.backgroundColor = .black
        // YouTube Music is always dark, so keep the panel's own controls dark to match.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(kind)?.isHidden = true
        }
        panel.setFrameAutosaveName("Panel")

        // Buttons in the panel's top strip: lyrics, and the toggles for compact player and pin (keeps the panel open).
        lyricsButton.isBordered = false
        lyricsButton.font = .systemFont(ofSize: 12, weight: .medium)
        lyricsButton.target = self
        lyricsButton.action = #selector(showLyrics)
        // Sized for the longer label, so the buttons beside it stay put when the label changes.
        lyricsButton.title = "Up next"
        let lyricsWidth = lyricsButton.fittingSize.width
        lyricsButton.widthAnchor.constraint(equalToConstant: lyricsWidth).isActive = true
        lyricsButton.title = "Lyrics"
        setUpStripButton(compactButton, "arrow.down.right.and.arrow.up.left", on: "arrow.up.left.and.arrow.down.right",
                         tip: "Compact player")
        compactButton.target = self
        compactButton.action = #selector(toggleCompact)
        compactButton.state = UserDefaults.standard.bool(forKey: "compact") ? .on : .off
        setUpStripButton(pinButton, "pin", on: "pin.fill", tip: "Keep the panel open")
        let strip = NSStackView(views: [lyricsButton, compactButton, pinButton])
        strip.spacing = 0
        strip.setCustomSpacing(8, after: lyricsButton)
        strip.frame.size = NSSize(width: 72 + lyricsWidth + 8, height: 28)
        let stripBar = NSTitlebarAccessoryViewController()
        stripBar.view = strip
        stripBar.layoutAttribute = .trailing
        panel.addTitlebarAccessoryViewController(stripBar)

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
        openTimer?.invalidate()
        openTimer = .scheduledTimer(
            timeInterval: 0.3, target: self, selector: #selector(showPanel), userInfo: nil, repeats: false)
    }

    @objc(mouseExited:) func mouseExited(with event: NSEvent) {
        openTimer?.invalidate()
    }

    @objc func iconClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem.menu = menu
            statusItem.button!.performClick(nil)
            statusItem.menu = nil
        } else if hasSong {
            // A click means play/pause, so don't also pop the panel open.
            openTimer?.invalidate()
            webView?.evaluateJavaScript("(v => { if (v) v.paused ? v.play() : v.pause() })(\(playerVideo))")
        } else {
            showPanel()
        }
    }

    // Scrolling down on the icon plays the next song, up the previous one, by pressing YouTube's
    // own buttons. A trackpad swipe sends many events (plus momentum), so each swipe skips one
    // song; a mouse wheel skips one per notch, at most every 0.4 s.
    func scrolled(_ event: NSEvent) {
        guard hasSong, event.momentumPhase == [] else { return }
        let delta: CGFloat
        if event.phase == [] {
            guard event.scrollingDeltaY != 0, event.timestamp - lastWheelSkip > 0.4 else { return }
            lastWheelSkip = event.timestamp
            delta = event.scrollingDeltaY
        } else {
            if event.phase == .began { scrollTotal = 0; scrollSkipped = false }
            scrollTotal += event.scrollingDeltaY
            guard !scrollSkipped, abs(scrollTotal) > 20 else { return }
            scrollSkipped = true
            delta = scrollTotal
        }
        // Negative means scrolling down, already adjusted for your scroll-direction setting.
        let button = delta < 0 ? "next" : "previous"
        webView?.evaluateJavaScript("document.querySelector('ytmusic-player-bar .\(button)-button button')?.click()")
    }

    // Updates the icon, title and Lyrics button whenever the page reports a change.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        // Links can take the panel to other sites; only YouTube Music may change the menu bar.
        guard message.frameInfo.securityOrigin.host == musicURL.host,
              let state = message.body as? [String: Any] else { return }
        song = (state["playing"] as? Bool ?? false, state["title"] as? String ?? "", state["artist"] as? String ?? "")
        updateStatus()
        // The label says what a press will do.
        lyricsButton.title = state["lyrics"] as? Bool == true ? "Up next" : "Lyrics"
    }

    // Shows the current song: the play or pause icon, then the title with the artist dimmed after it.
    // A long title is cut first; the artist keeps at least a third of the room.
    func updateStatus() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: song.playing || !hasSong ? "play.circle" : "pause.circle",
            accessibilityDescription: "YouTube Music")
        let font = button.font ?? .menuBarFont(ofSize: 0)
        guard hasSong, !song.artist.isEmpty, UserDefaults.standard.bool(forKey: "showArtist") else {
            button.title = fitted(song.title, font: font)
            return
        }
        let room = 220 - width(" · ", font)
        let artist = fitted(song.artist, font: font, maxWidth: max(room / 3, room - width(song.title, font)))
        let title = NSMutableAttributedString(
            string: fitted(song.title, font: font, maxWidth: room - width(artist, font)), attributes: [.font: font])
        title.append(NSAttributedString(
            string: " · " + artist, attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
        button.attributedTitle = title
    }

    @objc func toggleArtist(_ item: NSMenuItem) {
        item.state = item.state == .on ? .off : .on
        UserDefaults.standard.set(item.state == .on, forKey: "showArtist")
        updateStatus()
    }

    // Cuts text by width rather than characters, since wide (e.g. CJK) text could otherwise
    // make the item too wide for the menu bar, and macOS would hide it, icon and all.
    func fitted(_ text: String, font: NSFont, maxWidth: CGFloat = 150) -> String {
        guard width(text, font) > maxWidth else { return text }
        var cut = text
        while !cut.isEmpty && width(cut + "…", font) > maxWidth { cut.removeLast() }
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }

    func width(_ text: String, _ font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    @objc func showPanel() {
        openTimer?.invalidate()
        guard !panel.isVisible else { return }
        if webView == nil { webView = makeWebView() }
        place()
        panel.orderFrontRegardless()

        ticksOutside = 0
        closeTimer = .scheduledTimer(
            timeInterval: 0.25, target: self, selector: #selector(checkMouse), userInfo: nil, repeats: true)
    }

    // Hangs the panel from the menu bar under the icon, optionally at a new size, kept on screen.
    // When the menu bar auto-hides, visibleFrame reaches the top of the screen, so the icon's
    // own window marks where the menu bar ends.
    func place(size: NSSize? = nil) {
        guard let bar = statusItem.button?.window, let screen = bar.screen?.visibleFrame else { return }
        let top = min(bar.frame.minY, screen.maxY)
        var frame = panel.frame
        if let size { frame.size = size }
        frame.size.width = min(frame.width, screen.width)
        frame.size.height = min(frame.height, top - screen.minY)
        frame.origin.x = min(max(bar.frame.midX - frame.width / 2, screen.minX), screen.maxX - frame.width)
        frame.origin.y = top - frame.height
        panel.setFrame(frame, display: true)
    }

    func setUpStripButton(_ button: NSButton, _ symbol: String, on onSymbol: String, tip: String) {
        button.setButtonType(.toggle)
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        button.alternateImage = NSImage(systemSymbolName: onSymbol, accessibilityDescription: tip)
        button.toolTip = tip
    }

    // Shows YouTube's own lyrics: picks the Lyrics tab of the now-playing view, then opens the view
    // if it's closed. If the lyrics are already showing, goes back to Up next instead.
    // Tabs are found by position (Up next first, Lyrics second), so this works in every language.
    // For songs without lyrics YouTube disables the tab, and nothing happens.
    @objc func showLyrics() {
        webView?.evaluateJavaScript("""
            (tabs => {
                const showing = document.querySelector('ytmusic-app-layout')?.hasAttribute('player-page-open')
                    && tabs[1]?.getAttribute('aria-selected') === 'true';
                tabs[showing ? 0 : 1]?.click();
            })(document.querySelectorAll('ytmusic-player-page tp-yt-paper-tab.tab-header'))
            """)
        showNowPlaying(true)
    }

    // Compact mode: a small panel showing YouTube's own now-playing view, with its Up next list.
    // Each mode remembers its own size: the size you leave a mode at is what it comes back to.
    @objc func toggleCompact() {
        let compact = compactButton.state == .on
        let defaults = UserDefaults.standard
        defaults.set(NSStringFromSize(panel.frame.size), forKey: compact ? "fullSize" : "compactSize")
        defaults.set(compact, forKey: "compact")
        let saved = NSSizeFromString(defaults.string(forKey: compact ? "compactSize" : "fullSize") ?? "")
        place(size: saved != .zero ? saved : compact ? NSSize(width: 400, height: 680) : NSSize(width: 480, height: 720))
        // Give the page a moment to lay out at the new width before finding YouTube's controls.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in showNowPlaying(compact) }
    }

    // Opens or closes YouTube's now-playing view by clicking YouTube's own control for it:
    // the open/close toggle in the wide layout, or the mini player / minimize button in the narrow one.
    // The page keeps hidden copies of some controls, so a control counts only if it's what's
    // actually under its own center.
    func showNowPlaying(_ open: Bool) {
        guard let webView else { return }
        webView.evaluateJavaScript("""
            (open => {
                const layout = document.querySelector('ytmusic-app-layout');
                if (!layout || layout.hasAttribute('player-page-open') === open) return null;
                const targets = open
                    ? ['ytmusic-player-bar .toggle-player-page-button', 'ytmusic-player-bar .content-info-wrapper']
                    : ['ytmusic-player-page .collapse-button', 'ytmusic-player-bar .toggle-player-page-button'];
                for (const target of targets)
                    for (const element of document.querySelectorAll(target)) {
                        const r = element.getBoundingClientRect(), x = r.left + r.width / 2, y = r.top + r.height / 2;
                        const hit = document.elementFromPoint(x, y);
                        if (hit && element.contains(hit)) return [x, y];
                    }
                return null;
            })(\(open))
            """) { [self] result, _ in
            if let xy = result as? [Double], xy.count == 2 { click(webView, atPagePoint: NSPoint(x: xy[0], y: xy[1])) }
        }
    }

    // Delivers a real mouse click to a point on the page. YouTube opens its now-playing view only
    // for genuine clicks, which a script's click() isn't.
    func click(_ webView: WKWebView, atPagePoint point: NSPoint) {
        guard let window = webView.window else { return }
        let inView = NSPoint(x: point.x, y: webView.isFlipped ? point.y : webView.bounds.height - point.y)
        let location = webView.convert(inView, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return }
            type == .leftMouseDown ? webView.mouseDown(with: event) : webView.mouseUp(with: event)
        }
    }

    // Closes the panel once the mouse has been away from it and the icon for half a second,
    // unless it's pinned. The margin keeps it open while you grab an edge to resize.
    @objc func checkMouse() {
        let mouse = NSEvent.mouseLocation
        let near = panel.frame.insetBy(dx: -12, dy: -12).contains(mouse)
            || statusItem.button?.window?.frame.contains(mouse) == true
        ticksOutside = near || pinButton.state == .on ? 0 : ticksOutside + 1
        if ticksOutside >= 2 {
            closeTimer?.invalidate()
            panel.orderOut(nil)
        }
    }

    // Always goes back to YouTube Music, even if a link took the panel elsewhere.
    @objc func reload() {
        webView?.load(URLRequest(url: musicURL))
    }

    // Clears the store directly, so this works without loading the page first.
    @objc func signOut() {
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [self] in
            webView?.load(URLRequest(url: musicURL))
        }
    }

    // A new page (reload, sign-in, sign-out) starts with nothing playing.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        song = (false, "", "")
        updateStatus()
        lyricsButton.title = "Lyrics"
    }

    // If macOS kills the page's process, e.g. under memory pressure, start it again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.load(URLRequest(url: musicURL))
    }

    // Links that want a new window open in your default browser; other schemes are ignored,
    // so a page can't launch apps or files through this.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["http", "https"].contains(url.scheme?.lowercased()) {
            NSWorkspace.shared.open(url)
        }
        return nil
    }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
