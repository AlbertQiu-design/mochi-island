import AppKit
import MochiCore
import ServiceManagement
import SwiftUI

enum SettingsTab: Int, Hashable, CaseIterable {
    case dock
    case looks
    case colors
    case sound
    case links

    var title: String {
        switch self {
        case .dock: return "Dock"
        case .looks: return "Looks"
        case .colors: return "Colors"
        case .sound: return "Sound"
        case .links: return "Links"
        }
    }
}

@MainActor
final class SettingsChrome: NSObject {
    static let width: CGFloat = 420
    static let height: CGFloat = 540
    static let gap: CGFloat = 8
    static let palette = [
        "#ffffff", "#fff6e8", "#241f1c", "#e97868",
        "#efd36a", "#7dcb8d", "#3d6ea8", "#f4b6c2"
    ]
    static let sounds = ["boop", "chirp", "mew", "pop", "twinkle"]

    let panel: CapsulePanel
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
        panel.isMovable = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
        panel.isFloatingPanel = true
        panel.isRestorable = false
        panel.animationBehavior = .none
        panel.title = "Mochi Settings"
        panel.worksWhenModal = true

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
        model.onClose = { [weak self] in
            self?.hide()
        }
    }

    func attach(to host: NSWindow) {
        if let current = self.host {
            current.removeChildWindow(panel)
        }
        self.host = host
        // Independent of the click-through host so the fullscreen WebView
        // cannot steal Dock|Looks|Colors|Sound|Links clicks.
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
    @Published var petScale = 1.0
    @Published var bubbleScale = 1.0
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    var onPrefs: (([String: Any]) -> Void)?
    var onLink: ((String, Bool) -> [String: Any])?
    var onScan: ((Bool) -> Void)?
    var onReset: (() -> Void)?
    var onClose: (() -> Void)?

    func apply(prefs: IslandPrefs, link: [String: Any]) {
        dock = prefs.dock
        look = prefs.look
        sound = IslandPrefs.soundIDs.contains(prefs.sound) ? prefs.sound : "boop"
        fill = prefs.fill
        text = prefs.text
        stroke = prefs.stroke
        cardFill = prefs.cardFill
        cardStroke = prefs.cardStroke
        petScale = prefs.petScale
        bubbleScale = prefs.bubbleScale
        launchAtLogin = SMAppService.mainApp.status == .enabled
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
            "card_stroke": cardStroke,
            "pet_scale": petScale,
            "bubble_scale": bubbleScale
        ])
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

private struct SettingsCloseButton: View {
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(hovered
                        ? Color(red: 1, green: 95 / 255, blue: 87 / 255)
                        : Color(white: 0.62))
                    .frame(width: 14, height: 14)
                if hovered {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
            }
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("Close")
    }
}

struct SettingsRoot: View {
    @ObservedObject var model: SettingsModel
    @Namespace private var tabNS

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                SettingsCloseButton { model.onClose?() }
                settingsTabBar
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .padding(.top, 14)

            Group {
                switch model.tab {
                case .dock: dockPane
                case .looks: looksPane
                case .colors: colorsPane
                case .sound: soundPane
                case .links: linksPane
                }
            }
            .id(model.tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: SettingsChrome.width, height: SettingsChrome.height)
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
                .fill(Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255))
        }
    }

    private func tabButton(_ item: SettingsTab) -> some View {
        let selected = model.tab == item
        return Button {
            choose(item)
        } label: {
            Text(item.title)
                .font(Font(NSFont.systemFont(ofSize: 13, weight: NSFont.Weight(rawValue: 0.29))))
                .foregroundStyle(selected
                    ? Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
                    : Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255))
                .frame(minWidth: AppConfig.settingsTabMinWidth, maxWidth: .infinity, minHeight: 28)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: AppConfig.settingsSelectRadius, style: .continuous)
                            .fill(Color(red: 58 / 255, green: 58 / 255, blue: 58 / 255))
                            .matchedGeometryEffect(id: "settings-tab", in: tabNS)
                    }
                }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func choose(_ item: SettingsTab) {
        guard model.tab != item else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            model.tab = item
        }
    }

    private var dockPane: some View {
        Form {
            Section("Kitten") {
                Button("Reset kitten position") { model.onReset?() }
                Toggle("Open at login", isOn: $model.launchAtLogin)
                    .onChange(of: model.launchAtLogin) { _, enabled in
                        model.setLaunchAtLogin(enabled)
                    }
                Text("Drag the kitten anywhere on the screen. The capsule and bubble follow it.")
                    .foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("Mochi Island", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2")
                Text("A Mac kitten. Regular Liquid Glass on every surface.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var looksPane: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
        return Form {
            Section("Choose a pet") {
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
                .padding(.vertical, 4)
            }
            Section("Size") {
                Slider(value: $model.petScale, in: 0.5...2, step: 0.1) {
                    Text("Pet size")
                } minimumValueLabel: {
                    Text("S")
                } maximumValueLabel: {
                    Text("L")
                }
                .onChange(of: model.petScale) { _, _ in model.persist() }
                LabeledContent("Scale", value: String(format: "%.1f×", model.petScale))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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
            Section("Size") {
                Slider(value: $model.bubbleScale, in: 0.5...2, step: 0.1) {
                    Text("Bubble size")
                } minimumValueLabel: {
                    Text("S")
                } maximumValueLabel: {
                    Text("L")
                }
                .onChange(of: model.bubbleScale) { _, _ in model.persist() }
                LabeledContent("Scale", value: String(format: "%.1f×", model.bubbleScale))
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

    private var linksPane: some View {
        Form {
            Section("Cursor") {
                LabeledContent("Status", value: model.cursorStatus)
                if model.needsPrivacy {
                    Text("Mochi only reads and writes its own files in ~/.cursor on this Mac. It does not upload chats. Allow and deny stay on this computer.")
                        .foregroundStyle(.secondary)
                }
                Button(model.cursorButton) { model.connectCursor() }
                Toggle("Notice recent local agent files", isOn: $model.scanTranscripts)
                    .onChange(of: model.scanTranscripts) { _, enabled in
                        model.onScan?(enabled)
                    }
            }
            Section("Codex") {
                LabeledContent("Status", value: model.codexStatus)
                Button("Connect Codex") {
                    model.codexStatus = "Listening for tasks"
                }
                Text("Tasks arrive through the shared task file.")
                    .foregroundStyle(.secondary)
            }
            Section("Grok Bot") {
                LabeledContent("Status", value: model.grokStatus)
                Button("Connect Grok Bot") {
                    model.grokStatus = "Listening for tasks"
                }
                Text("Tasks arrive through the shared task file.")
                    .foregroundStyle(.secondary)
            }
            Section("小猫") {
                LabeledContent("Status", value: "Local desk pet")
                Text("小猫 stays on this Mac and does not open another app.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
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
