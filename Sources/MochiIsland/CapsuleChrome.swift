import AppKit
import MochiCore

/// Native sidebar capsule. Chrome is Apple Liquid Glass (`NSGlassEffectView`);
/// slot faces stay Designer art. Popup and settings stay in the web view.
@MainActor
final class CapsuleChrome: NSObject {
    static let width: CGFloat = 56
    static let face: CGFloat = 36
    static let gap: CGFloat = 8
    static let pad: CGFloat = 8
    static let caret: CGFloat = 8
    static let control: CGFloat = 36
    static let edge: CGFloat = 8
    static let materialAPI = "NSGlassEffectView.regular"
    static let addSymbol = "plus"
    static let settingsSymbol = "gearshape"
    static let menuTitles = ["Cursor", "Grok Bot", "小猫"]

    let panel: CapsulePanel
    let glass: NSGlassEffectView
    private let slotStack = NSStackView()
    private let slotScroll = NSScrollView()
    private let addButton: NSButton
    private let settingsButton: NSButton
    private let caretView = CaretView()
    private var slotButtons: [String: NSButton] = [:]
    private var slots: [[String: Any]] = []
    private var tasks: [[String: Any]] = []
    private var selected = ""
    private var dock = "right"
    private var popupOpen = false
    private var imageCache: [String: NSImage] = [:]
    private weak var host: NSWindow?

    var onSelect: ((String, Bool) -> Void)?
    var onCreate: ((String) -> Void)?
    var onSettings: (() -> Void)?

