import AppKit
import MochiCore
import SwiftUI

enum SettingsTab: Int, Hashable, CaseIterable {
    case dock
    case looks
    case colors
    case sound
    case links

    var title: String {
        let titles = AppConfig.settingsTabs
        if rawValue >= 0, rawValue < titles.count {
            return titles[rawValue]
        }
        return titles[0]
    }
}

@MainActor
final class SettingsChrome: NSObject {
    static let width: CGFloat = 400
    static let height: CGFloat = 460
    static let gap: CGFloat = 8
    static let palette = [
        "#ffffff", "#fff6e8", "#241f1c", "#e97868",
        "#efd36a", "#7dcb8d", "#3d6ea8", "#f4b6c2"
    ]
    static let sounds = ["boop", "chirp", "mew", "pop", "twinkle"]
    static let tabCircle: CGFloat = AppConfig.settingsTabCircle

    let panel: CapsulePanel
    private let model: SettingsModel
    private let hosting: HitHostingView<SettingsRoot>
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

    var isVisible: Bool { panel.isVisible && panel.alphaValue > 0 }

    override init() {
        let model = SettingsModel()
        let panel = CapsulePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
        panel.isRestorable = false
        panel.animationBehavior = .none
        panel.title = "Mochi Settings"
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)

        let hosting = HitHostingView(rootView: SettingsRoot(model: model))
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
        panel.contentView = hosting

