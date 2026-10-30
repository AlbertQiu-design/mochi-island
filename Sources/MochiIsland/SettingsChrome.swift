import AppKit
import MochiCore
import ServiceManagement
import SwiftUI

enum SettingsTab: Int, Hashable, CaseIterable {
    case general
    case kitten
    case sound
    case agents

    var title: String {
        switch self {
        case .general: return "General"
        case .kitten: return "Kitten"
        case .sound: return "Sound"
        case .agents: return "Agents"
        }
    }
}

/// Icons the plus picker is allowed to show. Settings writes it; the bubble reads it.
final class PickerMenu: ObservableObject {
    static let shared = PickerMenu()
    @Published private(set) var sources: [String] = IslandPrefs.pickerOrder

    func apply(_ prefs: IslandPrefs) {
        let next = prefs.pickerSources
        if next != sources {
            sources = next
        }
    }
}

final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

enum SettingsChromeMetrics {
    static let titleRow: CGFloat = 28
}

@MainActor
final class SettingsChrome: NSObject, NSWindowDelegate {
    static let width: CGFloat = AppConfig.settingsWidth
    static let height: CGFloat = 540
    static let gap: CGFloat = 8
    static let titleRow: CGFloat = SettingsChromeMetrics.titleRow
    static let sounds = IslandPrefs.soundIDs

    let panel: SettingsPanel
    private let model: SettingsModel
    private let hosting: NSHostingView<SettingsRoot>
    private weak var host: NSWindow?

    var onPrefs: (([String: Any]) -> Void)? {
        didSet { model.onPrefs = onPrefs }
    }
    var onLink: ((String, Bool) -> [String: Any])? {
        didSet { model.onLink = onLink }
    }
    var onScan: ((Bool) -> Void)? {
        didSet { model.onScan = onScan }
    }
    var onReset: (() -> Void)? {
        didSet { model.onReset = onReset }
    }

    var isVisible: Bool { panel.isVisible && panel.alphaValue > 0 }

    override init() {
        let model = SettingsModel()
        let panel = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
        panel.isFloatingPanel = true
        panel.isRestorable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.title = "Mochi Settings"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.worksWhenModal = true

        let hosting = SettingsHostingView(rootView: SettingsRoot(model: model))
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
        panel.contentView = hosting

        self.panel = panel
        self.model = model
        self.hosting = hosting
        super.init()
        panel.delegate = self
        revealWindowButtons()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        revealWindowButtons()
    }

