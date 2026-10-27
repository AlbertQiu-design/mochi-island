import AppKit
import MochiCore
import SwiftUI

/// Sidebar dock aligned to the DockPanel + DockView reference:
/// 68×602 panel, 60-wide capsule, 40pt buttons, clear glass, white plus/gear.
@MainActor
final class CapsuleChrome: NSObject {
    static let panelWidth: CGFloat = 68
    static let panelMaxHeight: CGFloat = 602
    static let dockWidth: CGFloat = 60
    static let dockMaxHeight: CGFloat = 570
    static let buttonSize: CGFloat = 40
    static let plusHeight: CGFloat = 36
    static let face: CGFloat = 36
    static let iconSize: CGFloat = 22
    static let itemSpacing: CGFloat = 8
    static let footerSpacing: CGFloat = 12
    static let footerGap: CGFloat = 16
    static let verticalPadding: CGFloat = 12
    static let edge: CGFloat = 20
    static let caret: CGFloat = 8
    static let cardWidth: CGFloat = 200
    static let materialAPI = "glassEffect.clear"
    static let addSymbol = "plus"
    static let settingsSymbol = "gearshape"
    static let menuTitles = ["Cursor", "Grok Bot", "小猫", "Codex"]

    static var width: CGFloat { panelWidth }
    static var gap: CGFloat { itemSpacing }
    static var pad: CGFloat { verticalPadding }
    static var control: CGFloat { buttonSize }
    static var corner: CGFloat { buttonSize / 2 }

    let panel: CapsulePanel
    private let model: CapsuleModel
    private let hosting: NSHostingView<CapsuleRoot>
    private let tipPanel: CapsulePanel
    private let tipHost: NSHostingView<DockBubbleRoot>
    private let tipModel: DockTipModel
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
    var onChoice: (([String: Any]) -> [String: Any])? {
        didSet { tipModel.onChoice = onChoice }
    }
    var onOpenAgent: ((String, String) -> Void)? {
        didSet { tipModel.onOpen = { [weak self] in
            guard let self else { return }
            self.onOpenAgent?(self.tipModel.source, self.tipModel.taskID)
        } }
    }

    var interactiveBubbleFrame: NSRect? {
        guard tipPanel.isVisible, tipPanel.alphaValue > 0, !tipPanel.ignoresMouseEvents else { return nil }
        return tipPanel.frame
    }

    override init() {
        let model = CapsuleModel()
        let panel = CapsulePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 200),
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
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.isRestorable = false
        panel.animationBehavior = .none
        panel.title = "Mochi Capsule"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = HitHostingView(rootView: CapsuleRoot(model: model))
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
        panel.contentView = hosting

        let tipModel = DockTipModel()
        let tipPanel = CapsulePanel(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 28),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        tipPanel.isOpaque = false
        tipPanel.backgroundColor = .clear
        tipPanel.hasShadow = false
        tipPanel.hidesOnDeactivate = false
        tipPanel.isFloatingPanel = true
        tipPanel.isMovable = false
        tipPanel.ignoresMouseEvents = true
        tipPanel.becomesKeyOnlyIfNeeded = true
        tipPanel.isRestorable = false
        tipPanel.animationBehavior = .none
        tipPanel.title = "Mochi Tip"
        tipPanel.level = .floating
        let tipHost = NSHostingView(rootView: DockBubbleRoot(model: tipModel))
        tipHost.sizingOptions = []
        tipHost.wantsLayer = true
        tipHost.layer?.backgroundColor = NSColor.clear.cgColor
        tipHost.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
        tipPanel.contentView = tipHost