        self.panel = panel
        self.model = model
        self.hosting = hosting
        super.init()
    }

    func attach(to host: NSWindow) {
        if let current = self.host {
            current.removeChildWindow(panel)
        }
        self.host = host
        // Never a child of the fullscreen host. Child windows inherit the
        // host's click-through, and WKWebView then eats the tab bar.
        if host.childWindows?.contains(panel) == true {
            host.removeChildWindow(panel)
        }
        panel.level = NSWindow.Level(rawValue: max(host.level.rawValue, NSWindow.Level.floating.rawValue) + 2)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        hide()
    }

    func load(prefs: IslandPrefs, link: [String: Any]) {
        model.apply(prefs: prefs, link: link)
    }

    func select(_ tab: SettingsTab) {
        model.show(tab)
    }

    func toggle(capsule: NSRect, dock: String, host: NSWindow) {
        if isVisible {
            hide()
            return
        }
        place(capsule: capsule, dock: dock, host: host)
        model.show(model.tab)
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(hosting)
    }

    func hide() {
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
    }

    func reposition(capsule: NSRect, dock: String, host: NSWindow) {
        guard isVisible else { return }
        place(capsule: capsule, dock: dock, host: host)
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
    @Published var tab: SettingsTab = .dock
    @Published var dock = "right"
    @Published var look = "mochi"
    @Published var sound = "boop"
    @Published var fill = "#ffffff"
    @Published var text = "#241f1c"
    @Published var stroke = "#2c2926"
    @Published var cardFill = "#111111"
    @Published var cardStroke = "#2c2926"
    @Published var cursorConnected = false
    @Published var needsPrivacy = false
    @Published var scanTranscripts = false
    @Published var cursorStatus = "Not connected"
    @Published var cursorButton = "Connect Cursor"
    @Published var codexStatus = "Upsert into the task file"
    @Published var grokStatus = "Upsert into the task file"
    @Published var lookImage: NSImage?

    var onPrefs: (([String: Any]) -> Void)?
    var onLink: ((String, Bool) -> [String: Any])?
    var onScan: ((Bool) -> Void)?

    func show(_ tab: SettingsTab) {
        self.tab = tab
    }

    func apply(prefs: IslandPrefs, link: [String: Any]) {
        dock = prefs.dock
        look = prefs.look
        sound = IslandPrefs.soundIDs.contains(prefs.sound) ? prefs.sound : "boop"
        fill = prefs.fill
        text = prefs.text
        stroke = prefs.stroke
        cardFill = prefs.cardFill
        cardStroke = prefs.cardStroke
        scanTranscripts = prefs.scanTranscripts
        cursorConnected = link["connected"] as? Bool ?? false
        needsPrivacy = link["needsPrivacy"] as? Bool ?? false
        if let scan = link["scanTranscripts"] as? Bool {
            scanTranscripts = scan
        }
        cursorStatus = cursorConnected ? "Connected" : "Not connected"
        cursorButton = needsPrivacy ? "Continue" : (cursorConnected ? "Disconnect" : "Connect Cursor")
        if lookImage == nil {
            lookImage = NSImage(
                contentsOf: Bundle.main.url(forResource: "happy", withExtension: "png", subdirectory: "Web/pets")
                    ?? URL(fileURLWithPath: "/dev/null")
            )
        }
    }

    func persist() {
        onPrefs?([
            "dock": dock,
            "look": look,
            "sound": sound,
            "fill": fill,
            "text": text,
            "stroke": stroke,
            "card_fill": cardFill,
            "card_stroke": cardStroke
        ])
    }

    func connectCursor() {
        let action = cursorConnected ? "disconnect" : "connect"
        let result = onLink?(action, cursorConnected || needsPrivacy) ?? [:]
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

    var body: some View {
        VStack(spacing: CapsuleChrome.gap) {
            settingsTabBar
                .padding(.horizontal, 16)
                .padding(.top, 16)

            Group {
                switch model.tab {
                case .dock: dockPane
                case .looks: looksPane
                case .colors: colorsPane
                case .sound: soundPane
                case .links: linksPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: SettingsChrome.width, height: SettingsChrome.height)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .glassEffect(.clear, in: .rect(cornerRadius: 28))
        .materialActiveAppearance(.active)
    }

    private var settingsTabBar: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTab.allCases, id: \.self) { item in
                if item != SettingsTab.allCases.first {
                    Divider()
                        .frame(height: 12)
                }
                tabButton(item)
            }
        }
        .padding(4)
        .glassEffect(.clear, in: .capsule)
        .materialActiveAppearance(.active)
    }

    private func tabButton(_ item: SettingsTab) -> some View {
        let selected = model.tab == item
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                model.show(item)
            }
        } label: {
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .frame(minWidth: SettingsChrome.tabCircle, minHeight: SettingsChrome.tabCircle)
                .padding(.horizontal, 6)
                .background {
                    if selected {
                        Circle()
                            .fill(.white.opacity(0.25))
                            .frame(width: SettingsChrome.tabCircle, height: SettingsChrome.tabCircle)
                            .matchedGeometryEffect(id: "settings-tab", in: tabNS)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var dockPane: some View {
        Form {
            Picker("Side", selection: $model.dock) {
                Text("Left").tag("left")
                Text("Right").tag("right")
            }
            .pickerStyle(.segmented)
            .onChange(of: model.dock) { _, _ in model.persist() }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var looksPane: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Choose a pet")
            LazyVGrid(columns: columns, spacing: 8) {
                Button {
                    model.look = "mochi"
                    model.persist()
                } label: {
                    if let image = model.lookImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                    } else {
                        Image(systemName: "pawprint.fill")
                            .frame(width: 48, height: 48)
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Mochi")
                ForEach(0..<15, id: \.self) { _ in
                    Button(action: {}) {
                        Image(systemName: "questionmark")
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.borderless)
                    .disabled(true)
                    .accessibilityLabel("Coming soon")
                }
            }
        }
        .padding()
    }

    private var colorsPane: some View {
        Form {
            Section("Bubble") {
                hexRow("Fill", text: $model.fill) { model.fill = $0 }
                hexRow("Text", text: $model.text) { model.text = $0 }
                hexRow("Stroke", text: $model.stroke) { model.stroke = $0 }
            }
            Section("Cards") {
                hexRow("Fill", text: $model.cardFill) { model.cardFill = $0 }
                hexRow("Stroke", text: $model.cardStroke) { model.cardStroke = $0 }
            }
        }
        .formStyle(.grouped)
    }

    private var soundPane: some View {
        Form {
            Picker("Click sound", selection: $model.sound) {
                ForEach(SettingsChrome.sounds, id: \.self) { id in
                    Text(id.capitalized).tag(id)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: model.sound) { _, _ in model.persist() }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var linksPane: some View {
        Form {
            Section("Cursor") {
                Text(model.cursorStatus)
                if model.needsPrivacy {
                    Text("Mochi only reads and writes its own files in ~/.cursor on this Mac. It does not upload chats. Allow and deny stay on this computer.")
                }
                Button(model.cursorButton) { model.connectCursor() }
                Toggle("Notice recent local agent files", isOn: $model.scanTranscripts)
                    .onChange(of: model.scanTranscripts) { _, enabled in
                        model.onScan?(enabled)
                    }
            }
            Section("Codex") {
                Text(model.codexStatus)
                Button("Connect Codex") {
                    model.codexStatus = "Listening for tasks"
                }
            }
            Section("Grok Bot") {
                Text(model.grokStatus)
                Button("Connect Grok Bot") {
                    model.grokStatus = "Listening for tasks"
                }
            }
        }
        .formStyle(.grouped)
    }

    private func hexRow(_ title: String, text: Binding<String>, set: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        set(SettingsModel.normalizedHex(text.wrappedValue, fallback: text.wrappedValue))
                        model.persist()
                    }
            }
            HStack(spacing: 6) {
                ForEach(SettingsChrome.palette, id: \.self) { hex in
                    Button {
                        set(hex)
                        text.wrappedValue = hex
                        model.persist()
                    } label: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(Color(hex: hex))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(hex)
                }
            }
        }
    }
}

extension SettingsModel {
    static func normalizedHex(_ value: String, fallback: String) -> String {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw.range(of: "^#[0-9a-f]{6}$", options: .regularExpression) != nil { return raw }
        if raw.range(of: "^[0-9a-f]{6}$", options: .regularExpression) != nil { return "#\(raw)" }
        return fallback
    }
}

private extension Color {
    init(hex: String) {
        let body = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var value: UInt64 = 0
        Scanner(string: body).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255,
            opacity: 1
        )
    }
}

#Preview("Settings") {
    SettingsRoot(model: SettingsModel())
        .frame(width: SettingsChrome.width, height: SettingsChrome.height)
}