    @objc func dismissSettings(_ sender: Any?) {
        hide()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: Self.width, height: Self.height)
    }

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        var frame = window.frame
        frame.size = NSSize(width: Self.width, height: Self.height)
        return frame
    }

    func attach(to host: NSWindow) {
        if let current = self.host {
            current.removeChildWindow(panel)
        }
        self.host = host
        // Independent of the click-through host so the fullscreen WebView
        // cannot steal the tab bar.
        if host.childWindows?.contains(panel) == true {
            host.removeChildWindow(panel)
        }
        panel.level = NSWindow.Level(rawValue: host.level.rawValue + 2)
        panel.collectionBehavior = host.collectionBehavior
        hide()
    }

    func load(prefs: IslandPrefs, link: [String: Any]) {
        model.apply(prefs: prefs, link: link)
    }

    func select(_ tab: SettingsTab) {
        model.tab = tab
    }

    func toggle(capsule: NSRect, dock: String, host: NSWindow) {
        if isVisible {
            hide()
            return
        }
        place(capsule: capsule, dock: dock, host: host)
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        revealWindowButtons()
        panel.makeFirstResponder(hosting)
    }

    func hide() {
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    func reposition(capsule: NSRect, dock: String, host: NSWindow) {
        guard isVisible else { return }
        place(capsule: capsule, dock: dock, host: host)
    }

    private func revealWindowButtons() {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = panel.standardWindowButton(kind) else { continue }
            button.isHidden = false
            button.isEnabled = true
        }
        if let close = panel.standardWindowButton(.closeButton) {
            close.target = self
            close.action = #selector(dismissSettings(_:))
        }
    }

    private func place(capsule: NSRect, dock: String, host: NSWindow) {
        let width = Self.width
        let height = Self.height
        var x = dock == "right" ? capsule.minX - Self.gap - width : capsule.maxX + Self.gap
        var y = capsule.minY + (capsule.height - height) / 2
        let canvas = host.frame
        x = min(max(x, canvas.minX + Self.gap), canvas.maxX - Self.gap - width)
        y = min(max(y, canvas.minY + Self.gap), canvas.maxY - Self.gap - height)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var tab: SettingsTab = .general
    @Published var selectionMoving = false
    @Published var sound = "boop"
    @Published var cursorConnected = false
    @Published var needsPrivacy = false
    @Published var scanTranscripts = false
    @Published var cursorStatus = "Not connected"
    @Published var cursorButton = "Connect Cursor"
    @Published var petScale = 1.0
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var pickerCursor = true
    @Published var pickerCodex = true
    @Published var pickerGrok = true
    @Published var pickerGPT = true

    var onPrefs: (([String: Any]) -> Void)?
    var onLink: ((String, Bool) -> [String: Any])?
    var onScan: ((Bool) -> Void)?
    var onReset: (() -> Void)?
    private var selectionTicket = 0

    func apply(prefs: IslandPrefs, link: [String: Any]) {
        sound = IslandPrefs.soundIDs.contains(prefs.sound) ? prefs.sound : "boop"
        petScale = prefs.petScale
        launchAtLogin = SMAppService.mainApp.status == .enabled
        scanTranscripts = prefs.scanTranscripts
        pickerCursor = prefs.pickerCursor
        pickerCodex = prefs.pickerCodex
        pickerGrok = prefs.pickerGrok
        pickerGPT = prefs.pickerGPT
        PickerMenu.shared.apply(prefs)
        cursorConnected = link["connected"] as? Bool ?? false
        needsPrivacy = link["needsPrivacy"] as? Bool ?? false
        if let scan = link["scanTranscripts"] as? Bool {
            scanTranscripts = scan
        }
        cursorStatus = cursorConnected ? "Connected" : "Not connected"
        cursorButton = needsPrivacy ? "Continue" : (cursorConnected ? "Disconnect" : "Connect Cursor")
    }

    func setPetScale(_ value: Double) {
        petScale = min(2, max(0.5, value))
        persist()
    }

    func persist() {
        let snapshot = IslandPrefs(
            sound: sound,
            petScale: petScale,
            pickerCursor: pickerCursor,
            pickerCodex: pickerCodex,
            pickerGrok: pickerGrok,
            pickerGPT: pickerGPT
        )
        onPrefs?([
            "sound": sound,
            "pet_scale": petScale,
            "picker_cursor": pickerCursor,
            "picker_codex": pickerCodex,
            "picker_grok": pickerGrok,
            "picker_gpt": pickerGPT
        ])
        PickerMenu.shared.apply(snapshot)
    }

    @discardableResult
    func beginSelectionMove() -> Int {
        selectionMoving = true
        selectionTicket += 1
        let ticket = selectionTicket
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            self.endSelectionMove(ticket)
        }
        return ticket
    }

    func endSelectionMove(_ ticket: Int) {
        guard selectionTicket == ticket else { return }
        selectionMoving = false
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func connectCursor() {
        let action = cursorConnected ? "disconnect" : "connect"
        // The privacy line is already on the Agents tab, so this click is the acknowledgment.
        let result = onLink?(action, true) ?? [:]
        if result["needsPrivacy"] as? Bool == true {
            needsPrivacy = true
            cursorButton = "Continue"
            return
        }
        cursorConnected = result["connected"] as? Bool ?? false
        scanTranscripts = result["scanTranscripts"] as? Bool ?? scanTranscripts
        cursorStatus = cursorConnected ? "Connected" : "Not connected"
        cursorButton = cursorConnected ? "Disconnect" : "Connect Cursor"
        needsPrivacy = false
    }
}

struct SettingsRoot: View {
    @ObservedObject var model: SettingsModel
    @Namespace private var tabNS

    private static let barFill = Color(red: 246 / 255, green: 246 / 255, blue: 247 / 255)
    private static let selectedFill = Color(red: 232 / 255, green: 232 / 255, blue: 234 / 255)
    private static let selectedInk = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    private static let idleInk = Color(red: 110 / 255, green: 110 / 255, blue: 115 / 255)

    var body: some View {
        VStack(spacing: 8) {
            Color.clear
                .frame(height: SettingsChrome.titleRow)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            settingsTabBar
                .padding(.horizontal, 16)
            Group {
                switch model.tab {
                case .general: generalPane
                case .kitten: kittenPane
                case .sound: soundPane
                case .agents: agentsPane
                }
            }
            .id(model.tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.bottom, 6)
        .frame(width: SettingsChrome.width, height: SettingsChrome.height, alignment: .top)
        .ignoresSafeArea()
        .background {
            Color.clear
                .glassEffect(.regular, in: .rect(cornerRadius: 28))
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var settingsTabBar: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTab.allCases, id: \.self) { item in
                tabButton(item)
            }
        }
        .padding(2)
        .frame(height: AppConfig.settingsBarHeight)
        .background {
            RoundedRectangle(cornerRadius: AppConfig.settingsBarRadius, style: .continuous)
                .fill(Self.barFill)
        }
    }