        self.panel = panel
        self.model = model
        self.hosting = hosting
        self.tipPanel = tipPanel
        self.tipHost = tipHost
        self.tipModel = tipModel
        super.init()
        model.onHover = { [weak self] id in
            self?.placeTip(id)
        }
    }

    func attach(to host: NSWindow) {
        if let current = self.host {
            current.removeChildWindow(panel)
        }
        self.host = host
        panel.level = .floating
        tipPanel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        tipPanel.collectionBehavior = panel.collectionBehavior
        host.addChildWindow(panel, ordered: .above)
        panel.orderFrontRegardless()
    }

    func setDock(_ side: String) {
        model.dock = side == "left" ? "left" : "right"
        layoutInHost()
    }

    func sync(slots: [[String: Any]], selected: String, tasks: [[String: Any]], dock: String) {
        model.tasks = tasks
        model.slots = slots.compactMap { raw in
            let id = string(raw["id"])
            guard !id.isEmpty else { return nil }
            let source = AgentLaunch.normalize(string(raw["source"]))
            let title = string(raw["title"]).isEmpty ? "New chat" : string(raw["title"])
            return CapsuleSlot(
                id: id,
                source: source,
                title: title,
                image: faceImage(source: source, status: taskStatus(id, in: tasks)),
                symbol: source == "codex" ? "circle" : nil
            )
        }
        model.selected = selected
        model.dock = dock == "left" ? "left" : "right"
        layoutInHost()
        if model.popupOpen {
            placeCard(selected)
        } else if tipModel.mode == .card {
            tipPanel.alphaValue = 0
            tipPanel.orderOut(nil)
        }
    }

    func layoutInHost() {
        guard let host else { return }
        let height = dockHeight(for: model.slots.count)
        let width = Self.panelWidth
        let x = model.dock == "left"
            ? host.frame.minX + Self.edge
            : host.frame.maxX - Self.edge - width
        let y = host.frame.midY - height / 2
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        hosting.rootView = CapsuleRoot(model: model)
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
            "capsuleW": Self.panelWidth,
            "slotW": Self.panelWidth,
            "slotH": Self.buttonSize,
            "faceW": Self.face,
            "faceH": Self.face,
            "slotGap": Self.itemSpacing,
            "addW": Self.buttonSize,
            "gearW": Self.buttonSize,
            "addSymbol": Self.addSymbol,
            "gearSymbol": Self.settingsSymbol,
            "caret": Self.caret,
            "centered": true,
            "withinHalf": panel.frame.height <= Self.panelMaxHeight + 1
        ]
    }

    func metrics() -> [String: Any] {
        [
            "material": Self.materialAPI,
            "capsuleW": Int(Self.panelWidth),
            "slotW": Int(Self.panelWidth),
            "slotH": Int(Self.buttonSize),
            "faceW": Int(Self.face),
            "faceH": Int(Self.face),
            "slotGap": Int(Self.itemSpacing),
            "addW": Int(Self.buttonSize),
            "gearW": Int(Self.buttonSize),
            "addH": Int(Self.plusHeight),
            "gearH": Int(Self.buttonSize),
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

    func noteHover(at screenPoint: NSPoint) {
        if model.popupOpen {
            return
        }
        guard panel.frame.contains(screenPoint) else {
            placeTip(nil)
            return
        }
        let local = panel.convertPoint(fromScreen: screenPoint)
        let hit = layoutRects().slots.first { $0.value.contains(local) }?.key
        placeTip(hit)
    }

    func hideTip() {
        if model.popupOpen { return }
        placeTip(nil)
    }

    func revealSelected() {
        model.popupOpen = true
        placeCard(model.selected)
    }

    func hideCard() {
        model.popupOpen = false
        tipPanel.alphaValue = 0
        tipPanel.orderOut(nil)
    }

    private func dockHeight(for slotCount: Int) -> CGFloat {
        let count = max(1, slotCount)
        let slotStack = CGFloat(count) * Self.buttonSize + CGFloat(max(0, count - 1)) * Self.itemSpacing
        let footer = Self.footerGap + Self.plusHeight + Self.footerSpacing + Self.buttonSize
        let natural = Self.verticalPadding * 2 + slotStack + footer
        return min(Self.panelMaxHeight, min(Self.dockMaxHeight, natural))
    }

    private func layoutRects() -> (slots: [String: NSRect], add: NSRect, settings: NSRect) {
        let height = panel.frame.height
        let pad = Self.verticalPadding
        let settings = NSRect(
            x: (Self.panelWidth - Self.buttonSize) / 2,
            y: pad,
            width: Self.buttonSize,
            height: Self.buttonSize
        )
        let add = NSRect(
            x: (Self.panelWidth - Self.buttonSize) / 2,
            y: pad + Self.buttonSize + Self.footerSpacing,
            width: Self.buttonSize,
            height: Self.plusHeight
        )
        var slotMap: [String: NSRect] = [:]
        for (index, slot) in model.slots.enumerated() {
            let top = pad + CGFloat(index) * (Self.buttonSize + Self.itemSpacing)
            let y = height - top - Self.buttonSize
            slotMap[slot.id] = NSRect(x: 0, y: y, width: Self.panelWidth, height: Self.buttonSize)
        }
        return (slotMap, add, settings)
    }

    private func taskStatus(_ id: String, in tasks: [[String: Any]]) -> String {
        for task in tasks where string(task["id"]) == id {
            return string(task["status"])
        }
        return ""
    }

    private func task(for id: String) -> [String: Any]? {
        model.tasks.first { string($0["id"]) == id }
    }

    private func placeTip(_ id: String?) {
        guard !model.popupOpen else { return }
        guard let id,
              let slot = model.slots.first(where: { $0.id == id }),
              let rect = layoutRects().slots[id] else {
            if !model.popupOpen {
                tipPanel.alphaValue = 0
                tipPanel.orderOut(nil)
            }
            return
        }
        tipModel.mode = .tip
        tipModel.text = SlotFace.label(title: slot.title, source: slot.source)
        tipModel.dock = model.dock
        tipModel.taskID = slot.id
        tipModel.source = slot.source
        showBubble(anchor: rect, interactive: false)
    }

    private func placeCard(_ id: String) {
        guard let slot = model.slots.first(where: { $0.id == id }),
              let rect = layoutRects().slots[id] else {
            tipPanel.alphaValue = 0
            tipPanel.orderOut(nil)
            return
        }
        let task = task(for: id) ?? [:]
        tipModel.mode = .card
        tipModel.dock = model.dock
        tipModel.taskID = slot.id
        tipModel.source = AgentLaunch.normalize(string(task["source"]).isEmpty ? slot.source : string(task["source"]))
        tipModel.text = SlotFace.label(title: slot.title, source: slot.source)
        tipModel.title = string(task["title"]).isEmpty ? slot.title : string(task["title"])
        tipModel.app = SlotFace.displayName(for: tipModel.source)
        tipModel.status = string(task["status"])
        tipModel.kind = string(task["kind"])
        tipModel.prompt = string(task["prompt"])
        tipModel.detail = string(task["detail"])
        tipModel.requestID = string(task["request_id"])
        tipModel.questionID = string(task["question_id"])
        tipModel.options = Self.parseOptions(task["options"])
        showBubble(anchor: rect, interactive: true)
    }

    private func showBubble(anchor: NSRect, interactive: Bool) {
        tipHost.rootView = DockBubbleRoot(model: tipModel)
        let fitted = tipHost.fittingSize
        let width = tipModel.mode == .card
            ? max(Self.cardWidth + Self.caret, ceil(fitted.width))
            : max(56, ceil(fitted.width))
        let height = max(26, ceil(fitted.height))
        let screenSlot = panel.convertToScreen(anchor)
        let gap: CGFloat = 6
        let x = model.dock == "right"
            ? screenSlot.minX - gap - width
            : screenSlot.maxX + gap
        let y = screenSlot.midY - height / 2
        tipPanel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        tipHost.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        tipPanel.ignoresMouseEvents = !interactive
        tipPanel.alphaValue = 1
        tipPanel.orderFrontRegardless()
    }

    private func faceName(source: String, status: String) -> String {
        SlotFace.resourceName(source: source, status: status)
    }

    private func faceImage(source: String, status: String) -> NSImage? {
        let name = faceName(source: source, status: status)
        if let cached = imageCache[name] { return cached }
        let folders = ["Web/pets", "pets"]
        for ext in ["png", "svg"] {
            for folder in folders {
                if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: folder),
                   let image = NSImage(contentsOf: url) {
                    image.size = NSSize(width: Self.face, height: Self.face)
                    imageCache[name] = image
                    return image
                }
            }
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

    private static func parseOptions(_ value: Any?) -> [DockOption] {
        let rows: [[String: Any]]
        if let list = value as? [[String: Any]] {
            rows = list
        } else if let list = value as? [[String: String]] {
            return list.compactMap { item in
                let label = item["label"] ?? ""
                guard !label.isEmpty else { return nil }
                return DockOption(id: item["id"] ?? "", label: label)
            }
        } else {
            rows = []
        }
        return rows.compactMap { item in
            let label = (item["label"] as? String) ?? ""
            guard !label.isEmpty else { return nil }
            return DockOption(id: (item["id"] as? String) ?? "", label: label)
        }
    }
}

final class CapsulePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class HitHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let view = super.hitTest(point) { return view }
        return bounds.contains(point) ? self : nil
    }
}