    override init() {
        let panel = CapsulePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
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
        panel.becomesKeyOnlyIfNeeded = true
        panel.isRestorable = false
        panel.animationBehavior = .none
        panel.title = "Mochi Capsule"
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)

        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: NSSize(width: Self.width, height: 200)))
        glass.style = .regular
        glass.tintColor = nil
        glass.cornerRadius = Self.width / 2
        if #available(macOS 27.0, *) {
            glass.effectIsInteractive = true
        }

        let addButton = CapsuleChrome.symbolButton(
            symbol: Self.addSymbol,
            title: "New chat",
            size: Self.control
        )
        let settingsButton = CapsuleChrome.symbolButton(
            symbol: Self.settingsSymbol,
            title: "Settings",
            size: Self.control
        )

        self.panel = panel
        self.glass = glass
        self.addButton = addButton
        self.settingsButton = settingsButton
        super.init()

        addButton.target = self
        addButton.action = #selector(addClicked(_:))
        settingsButton.target = self
        settingsButton.action = #selector(settingsClicked(_:))

        slotStack.orientation = .vertical
        slotStack.alignment = .centerX
        slotStack.spacing = Self.gap
        slotStack.translatesAutoresizingMaskIntoConstraints = false

        slotScroll.drawsBackground = false
        slotScroll.hasVerticalScroller = false
        slotScroll.hasHorizontalScroller = false
        slotScroll.autohidesScrollers = true
        slotScroll.borderType = .noBorder
        slotScroll.documentView = slotStack
        slotScroll.translatesAutoresizingMaskIntoConstraints = false

        let column = NSStackView(views: [slotScroll, addButton, settingsButton])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = Self.gap
        column.edgeInsets = NSEdgeInsets(top: Self.pad, left: 0, bottom: Self.pad, right: 0)
        column.translatesAutoresizingMaskIntoConstraints = false

        let hostView = NSView(frame: glass.bounds)
        hostView.autoresizingMask = [.width, .height]
        hostView.addSubview(column)
        hostView.addSubview(caretView)
        caretView.isHidden = true
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            column.topAnchor.constraint(equalTo: hostView.topAnchor),
            column.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
            slotScroll.widthAnchor.constraint(equalToConstant: Self.width),
            addButton.widthAnchor.constraint(equalToConstant: Self.control),
            addButton.heightAnchor.constraint(equalToConstant: Self.control),
            settingsButton.widthAnchor.constraint(equalToConstant: Self.control),
            settingsButton.heightAnchor.constraint(equalToConstant: Self.control)
        ])
        glass.contentView = hostView
        panel.contentView = glass
    }

    func attach(to host: NSWindow) {
        if let current = self.host {
            current.removeChildWindow(panel)
        }
        self.host = host
        panel.level = NSWindow.Level(rawValue: host.level.rawValue + 1)
        panel.collectionBehavior = host.collectionBehavior
        host.addChildWindow(panel, ordered: .above)
        panel.orderFrontRegardless()
    }

    func setDock(_ side: String) {
        dock = side == "left" ? "left" : "right"
        caretView.pointsLeft = dock == "right"
        layoutInHost()
    }

    func sync(slots: [[String: Any]], selected: String, tasks: [[String: Any]], dock: String) {
        self.slots = slots
        self.selected = selected
        self.tasks = tasks
        setDock(dock)
        rebuildSlots()
        layoutInHost()
    }

    func layoutInHost() {
        guard let host else { return }
        let canvas = host.frame
        let maxHeight = max(Self.control * 3, floor(canvas.height * 0.5))
        let slotCount = max(1, slots.count)
        let slotsHeight = CGFloat(slotCount) * Self.face + CGFloat(max(0, slotCount - 1)) * Self.gap
        let natural = Self.pad + slotsHeight + Self.gap + Self.control + Self.gap + Self.control + Self.pad
        let height = min(maxHeight, natural)
        let width = Self.width
        let x = dock == "left"
            ? canvas.minX + Self.edge
            : canvas.maxX - Self.edge - width
        let y = canvas.midY - height / 2
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        glass.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        glass.cornerRadius = width / 2
        if let hostView = glass.contentView {
            hostView.frame = glass.bounds
        }
        let scrollHeight = max(
            Self.face,
            height - (Self.pad + Self.gap + Self.control + Self.gap + Self.control + Self.pad)
        )
        slotScroll.frame.size.height = scrollHeight
        slotStack.frame = NSRect(
            x: 0,
            y: max(0, scrollHeight - slotsHeight),
            width: width,
            height: slotsHeight
        )
        addButton.setFrameSize(NSSize(width: Self.control, height: Self.control))
        settingsButton.setFrameSize(NSSize(width: Self.control, height: Self.control))
        placeCaret()
    }

    func chromePayload(in host: NSWindow) -> [String: Any] {
        func css(_ rect: NSRect) -> [String: Any] {
            let x = rect.minX - host.frame.minX
            let y = host.frame.height - (rect.minY - host.frame.minY) - rect.height
            return [
                "x": x,
                "y": y,
                "w": rect.width,
                "h": rect.height,
                "left": x,
                "top": y,
                "right": x + rect.width,
                "bottom": y + rect.height
            ]
        }
        var slotMap: [String: Any] = [:]
        for (id, button) in slotButtons {
            slotMap[id] = css(button.window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? .zero)
        }
        return [
            "dock": dock,
            "material": Self.materialAPI,
            "capsule": css(panel.frame),
            "add": css(addButton.window?.convertToScreen(addButton.convert(addButton.bounds, to: nil)) ?? .zero),
            "settings": css(settingsButton.window?.convertToScreen(settingsButton.convert(settingsButton.bounds, to: nil)) ?? .zero),
            "slots": slotMap,
            "selected": selected,
            "popupOpen": popupOpen,
            "menuCount": Self.menuTitles.count,
            "capsuleW": Self.width,
            "slotW": Self.width,
            "slotH": Self.face,
            "faceW": Self.face,
            "faceH": Self.face,
            "slotGap": Self.gap,
            "addW": Self.control,
            "gearW": Self.control,
            "addSymbol": Self.addSymbol,
            "gearSymbol": Self.settingsSymbol,
            "caret": Self.caret,
            "centered": true,
            "withinHalf": panel.frame.height <= host.frame.height * 0.5 + 1
        ]
    }

    func metrics() -> [String: Any] {
        addButton.layoutSubtreeIfNeeded()
        settingsButton.layoutSubtreeIfNeeded()
        let addW = addButton.bounds.width > 1 ? addButton.bounds.width.rounded() : Self.control
        let gearW = settingsButton.bounds.width > 1 ? settingsButton.bounds.width.rounded() : Self.control
        return [
            "material": Self.materialAPI,
            "capsuleW": Int(Self.width),
            "slotW": Int(Self.width),
            "slotH": Int(Self.face),
            "faceW": Int(Self.face),
            "faceH": Int(Self.face),
            "slotGap": Int(Self.gap),
            "addW": Int(addW),
            "gearW": Int(gearW),
            "addH": Int(addButton.bounds.height > 1 ? addButton.bounds.height.rounded() : Self.control),
            "gearH": Int(settingsButton.bounds.height > 1 ? settingsButton.bounds.height.rounded() : Self.control),
            "menuCount": Self.menuTitles.count,
            "addSymbol": Self.addSymbol,
            "gearSymbol": Self.settingsSymbol,
            "equalControls": abs(addButton.bounds.width - settingsButton.bounds.width) < 0.5,
            "faces": slots.map { slot -> [String: String] in
                [
                    "id": string(slot["id"]),
                    "source": AgentLaunch.normalize(string(slot["source"])),
                    "face": faceName(source: string(slot["source"]), status: taskStatus(string(slot["id"])))
                ]
            }
        ]
    }

    private func rebuildSlots() {
        slotStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        slotButtons.removeAll()
        for raw in slots {
            let id = string(raw["id"])
            guard !id.isEmpty else { continue }
            let source = AgentLaunch.normalize(string(raw["source"]))
            let title = string(raw["title"]).isEmpty ? "New chat" : string(raw["title"])
            let button = NSButton(title: "", target: self, action: #selector(slotClicked(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(id)
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.image = faceImage(source: source, status: taskStatus(id))
            button.toolTip = title
            button.setAccessibilityLabel(title)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: Self.width),
                button.heightAnchor.constraint(equalToConstant: Self.face)
            ])
            slotStack.addArrangedSubview(button)
            slotButtons[id] = button
        }
        placeCaret()
    }

    private func placeCaret() {
        caretView.pointsLeft = dock == "right"
        guard let button = slotButtons[selected] else {
            caretView.isHidden = true
            return
        }
        button.layoutSubtreeIfNeeded()
        let local = button.convert(button.bounds, to: caretView.superview)
        let width = Self.caret
        let height = Self.caret
        let x = dock == "right" ? 0 : Self.width - width
        caretView.frame = NSRect(
            x: x,
            y: local.midY - height / 2,
            width: width,
            height: height
        )
        caretView.isHidden = false
        caretView.needsDisplay = true
    }

    @objc private func slotClicked(_ sender: NSButton) {
        let id = sender.identifier?.rawValue ?? ""
        guard !id.isEmpty else { return }
        if id == selected, popupOpen {
            popupOpen = false
        } else {
            selected = id
            popupOpen = true
        }
        placeCaret()
        onSelect?(id, popupOpen)
    }

    @objc private func addClicked(_ sender: NSButton) {
        let menu = NSMenu()
        for (index, title) in Self.menuTitles.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(createFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
        }
        let point = NSPoint(x: dock == "right" ? 0 : sender.bounds.width, y: sender.bounds.height)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc private func createFromMenu(_ item: NSMenuItem) {
        let sources = ["cursor", "grok-bot", "mochi"]
        guard item.tag >= 0, item.tag < sources.count else { return }
        popupOpen = true
        onCreate?(sources[item.tag])
    }

    @objc private func settingsClicked(_ sender: NSButton) {
        onSettings?()
    }

    private func taskStatus(_ id: String) -> String {
        for task in tasks where string(task["id"]) == id {
            return string(task["status"])
        }
        return ""
    }

    private func faceName(source: String, status: String) -> String {
        let pack: String
        switch AgentLaunch.normalize(source) {
        case "grok-bot": pack = "grok"
        case "mochi": pack = "kitten"
        default: pack = "cursor"
        }
        return "\(pack)-\(faceState(status))"
    }

    private func faceState(_ status: String) -> String {
        switch status {
        case "running": return "work"
        case "wait", "fail": return "wait"
        case "done": return "done"
        default: return "wake"
        }
    }

    private func faceImage(source: String, status: String) -> NSImage? {
        let name = faceName(source: source, status: status)
        if let cached = imageCache[name] { return cached }
        if let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Web/pets"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: Self.face, height: Self.face)
            imageCache[name] = image
            return image
        }
        if AgentLaunch.normalize(source) == "codex" {
            let symbol = NSImage(systemSymbolName: "circle", accessibilityDescription: "Codex")
            imageCache[name] = symbol
            return symbol
        }
        return nil
    }

    private func string(_ value: Any?) -> String {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func symbolButton(symbol: String, title: String, size: CGFloat) -> NSButton {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(config)
        let button = NSButton(image: image ?? NSImage(), target: nil, action: nil)
        button.bezelStyle = .circular
        button.isBordered = true
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.setAccessibilityLabel(title)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}

final class CapsulePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private final class CaretView: NSView {
    var pointsLeft = true {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath()
        if pointsLeft {
            path.move(to: NSPoint(x: bounds.maxX, y: bounds.minY))
            path.line(to: NSPoint(x: bounds.minX, y: bounds.midY))
            path.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY))
        } else {
            path.move(to: NSPoint(x: bounds.minX, y: bounds.minY))
            path.line(to: NSPoint(x: bounds.maxX, y: bounds.midY))
            path.line(to: NSPoint(x: bounds.minX, y: bounds.maxY))
        }
        path.close()
        NSColor.white.setFill()
        path.fill()
    }
}
