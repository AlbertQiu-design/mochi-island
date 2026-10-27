import AppKit
import MochiCore
import ServiceManagement
import WebKit

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class ClickThroughWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class GlassPlate {
    let window: NSWindow
    let effect: NSGlassEffectView
    let label: NSTextField
    private weak var panel: NSPanel?
    private var coversContent = false

    init(panel: NSPanel) {
        self.panel = panel
        let effect = NSGlassEffectView(frame: .zero)
        effect.style = .regular
        effect.tintColor = nil
        if #available(macOS 27.0, *) {
            effect.effectIsInteractive = true
        }
        let label = NSTextField(wrappingLabelWithString: "")
        label.alignment = .center
        label.font = NSFont(name: "ChalkboardSE-Regular", size: 15) ?? .systemFont(ofSize: 15)
        label.textColor = NSColor(srgbRed: 0.141, green: 0.122, blue: 0.110, alpha: 1)
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.maximumNumberOfLines = 4
        label.lineBreakMode = .byWordWrapping
        let host = NSView(frame: .zero)
        host.autoresizingMask = [.width, .height]
        host.addSubview(label)
        effect.contentView = host
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = panel.level
        window.collectionBehavior = panel.collectionBehavior
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = effect
        panel.addChildWindow(window, ordered: .below)
        self.window = window
        self.effect = effect
        self.label = label
    }

    func update(frame: NSRect, radius: CGFloat, alpha: CGFloat, text: String, cover: Bool, textColor: NSColor) {
        if coversContent != cover, let panel {
            panel.removeChildWindow(window)
            panel.addChildWindow(window, ordered: cover ? .above : .below)
            coversContent = cover
        }
        window.setFrame(frame, display: true)
        window.alphaValue = alpha
        effect.cornerRadius = radius
        effect.tintColor = nil
        label.isHidden = !cover
        label.stringValue = text
        label.textColor = textColor
        layoutLabel()
    }

    private func layoutLabel() {
        let bounds = NSRect(origin: .zero, size: window.frame.size)
        guard bounds.width > 1, bounds.height > 1, let host = effect.contentView else { return }
        host.frame = bounds
        let inset = bounds.insetBy(dx: 16, dy: 6)
        label.preferredMaxLayoutWidth = inset.width
        let measured = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: inset.width, height: 400)) ?? inset.size
        let height = min(inset.height, max(1, measured.height))
        label.frame = NSRect(
            x: inset.minX,
            y: inset.minY + (inset.height - height) / 2,
            width: inset.width,
            height: height
        )
    }
}

