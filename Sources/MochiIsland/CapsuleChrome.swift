import AppKit
import MochiCore
import SwiftUI

/// Native sidebar capsule. Chrome is official SwiftUI Liquid Glass:
/// `.glassEffect(.clear, in: .capsule)`.
/// Slot faces stay Designer art. Popup stays web. Settings is native Picker + glass.
@MainActor
final class CapsuleChrome: NSObject {
    static let width: CGFloat = 56
    static let face: CGFloat = 36
    static let gap: CGFloat = 8
    static let pad: CGFloat = 8
    static let caret: CGFloat = 8
    static let control: CGFloat = 36
    static let edge: CGFloat = 8
    static let corner: CGFloat = 28
    static let materialAPI = "glassEffect.clear"
    static let addSymbol = "plus"
    static let settingsSymbol = "gearshape"
    static let menuTitles = ["Cursor", "Grok Bot", "小猫"]

    let panel: CapsulePanel
    private let model: CapsuleModel
    private let hosting: NSHostingView<CapsuleRoot>
    private var imageCache: [String: NSImage] = [:]
    private weak var host: NSWindow?

    var onSelect: ((String, Bool) -> Void)? {
        didSet { model.onSelect = onSelect }
    }
    var onCreate: ((String) -> Void)? {
        didSet { model.onCreate = onCreate }
    }
    var onSettings: (() -> Void)? {
        didSet { model.onSettings = onSettings }
    }

    override init() {
        let model = CapsuleModel()
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

        let hosting = NSHostingView(rootView: CapsuleRoot(model: model))
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
        panel.level = NSWindow.Level(rawValue: host.level.rawValue + 1)
        panel.collectionBehavior = host.collectionBehavior
        host.addChildWindow(panel, ordered: .above)
        panel.orderFrontRegardless()
    }

    func setDock(_ side: String) {
        model.dock = side == "left" ? "left" : "right"
        layoutInHost()
    }

    func sync(slots: [[String: Any]], selected: String, tasks: [[String: Any]], dock: String) {
        model.slots = slots.compactMap { raw in
            let id = string(raw["id"])
            guard !id.isEmpty else { return nil }
            let source = AgentLaunch.normalize(string(raw["source"]))
            let title = string(raw["title"]).isEmpty ? "New chat" : string(raw["title"])
            return CapsuleSlot(
                id: id,
                source: source,
                title: title,
                image: faceImage(source: source, status: taskStatus(id, in: tasks))
            )
        }
        model.selected = selected
        model.dock = dock == "left" ? "left" : "right"
        layoutInHost()
    }