    private func tabButton(_ item: SettingsTab) -> some View {
        let selected = model.tab == item
        return Button {
            choose(item)
        } label: {
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? Self.selectedInk : Self.idleInk)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background {
                    if selected {
                        selectionPlate
                    }
                }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var selectionPlate: some View {
        let shape = RoundedRectangle(cornerRadius: AppConfig.settingsSelectRadius, style: .continuous)
        Group {
            if model.selectionMoving {
                GlassEffectContainer {
                    shape
                        .fill(.clear)
                        .glassEffect(.regular, in: shape)
                }
            } else {
                shape.fill(Self.selectedFill)
            }
        }
        .matchedGeometryEffect(id: "settings-tab", in: tabNS)
        .padding(1)
        .allowsHitTesting(false)
    }

    private func choose(_ item: SettingsTab) {
        guard model.tab != item else { return }
        let ticket = model.beginSelectionMove()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            model.tab = item
        } completion: {
            model.endSelectionMove(ticket)
        }
    }

    private var generalPane: some View {
        Form {
            Section {
                Button("Reset kitten position") { model.onReset?() }
                Toggle("Open at login", isOn: $model.launchAtLogin)
                    .onChange(of: model.launchAtLogin) { _, enabled in
                        model.setLaunchAtLogin(enabled)
                    }
            }
            Section {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var kittenPane: some View {
        Form {
            Section {
                ZStack {
                    FullKitten()
                        .frame(width: 56 * model.petScale, height: 56 * model.petScale)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 112)
                Slider(value: Binding(
                    get: { model.petScale },
                    set: { model.setPetScale($0) }
                ), in: 0.5...2) {
                    Text("Size")
                } minimumValueLabel: {
                    Text("S")
                } maximumValueLabel: {
                    Text("L")
                }
                LabeledContent("Size", value: String(format: "%.2f×", model.petScale))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var soundPane: some View {
        Form {
            Section("Click sound") {
                Picker("Sound", selection: Binding(
                    get: { model.sound },
                    set: { value in
                        model.sound = value
                        model.persist()
                        SoundPlayer.shared.playPreview(value)
                    }
                )) {
                    ForEach(SettingsChrome.sounds, id: \.self) { id in
                        Text(id.capitalized).tag(id)
                    }
                }
                .pickerStyle(.segmented)
                Text("Plays when you click the kitten, pick an agent, or hear an alert. A muted Mac stays quiet.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var agentsPane: some View {
        Form {
            Section("Cursor") {
                LabeledContent("Status", value: model.cursorStatus)
                Text("Mochi only reads and writes its own files in ~/.cursor on this Mac. It does not upload chats. Allow and deny stay on this computer.")
                    .foregroundStyle(.secondary)
                Button(model.cursorButton) { model.connectCursor() }
                Toggle("Notice recent local agent files", isOn: $model.scanTranscripts)
                    .onChange(of: model.scanTranscripts) { _, enabled in
                        model.onScan?(enabled)
                    }
                Text("Off by default. It records names and times on this Mac, not chat text.")
                    .foregroundStyle(.secondary)
            }
            Section("Plus picker") {
                Toggle("Cursor", isOn: $model.pickerCursor)
                    .onChange(of: model.pickerCursor) { _, _ in model.persist() }
                Toggle("Codex", isOn: $model.pickerCodex)
                    .onChange(of: model.pickerCodex) { _, _ in model.persist() }
                Toggle("Grok", isOn: $model.pickerGrok)
                    .onChange(of: model.pickerGrok) { _, _ in model.persist() }
                Toggle("GPT", isOn: $model.pickerGPT)
                    .onChange(of: model.pickerGPT) { _, _ in model.persist() }
                Text("These icons appear in the plus picker.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

#Preview("Settings") {
    SettingsRoot(model: SettingsModel())
        .frame(width: SettingsChrome.width, height: SettingsChrome.height)
}

/// Full-size host under a transparent titlebar. Clicks in the traffic-light
/// strip pass through so Close, miniaturize, and zoom stay live.
final class SettingsHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let stripHeight = SettingsChromeMetrics.titleRow
        let strip = NSRect(x: 0, y: bounds.height - stripHeight, width: 86, height: stripHeight)
        if strip.contains(local) {
            return nil
        }
        return super.hitTest(point)
    }
}