@MainActor
final class IslandController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private let panel = IslandPanel(
        contentRect: NSRect(origin: .zero, size: NSSize(width: 800, height: 600)),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private var webView: ClickThroughWebView!
    private let session = AppSession()
    private let taskWatch = TaskFileWatch(
        fileURL: AppConfig.cursorDirectory.appendingPathComponent("mochi-island-tasks.json")
    )
    private var taskStamp = ""
    private var reloadTries = 0
    private var glassPlates: [GlassPlate] = []
    private var hotRects: [NSRect] = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private let capsule = CapsuleChrome()

    func start() {
        configurePanel()
        configureWebView()
        applyFrame()
        configureCapsule()
        startMousePassthrough()
        panel.orderFrontRegardless()
        loadPage()
        taskWatch.start { [weak self] in
            DispatchQueue.main.async {
                self?.deliverTasksIfChanged()
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.isRestorable = false
        panel.animationBehavior = .none
        panel.title = "Mochi Island"
    }

    private func configureWebView() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "island")
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = ClickThroughWebView(frame: panel.contentView!.bounds, configuration: config)
        view.navigationDelegate = self
        view.autoresizingMask = [.width, .height]
        view.setValue(false, forKey: "drawsBackground")
        view.clipsToBounds = false
        if #available(macOS 12.0, *) {
            view.underPageBackgroundColor = .clear
        }
        panel.contentView?.clipsToBounds = false
        panel.contentView = view
        webView = view
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "island" else { return }
        let body = message.body as? [String: Any] ?? [:]
        let action = body["action"] as? String ?? ""
        let requestID = body["rpc"] as? String ?? ""
        switch action {
        case "savePrefs":
            session.replacePrefs(body)
            retintGlass()
            refreshCapsule()
        case "hotRects":
            hotRects = Self.parseRects(body["rects"], windowHeight: panel.frame.height)
            syncMousePassthrough()
        case "glass":
            syncGlass(body["rects"])
        case "getState":
            reply(requestID, session.statePayload())
        case "play":
            reply(requestID, session.play())
        case "getTasks":
            reply(requestID, session.tasksPayload())
        case "cursorLink":
            reply(requestID, session.linkPayload(
                action: body["linkAction"] as? String ?? "",
                acknowledged: body["acknowledged"] as? Bool ?? false
            ))
        case "cursorChoice":
            reply(requestID, session.choicePayload(body))
        case "openAgent":
            reply(requestID, session.openAgent(
                source: body["source"] as? String ?? "",
                taskID: body["id"] as? String ?? ""
            ))
        case "setScan":
            session.setScanTranscripts(body["enabled"] as? Bool ?? false)
            reply(requestID, ["ok": true, "scanTranscripts": session.currentPrefs.scanTranscripts])
        case "createSlot":
            let created = session.createSlot(source: body["source"] as? String ?? "")
            refreshCapsule()
            reply(requestID, created)
        default:
            break
        }
    }

    private func configureCapsule() {
        capsule.attach(to: panel)
        capsule.onSelect = { [weak self] id, open in
            guard let self else { return }
            _ = self.session.selectSlot(id)
            self.refreshCapsule()
            self.tellPage(
                "window.applyCapsuleEvent && window.applyCapsuleEvent({kind:'select',id:\(Self.jsonString(id)),open:\(open ? "true" : "false")});"
            )
        }
        capsule.onCreate = { [weak self] source in
            guard let self else { return }
            let created = self.session.createSlot(source: source)
            self.refreshCapsule()
            self.tellPage(
                "window.applyCapsuleEvent && window.applyCapsuleEvent({kind:'created',selected:\(Self.jsonString(created["selected"] as? String ?? "")),slots:\(Self.jsonString(created["slots"] ?? []))});"
            )
        }
        capsule.onSettings = { [weak self] in
            self?.tellPage("window.applyCapsuleEvent && window.applyCapsuleEvent({kind:'settings'});")
        }
        refreshCapsule()
    }

    private func refreshCapsule() {
        let state = session.statePayload()
        let tasks = session.tasksPayload()
        capsule.sync(
            slots: state["slots"] as? [[String: Any]] ?? [],
            selected: state["selected"] as? String ?? "",
            tasks: tasks,
            dock: session.currentPrefs.dock
        )
        publishCapsule()
    }

    private func publishCapsule() {
        let payload = Self.jsonString(capsule.chromePayload(in: panel))
        tellPage("window.applyCapsuleChrome && window.applyCapsuleChrome(\(payload));")
    }

    private func tellPage(_ script: String) {
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    private func reply(_ id: String, _ object: Any) {
        guard !id.isEmpty, JSONSerialization.isValidJSONObject(object) else { return }
        let payload = Self.jsonString(object)
        let request = (try? JSONEncoder().encode(id)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        webView.evaluateJavaScript(
            "window.mochiReply && window.mochiReply(\(request), \(payload));",
            completionHandler: nil
        )
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        retryLoad()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        retryLoad()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        injectPageState()
        deliverTasks()
    }

    private func deliverTasksIfChanged() {
        guard taskWatch.stamp() != taskStamp else { return }
        deliverTasks()
    }

    private func deliverTasks() {
        taskStamp = taskWatch.stamp()
        let state = Self.jsonString(session.statePayload())
        let tasks = Self.jsonString(session.tasksPayload())
        webView.evaluateJavaScript(
            "window.pushTasks && window.pushTasks(\(tasks), \(state));",
            completionHandler: nil
        )
        refreshCapsule()
    }

    private func injectPageState() {
        let layout = Self.screenLayoutJSON()
        let payload = Self.jsonString(session.currentPrefs.dictionary)
        webView.evaluateJavaScript(
            "window.applyScreenLayout && window.applyScreenLayout(\(layout)); window.applyPrefs && window.applyPrefs(\(payload));",
            completionHandler: nil
        )
        refreshCapsule()
    }

    private func retryLoad() {
        guard reloadTries < 3 else { return }
        reloadTries += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.loadPage()
        }
    }

    private func loadPage() {
        guard let html = Bundle.main.url(forResource: "island", withExtension: "html", subdirectory: "Web") else {
            return
        }
        webView.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
    }

    @objc private func screenChanged() {
        applyFrame()
        injectPageState()
        refreshCapsule()
    }

    private func applyFrame() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        var frame = screen.frame
        // Exact screen.frame can be treated as macOS fullscreen and disappear from the desktop.
        frame.origin.y += 1
        frame.size.height -= 1
        panel.setFrame(frame, display: true)
        if webView != nil {
            webView.frame = panel.contentView?.bounds ?? NSRect(origin: .zero, size: frame.size)
        }
    }

    private func startMousePassthrough() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged]) { [weak self] event in
            self?.syncMousePassthrough()
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.syncMousePassthrough()
        }
        syncMousePassthrough()
    }

    private func syncMousePassthrough() {
        if hotRects.isEmpty {
            panel.ignoresMouseEvents = true
            return
        }
        let mouse = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let hit = hotRects.contains { $0.insetBy(dx: -10, dy: -10).contains(mouse) }
        panel.ignoresMouseEvents = !hit
    }

    private static func parseRects(_ value: Any?, windowHeight: CGFloat) -> [NSRect] {
        var items: [[String: Any]] = []
        if let list = value as? [[String: Any]] {
            items = list
        } else if let list = value as? [Any] {
            items = list.compactMap { $0 as? [String: Any] }
        } else if let text = value as? String,
                  let data = text.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            items = parsed
        }
        return items.compactMap { item in
            let x = cgFloat(item["x"])
            let y = cgFloat(item["y"])
            let w = cgFloat(item["w"])
            let h = cgFloat(item["h"])
            guard w > 1, h > 1 else { return nil }
            return NSRect(x: x, y: windowHeight - y - h, width: w, height: h)
        }
    }

    private func syncGlass(_ value: Any?) {
        let windowHeight = panel.frame.height
        let plates = Self.parseGlass(value, windowHeight: windowHeight)
        while glassPlates.count < plates.count {
            glassPlates.append(GlassPlate(panel: panel))
        }
        let color = Self.rgbColor(session.currentPrefs.text)
        for (index, plate) in plates.enumerated() {
            let screenRect = NSRect(
                x: panel.frame.minX + plate.rect.minX,
                y: panel.frame.minY + plate.rect.minY,
                width: plate.rect.width,
                height: plate.rect.height
            )
            glassPlates[index].update(
                frame: screenRect,
                radius: plate.radius,
                alpha: plate.alpha,
                text: plate.text,
                cover: plate.cover,
                textColor: color
            )
        }
        if glassPlates.count > plates.count {
            for plate in glassPlates[plates.count...] {
                plate.window.alphaValue = 0
            }
        }
    }

    private func retintGlass() {
        let color = Self.rgbColor(session.currentPrefs.text)
        for plate in glassPlates where plate.window.alphaValue > 0 {
            plate.label.textColor = color
        }
    }

    private static func parseGlass(_ value: Any?, windowHeight: CGFloat) -> [(rect: NSRect, radius: CGFloat, alpha: CGFloat, text: String, cover: Bool)] {
        var items: [[String: Any]] = []
        if let list = value as? [[String: Any]] {
            items = list
        } else if let text = value as? String,
                  let data = text.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            items = parsed
        }
        return items.compactMap { item in
            let x = cgFloat(item["x"])
            let y = cgFloat(item["y"])
            let w = cgFloat(item["w"])
            let h = cgFloat(item["h"])
            guard w > 1, h > 1 else { return nil }
            let cover = false
            var radius = max(8, cgFloat(item["r"]))
            if h <= 64 {
                radius = h / 2
            } else {
                radius = min(radius, 16)
            }
            var alpha = cgFloat(item["a"])
            if alpha <= 0 { alpha = 1 }
            alpha = min(1, max(0, alpha))
            let text = item["text"] as? String ?? ""
            return (NSRect(x: x, y: windowHeight - y - h, width: w, height: h), radius, alpha, text, cover)
        }
    }

    private static func rgbColor(_ hex: String) -> NSColor {
        let raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        var value: UInt64 = 0
        let body = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        Scanner(string: body).scanHexInt64(&value)
        let red = CGFloat((value >> 16) & 0xff) / 255
        let green = CGFloat((value >> 8) & 0xff) / 255
        let blue = CGFloat(value & 0xff) / 255
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    private static func screenLayoutJSON() -> String {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.frame
        var notchLeft = frame.width / 2 - 110
        var notchRight = frame.width / 2 + 110
        if #available(macOS 12.0, *) {
            if let left = screen.auxiliaryTopLeftArea,
               let right = screen.auxiliaryTopRightArea,
               left.width > 1, right.width > 1, right.minX > left.maxX {
                notchLeft = left.maxX - frame.minX
                notchRight = right.minX - frame.minX
            }
        }
        return "{\"width\":\(frame.width),\"height\":\(frame.height),\"notchLeft\":\(notchLeft),\"notchRight\":\(notchRight)}"
    }

    private static func cgFloat(_ value: Any?) -> CGFloat {
        if let number = value as? NSNumber { return CGFloat(truncating: number) }
        if let number = value as? Double { return CGFloat(number) }
        if let number = value as? Int { return CGFloat(number) }
        return 0
    }

    private static func jsonString(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}

@MainActor
final class Runtime: NSObject, NSApplicationDelegate {
    static let shared = Runtime()
    let island = IslandController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Self.claimSingleInstance() else {
            NSApp.terminate(nil)
            return
        }
        try? SMAppService.mainApp.register()
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        island.start()
    }

    private static func claimSingleInstance() -> Bool {
        let identifier = Bundle.main.bundleIdentifier ?? AppConfig.bundleID
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            existing.activate(options: [.activateAllWindows])
            return false
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
enum MochiIsland {
    static func main() {
        if CommandLine.arguments.contains("--measure-latency") {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            app.delegate = LatencyHarness.shared
            app.run()
            return
        }
        let app = NSApplication.shared
        app.delegate = Runtime.shared
        app.setActivationPolicy(.regular)
        app.run()
    }
}