struct DockOption: Identifiable, Equatable {
    var id: String
    var label: String
}

enum DockBubbleMode {
    case tip
    case card
}

@MainActor
final class DockTipModel: ObservableObject {
    @Published var mode: DockBubbleMode = .tip
    @Published var text = ""
    @Published var dock = "right"
    @Published var title = ""
    @Published var app = ""
    @Published var status = ""
    @Published var kind = ""
    @Published var prompt = ""
    @Published var detail = ""
    @Published var taskID = ""
    @Published var source = "cursor"
    @Published var requestID = ""
    @Published var questionID = ""
    @Published var options: [DockOption] = []
    var onChoice: (([String: Any]) -> [String: Any])?
    var onOpen: (() -> Void)?

    func choose(_ option: DockOption) {
        _ = onChoice?([
            "id": taskID,
            "kind": kind,
            "request_id": requestID,
            "question_id": questionID,
            "option_id": option.id,
            "label": option.label
        ])
        options = []
        status = status == "wait" ? "running" : status
        prompt = ""
    }
}

struct CaretTriangle: Shape {
    var pointing: Edge

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch pointing {
        case .trailing:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .leading:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        default:
            path.addRect(rect)
        }
        path.closeSubpath()
        return path
    }
}

struct DockBubbleRoot: View {
    @ObservedObject var model: DockTipModel

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 0) {
                if model.dock == "left" {
                    caret
                }
                if model.mode == .tip {
                    tipBody
                } else {
                    cardBody
                }
                if model.dock == "right" {
                    caret
                }
            }
        }
        .materialActiveAppearance(.active)
    }

    private var tipBody: some View {
        Text(model.text)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.clear, in: .capsule)
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(model.app)
                    .font(.system(size: 14, weight: .semibold))
                Text(model.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .contentShape(Rectangle())
            .onTapGesture { model.onOpen?() }

            if !model.status.isEmpty {
                HStack(spacing: 6) {
                    statusMark
                    Text(statusLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
            }
            if !kindLabel.isEmpty {
                Text(kindLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            if !model.prompt.isEmpty {
                Text(model.prompt)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.detail.isEmpty, model.detail != model.prompt, model.detail != model.title {
                Text(model.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.prompt.isEmpty, model.detail.isEmpty {
                Text("No summary yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if !model.options.isEmpty {
                HStack(spacing: 8) {
                    ForEach(model.options) { option in
                        Button(option.label) { model.choose(option) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: CapsuleChrome.cardWidth, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { model.onOpen?() }
        .glassEffect(.clear, in: .rect(cornerRadius: 16))
    }

    private var caret: some View {
        let edge: Edge = model.dock == "right" ? .trailing : .leading
        return CaretTriangle(pointing: edge)
            .frame(width: CapsuleChrome.caret, height: 10)
            .glassEffect(.clear, in: CaretTriangle(pointing: edge))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var statusMark: some View {
        switch model.status {
        case "running":
            ProgressView()
                .controlSize(.small)
        case "wait":
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        case "done":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case "fail":
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }

    private var statusLabel: String {
        switch model.status {
        case "running": return "Running"
        case "wait": return "Waiting"
        case "done": return "Done"
        case "fail": return "Failed"
        default: return ""
        }
    }

    private var kindLabel: String {
        switch model.kind {
        case "choice": return "Choice"
        case "plan": return "Plan"
        case "mode": return "Mode"
        case "permission": return "Permission"
        default: return ""
        }
    }
}

@MainActor
final class CapsuleModel: ObservableObject {
    @Published var slots: [CapsuleSlot] = []
    @Published var selected = ""
    @Published var hovered = ""
    @Published var dock = "right"
    @Published var popupOpen = false
    var tasks: [[String: Any]] = []
    var onSelect: ((String, Bool) -> Void)?
    var onCreate: ((String) -> Void)?
    var onSettings: (() -> Void)?
    var onHover: ((String?) -> Void)?

    func choose(_ id: String) {
        if id == selected, popupOpen {
            popupOpen = false
            onHover?(nil)
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
    var symbol: String?
}

struct CapsuleRoot: View {
    @ObservedObject var model: CapsuleModel
    @Namespace private var selectionAnimation
    @State private var hoveredID: String?

    private var slotStack: CGFloat {
        let count = max(1, model.slots.count)
        return CGFloat(count) * CapsuleChrome.buttonSize
            + CGFloat(max(0, count - 1)) * CapsuleChrome.itemSpacing
    }

    private var footer: CGFloat {
        CapsuleChrome.footerGap + CapsuleChrome.plusHeight + CapsuleChrome.footerSpacing + CapsuleChrome.buttonSize
    }

    private var maxSlotArea: CGFloat {
        max(CapsuleChrome.buttonSize, CapsuleChrome.dockMaxHeight - CapsuleChrome.verticalPadding * 2 - footer)
    }

    var body: some View {
        VStack(spacing: 0) {
            slotList
            Spacer(minLength: CapsuleChrome.footerGap)
            VStack(spacing: CapsuleChrome.footerSpacing) {
                plusMenu
                gearButton
            }
        }
        .frame(width: CapsuleChrome.dockWidth)
        .frame(maxHeight: CapsuleChrome.dockMaxHeight)
        .padding(.vertical, CapsuleChrome.verticalPadding)
        .glassEffect(.clear, in: .capsule)
        .materialActiveAppearance(.active)
        .frame(width: CapsuleChrome.panelWidth)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var slotList: some View {
        if slotStack > maxSlotArea {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: CapsuleChrome.itemSpacing) {
                    ForEach(model.slots) { slot in
                        dockButton(slot)
                    }
                }
            }
            .frame(height: maxSlotArea)
        } else {
            VStack(spacing: CapsuleChrome.itemSpacing) {
                ForEach(model.slots) { slot in
                    dockButton(slot)
                }
            }
        }
    }

    private var plusMenu: some View {
        Menu {
            Button("Cursor", systemImage: "plus") { model.create("cursor") }
            Button("Grok Bot", systemImage: "plus") { model.create("grok-bot") }
            Button("小猫", systemImage: "plus") { model.create("mochi") }
            Button("Codex", systemImage: "plus") { model.create("codex") }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: CapsuleChrome.addSymbol)
                    .font(.system(size: 19))
                    .foregroundStyle(.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
            }
            .frame(width: CapsuleChrome.buttonSize, height: CapsuleChrome.plusHeight)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .help("New chat")
        .accessibilityLabel("New chat")
    }

    private var gearButton: some View {
        Button {
            model.onSettings?()
        } label: {
            Image(systemName: CapsuleChrome.settingsSymbol)
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .frame(width: CapsuleChrome.buttonSize, height: CapsuleChrome.buttonSize)
        }
        .buttonStyle(.plain)
        .help("Settings")
        .accessibilityLabel("Settings")
    }

    private func dockButton(_ slot: CapsuleSlot) -> some View {
        let isSelected = model.selected == slot.id
        let isHovered = hoveredID == slot.id
        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
                model.choose(slot.id)
            }
        } label: {
            Group {
                if let image = slot.image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: CapsuleChrome.face, height: CapsuleChrome.face)
                } else {
                    Image(systemName: slot.symbol ?? "circle")
                        .font(.system(size: CapsuleChrome.iconSize))
                        .foregroundStyle(.white)
                }
            }
            .scaleEffect(isHovered ? 1.08 : 1)
            .frame(width: CapsuleChrome.buttonSize, height: CapsuleChrome.buttonSize)
            .background {
                if isSelected {
                    Circle()
                        .fill(.white.opacity(0.25))
                        .matchedGeometryEffect(id: "selection", in: selectionAnimation)
                } else if isHovered {
                    Circle()
                        .fill(.white.opacity(0.10))
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(SlotFace.label(title: slot.title, source: slot.source))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                hoveredID = hovering ? slot.id : nil
            }
            if !model.popupOpen {
                model.onHover?(hovering ? slot.id : nil)
            }
        }
        .accessibilityLabel(SlotFace.label(title: slot.title, source: slot.source))
    }
}

#Preview("Capsule") {
    let model = CapsuleModel()
    model.slots = [
        CapsuleSlot(id: "a", source: "cursor", title: "Cursor", image: nil),
        CapsuleSlot(id: "b", source: "grok-bot", title: "Grok Bot", image: nil),
        CapsuleSlot(id: "c", source: "mochi", title: "小猫", image: nil),
        CapsuleSlot(id: "d", source: "codex", title: "Codex", image: nil, symbol: "circle")
    ]
    model.selected = "a"
    return CapsuleRoot(model: model)
        .frame(width: CapsuleChrome.panelWidth, height: 320)
}