    func layoutInHost() {
        guard let host else { return }
        let canvas = host.frame
        let maxHeight = max(Self.control * 3, floor(canvas.height * 0.5))
        let slotCount = max(1, model.slots.count)
        let slotsHeight = CGFloat(slotCount) * Self.face + CGFloat(max(0, slotCount - 1)) * Self.gap
        let natural = Self.pad + slotsHeight + Self.gap + 8 + Self.gap + Self.control + Self.gap + Self.control + Self.pad
        let height = min(maxHeight, natural)
        let width = Self.width
        let x = model.dock == "left"
            ? canvas.minX + Self.edge
            : canvas.maxX - Self.edge - width
        let y = canvas.midY - height / 2
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
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
        let local = layoutRects()
        var slotMap: [String: Any] = [:]
        for (id, rect) in local.slots {
            slotMap[id] = css(panel.convertToScreen(rect))
        }
        return [
            "dock": model.dock,
            "material": Self.materialAPI,
            "capsule": css(panel.frame),
            "add": css(panel.convertToScreen(local.add)),
            "settings": css(panel.convertToScreen(local.settings)),
            "slots": slotMap,
            "selected": model.selected,
            "popupOpen": model.popupOpen,
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
        [
            "material": Self.materialAPI,
            "capsuleW": Int(Self.width),
            "slotW": Int(Self.width),
            "slotH": Int(Self.face),
            "faceW": Int(Self.face),
            "faceH": Int(Self.face),
            "slotGap": Int(Self.gap),
            "addW": Int(Self.control),
            "gearW": Int(Self.control),
            "addH": Int(Self.control),
            "gearH": Int(Self.control),
            "menuCount": Self.menuTitles.count,
            "addSymbol": Self.addSymbol,
            "gearSymbol": Self.settingsSymbol,
            "equalControls": true,
            "faces": model.slots.map { slot in
                [
                    "id": slot.id,
                    "source": slot.source,
                    "face": faceName(source: slot.source, status: "")
                ]
            }
        ]
    }

    private func layoutRects() -> (slots: [String: NSRect], add: NSRect, settings: NSRect) {
        let height = panel.frame.height
        let slotsHeight = CGFloat(max(1, model.slots.count)) * Self.face
            + CGFloat(max(0, model.slots.count - 1)) * Self.gap
        var slotMap: [String: NSRect] = [:]
        for (index, slot) in model.slots.enumerated() {
            let top = Self.pad + CGFloat(index) * (Self.face + Self.gap)
            let y = height - top - Self.face
            slotMap[slot.id] = NSRect(x: 0, y: y, width: Self.width, height: Self.face)
        }
        let addTop = Self.pad + slotsHeight + Self.gap
        let add = NSRect(
            x: (Self.width - Self.control) / 2,
            y: height - addTop - Self.control,
            width: Self.control,
            height: Self.control
        )
        let settingsTop = addTop + Self.control + Self.gap
        let settings = NSRect(
            x: (Self.width - Self.control) / 2,
            y: height - settingsTop - Self.control,
            width: Self.control,
            height: Self.control
        )
        return (slotMap, add, settings)
    }

    private func taskStatus(_ id: String, in tasks: [[String: Any]]) -> String {
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
}

final class CapsulePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
final class CapsuleModel: ObservableObject {
    @Published var slots: [CapsuleSlot] = []
    @Published var selected = ""
    @Published var dock = "right"
    @Published var popupOpen = false
    var onSelect: ((String, Bool) -> Void)?
    var onCreate: ((String) -> Void)?
    var onSettings: (() -> Void)?

    func choose(_ id: String) {
        if id == selected, popupOpen {
            popupOpen = false
        } else {
            selected = id
            popupOpen = true
        }
        onSelect?(id, popupOpen)
    }

    func create(_ source: String) {
        popupOpen = true
        onCreate?(source)
    }
}

struct CapsuleSlot: Identifiable {
    var id: String
    var source: String
    var title: String
    var image: NSImage?
}

struct CapsuleRoot: View {
    @ObservedObject var model: CapsuleModel
    @Namespace private var selectionNS

    var body: some View {
        VStack(spacing: CapsuleChrome.gap) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: CapsuleChrome.gap) {
                    ForEach(model.slots) { slot in
                        slotButton(slot)
                    }
                }
            }

            Divider()

            Menu {
                Button("Cursor") { model.create("cursor") }
                Button("Grok Bot") { model.create("grok-bot") }
                Button("小猫") { model.create("mochi") }
            } label: {
                Image(systemName: CapsuleChrome.addSymbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: CapsuleChrome.control, height: CapsuleChrome.control)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .frame(width: CapsuleChrome.control, height: CapsuleChrome.control)
            .accessibilityLabel("New chat")

            Button(action: { model.onSettings?() }) {
                Image(systemName: CapsuleChrome.settingsSymbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: CapsuleChrome.control, height: CapsuleChrome.control)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(width: CapsuleChrome.control, height: CapsuleChrome.control)
            .accessibilityLabel("Settings")
        }
        .padding(CapsuleChrome.pad)
        .frame(width: CapsuleChrome.width)
        .frame(maxHeight: .infinity)
        .glassEffect(.clear, in: .capsule)
    }

    @ViewBuilder
    private func slotButton(_ slot: CapsuleSlot) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                model.choose(slot.id)
            }
        } label: {
            ZStack {
                if slot.id == model.selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.quaternary)
                        .matchedGeometryEffect(id: "slot-selection", in: selectionNS)
                }
                if let image = slot.image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: CapsuleChrome.face, height: CapsuleChrome.face)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: CapsuleChrome.face, height: CapsuleChrome.face)
                }
            }
            .frame(width: CapsuleChrome.control, height: CapsuleChrome.control)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(slot.title)
    }
}

#Preview("Capsule") {
    let model = CapsuleModel()
    model.slots = [
        CapsuleSlot(id: "a", source: "cursor", title: "Cursor", image: nil),
        CapsuleSlot(id: "b", source: "grok-bot", title: "Grok Bot", image: nil),
        CapsuleSlot(id: "c", source: "mochi", title: "小猫", image: nil)
    ]
    model.selected = "a"
    return CapsuleRoot(model: model)
        .frame(width: CapsuleChrome.width, height: 280)
}
