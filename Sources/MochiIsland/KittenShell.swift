import AppKit
import MochiCore
import SwiftUI

struct KittenRow: Identifiable, Equatable {
    var id: String
    var source: String
    var title: String
    var status: String
    var read: Bool
    var icon: NSImage?

    var showsDot: Bool {
        !read && (status == "wait" || status == "done" || status == "fail")
    }
}

@MainActor
final class KittenModel: ObservableObject {
    @Published var expanded = false
    @Published var rows: [KittenRow] = []
    @Published var selected = ""
    @Published var scroll: CGFloat = 0
    @Published var viewport: CGFloat = 0
    @Published var capsuleHeight: CGFloat = AppConfig.kittenSize
}

final class KittenMouseView: NSView {
    var shadowPad: CGFloat = 0
    var onDown: (() -> Void)?
    var onDrag: ((CGSize) -> Void)?
    var onUp: ((Bool, NSPoint) -> Void)?
    var onScroll: ((CGFloat) -> Void)?
    private var origin = NSPoint.zero

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let capsule = bounds.insetBy(dx: shadowPad, dy: shadowPad)
        return capsule.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        origin = NSEvent.mouseLocation
        onDown?()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        onDrag?(CGSize(width: point.x - origin.x, height: point.y - origin.y))
    }

    override func mouseUp(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        let delta = CGSize(width: point.x - origin.x, height: point.y - origin.y)
        let dragged = hypot(delta.width, delta.height) >= AppConfig.dragThreshold
        onUp?(dragged, convert(event.locationInWindow, from: nil))
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 8
        onScroll?(delta)
    }
}

struct KittenRoot: View {
    @ObservedObject var model: KittenModel
    @Namespace private var kittenNS
    @Namespace private var selectionNS

    private var spring: Animation {
        .spring(response: 0.32, dampingFraction: 0.78)
    }

    var body: some View {
        let height = model.expanded ? model.capsuleHeight : AppConfig.kittenSize
        VStack(spacing: 0) {
            kittenWell
            if model.expanded {
                menu
                    .transition(.opacity)
            }
        }
        .frame(width: AppConfig.capsuleWidth, height: height, alignment: .top)
        .background {
            if model.expanded {
                GlassEffectContainer {
                    Capsule(style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular, in: .capsule)
                        .matchedGeometryEffect(id: "kitten-base", in: kittenNS)
                }
                .allowsHitTesting(false)
            }
        }
        .animation(spring, value: model.expanded)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Collapsed is the artwork alone. The glass capsule exists only after the kitten is opened.
    private var kittenWell: some View {
        ZStack {
            FullKitten()
                .frame(width: AppConfig.kittenSize, height: AppConfig.kittenSize)
                .matchedGeometryEffect(id: "kitten-art", in: kittenNS)
            if model.rows.contains(where: \.showsDot) {
                Circle()
                    .fill(Color(red: 1, green: 59 / 255, blue: 48 / 255))
                    .frame(width: AppConfig.unreadDot, height: AppConfig.unreadDot)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(6)
            }
        }
        .frame(width: AppConfig.kittenSize, height: AppConfig.kittenSize)
    }

    private var menu: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: AppConfig.dividerGap)
            Capsule()
                .fill(Color.primary.opacity(0.22))
                .frame(width: AppConfig.dividerWidth, height: AppConfig.dividerHeight)
            Color.clear.frame(height: AppConfig.dividerGap)
            VStack(spacing: AppConfig.rowGap) {
                ForEach(model.rows) { row in
                    agentRow(row)
                }
            }
            .offset(y: -model.scroll)
            .frame(height: model.rows.isEmpty ? 0 : model.viewport, alignment: .top)
            .clipped()
            .padding(.bottom, model.rows.isEmpty ? 0 : AppConfig.rowGap)
            symbol("plus", label: "Add")
            Color.clear.frame(height: AppConfig.rowGap)
            symbol("gearshape", label: "Settings")
            Color.clear.frame(height: AppConfig.capsulePadY)
        }
    }

    private func agentRow(_ row: KittenRow) -> some View {
        let selected = model.selected == row.id
        return ZStack {
            if selected {
                RoundedRectangle(cornerRadius: AppConfig.selectedRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.14))
                    .matchedGeometryEffect(id: "agent-selection", in: selectionNS)
            }
            ZStack(alignment: .topTrailing) {
                rowIcon(row)
                    .frame(width: AppConfig.agentIcon, height: AppConfig.agentIcon)
                if row.showsDot {
                    Circle()
                        .fill(Color(red: 1, green: 59 / 255, blue: 48 / 255))
                        .frame(width: AppConfig.unreadDot, height: AppConfig.unreadDot)
                        .offset(x: 3, y: -3)
                }
            }
        }
        .frame(width: AppConfig.agentIcon + 8, height: AppConfig.agentRow)
        .accessibilityLabel(row.title)
    }

    @ViewBuilder
    private func rowIcon(_ row: KittenRow) -> some View {
        if let icon = row.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: AppConfig.agentIcon, height: AppConfig.agentIcon)
        } else {
            AgentMark(source: row.source)
        }
    }

    private func symbol(_ name: String, label: String) -> some View {
        Image(systemName: name)
            .font(.system(size: AppConfig.symbolSize, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: AppConfig.capsuleWidth - AppConfig.capsulePadX * 2, height: AppConfig.controlRow)
            .accessibilityLabel(label)
    }
}

@MainActor
final class KittenShell: NSObject {
    static let materialAPI = AppConfig.materialAPI
    static let addSymbol = "plus"
    static let settingsSymbol = "gearshape"
    static let shadowPad: CGFloat = 0

    let panel: CapsulePanel
    private let model: KittenModel
    private let mouse: KittenMouseView
    private let hosting: NSHostingView<KittenRoot>
    private let bubble = BubblePanel()
    private var anchor = CGPoint.zero
    private var positioned = false
    private var positionToken = ""
    private var dragging = false
    private var dragFrame = NSRect.zero
    private var remembered: [String: String] = [:]
    private var timbre = "boop"
    private var dock = "right"
    private var monitors: [Any] = []
    private weak var host: NSWindow?
    private var iconCache: [String: NSImage] = [:]
    private var springTimer: Timer?
    private var springHeight: CGFloat = AppConfig.kittenSize
    private var springVelocity: CGFloat = 0
    private var springTarget: NSRect?

    var onSettings: (() -> Void)?
    var onChoice: (([String: Any]) -> [String: Any])?
    var onOpenAgent: ((String, String) -> Void)?
    var onOpenApp: ((String) -> Void)?
    var onPosition: ((Double, Double) -> Void)?
    var onRead: ((String) -> Void)?
    var onRetire: (() -> Void)?
    var protectedFrames: () -> [NSRect] = { [] }

    var interactiveBubbleFrame: NSRect? {
        guard bubble.visible else { return nil }
        return bubble.panel.frame
    }

    var hitFrame: NSRect {
        let pad = model.expanded ? Self.shadowPad : 0
        return panel.frame.insetBy(dx: pad, dy: pad)
    }

    override init() {
        let model = KittenModel()
        let panel = CapsulePanel(
            contentRect: NSRect(x: 0, y: 0, width: AppConfig.kittenSize, height: AppConfig.kittenSize),
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
        panel.title = "Mochi"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: KittenRoot(model: model))
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        let mouse = KittenMouseView(frame: hosting.bounds)
        mouse.wantsLayer = true
        mouse.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.frame = mouse.bounds
        hosting.autoresizingMask = [.width, .height]
        mouse.addSubview(hosting)
        panel.contentView = mouse
        self.panel = panel
        self.model = model
        self.mouse = mouse
        self.hosting = hosting
        super.init()
        wireMouse()
        wireBubble()
        installMonitors()
    }

    func attach(to host: NSWindow) {
        if let current = self.host {
            current.removeChildWindow(panel)
            current.removeChildWindow(bubble.panel)
        }
        self.host = host
        panel.collectionBehavior = host.collectionBehavior
        host.addChildWindow(panel, ordered: .above)
        bubble.attach(to: host)
        panel.orderFrontRegardless()
        ensurePosition()
        layout()
    }

    func apply(prefs: IslandPrefs, force: Bool = false) {
        timbre = IslandPrefs.soundIDs.contains(prefs.sound) ? prefs.sound : "boop"
        dock = prefs.dock == "left" ? "left" : "right"
        let token = "\(prefs.kittenPlaced)|\(prefs.kittenX)|\(prefs.kittenY)|\(dock)"
        guard force || token != positionToken || !positioned else { return }
        positionToken = token
        let boxes = canvas()
        if prefs.kittenPlaced {
            anchor = ShellGeometry.anchor(x: prefs.kittenX, y: prefs.kittenY, screen: boxes.full)
        } else if dock == "left" {
            anchor = ShellGeometry.leftAnchor(screen: boxes.full, visible: boxes.visible)
        } else {
            anchor = ShellGeometry.defaultAnchor(screen: boxes.full, visible: boxes.visible)
        }
        anchor = ShellGeometry.clampCenter(anchor, size: AppConfig.kittenSize, visible: boxes.visible)
        positioned = true
        layout()
    }

    func sync(slots: [[String: Any]], selected: String, tasks: [[String: Any]], dock: String) {
        self.dock = dock == "left" ? "left" : "right"
        rememberTasks(tasks)
        var taskByID: [String: [String: Any]] = [:]
        for task in tasks {
            let id = string(task["id"])
            if !id.isEmpty {
                taskByID[id] = task
                let status = string(task["status"])
                if !status.isEmpty { remembered[id] = status }
            }
        }
        model.rows = slots.compactMap { raw in
            let id = string(raw["id"])
            guard !id.isEmpty else { return nil }
            let source = AgentLaunch.normalize(string(raw["source"]))
            if source == "mochi" && taskByID[id] == nil { return nil }
            let task = taskByID[id]
            let status = task.map { string($0["status"]) } ?? remembered[id] ?? ""
            if task == nil && status.isEmpty && id.hasPrefix("seed-") { return nil }
            let title = string(raw["title"])
            return KittenRow(
                id: id,
                source: source,
                title: title.isEmpty ? SlotFace.displayName(for: source) : title,
                status: status,
                read: bool(raw["read"]),
                icon: cachedIcon(source)
            )
        }
        if !model.selected.isEmpty, !model.rows.contains(where: { $0.id == model.selected }) {
            model.selected = ""
        }
        if model.selected.isEmpty, !selected.isEmpty, model.rows.contains(where: { $0.id == selected }) {
            model.selected = selected
        }
        ensurePosition()
        if !dragging { layout() }
        if bubble.visible { repositionBubble() }
    }

    func layoutInHost() {
        ensurePosition()
        layout()
    }

    func noteHover(at screenPoint: NSPoint) {}

    func hideTip() {}

    func hideCard() {
        closeBubble(retire: false)
    }

    func revealSelected() {
        model.expanded = true
        layout()
        guard let index = model.rows.firstIndex(where: { $0.id == model.selected }) else { return }
        showCard(index: index, kind: .card, sound: false)
    }

    func presentAlert(id: String) {
        guard let index = model.rows.firstIndex(where: { $0.id == id }) else { return }
        showCard(index: index, kind: .alert, sound: false)
        let event: SoundPlayer.Event = model.rows[index].status == "done" ? .done : .alert
        SoundPlayer.shared.play(event, timbre: timbre)
    }

    func chromePayload(in host: NSWindow) -> [String: Any] {
        let frame = hitFrame
        return [
            "dock": anchor.x < (canvas().full.midX) ? "left" : "right",
            "material": Self.materialAPI,
            "capsule": css(frame, host: host),
            "selected": model.selected,
            "popupOpen": bubble.visible,
            "menuCount": 0,
            "capsuleW": AppConfig.capsuleWidth,
            "kitten": AppConfig.kittenSize,
            "addSymbol": Self.addSymbol,
            "gearSymbol": Self.settingsSymbol
        ]
    }

    func metrics() -> [String: Any] {
        [
            "material": Self.materialAPI,
            "capsuleW": Int(AppConfig.capsuleWidth),
            "slotW": Int(AppConfig.capsuleWidth),
            "slotH": Int(AppConfig.agentRow),
            "faceW": Int(AppConfig.agentIcon),
            "faceH": Int(AppConfig.agentIcon),
            "slotGap": Int(AppConfig.rowGap),
            "addW": Int(AppConfig.controlRow),
            "gearW": Int(AppConfig.controlRow),
            "kitten": Int(AppConfig.kittenSize),
            "kittenMark": Int(AppConfig.kittenMark),
            "rowH": Int(AppConfig.agentRow),
            "icon": Int(AppConfig.agentIcon),
            "rowGap": Int(AppConfig.rowGap),
            "radius": Int(AppConfig.capsuleRadius),
            "menuCount": 0,
            "addSymbol": Self.addSymbol,
            "gearSymbol": Self.settingsSymbol,
            "bubbleRadius": Int(AppConfig.bubbleRadius),
            "beakW": Int(AppConfig.beakWidth),
            "beakH": Int(AppConfig.beakHeight),
            "beakGap": Int(AppConfig.beakGap),
            "bubbleMinW": Int(AppConfig.bubbleMinWidth),
            "bubbleMaxW": Int(AppConfig.bubbleMaxWidth)
        ]
    }

    private func wireMouse() {
        mouse.onDown = { [weak self] in
            guard let self else { return }
            self.dragFrame = self.hitFrame
            self.dragging = false
        }
        mouse.onDrag = { [weak self] delta in
            guard let self else { return }
            if hypot(delta.width, delta.height) < AppConfig.dragThreshold { return }
            self.dragging = true
            var frame = self.dragFrame
            frame.origin.x += delta.width
            frame.origin.y += delta.height
            let visible = self.canvas().visible
            frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.minX, visible.maxX - frame.width))
            frame.origin.y = min(max(frame.origin.y, visible.minY), max(visible.minY, visible.maxY - frame.height))
            self.panel.setFrame(frame, display: true)
            self.anchor = CGPoint(x: frame.midX, y: frame.maxY - AppConfig.kittenSize / 2)
            self.repositionBubble()
        }
        mouse.onUp = { [weak self] dragged, local in
            guard let self else { return }
            if dragged {
                let ratios = ShellGeometry.ratios(anchor: self.anchor, screen: self.canvas().full)
                self.positionToken = "true|\(ratios.x)|\(ratios.y)|\(ratios.x < 0.5 ? "left" : "right")"
                self.dock = ratios.x < 0.5 ? "left" : "right"
                self.onPosition?(ratios.x, ratios.y)
                self.layout()
            } else {
                self.click(at: local)
            }
            self.dragging = false
        }
        mouse.onScroll = { [weak self] delta in
            guard let self, self.model.expanded else { return }
            let count = self.model.rows.count
            let block: CGFloat = count == 0 ? 0 : CGFloat(count) * AppConfig.agentRow + CGFloat(count - 1) * AppConfig.rowGap
            let maxScroll = max(0, block - self.model.viewport)
            self.model.scroll = min(max(0, self.model.scroll - delta), maxScroll)
        }
    }

    private func wireBubble() {
        bubble.model.onChoice = { [weak self] option in
            guard let self else { return }
            SoundPlayer.shared.play(.choice, timbre: self.timbre)
            let payload: [String: Any] = [
                "id": self.bubble.model.taskID,
                "kind": self.bubble.model.taskKind,
                "request_id": self.bubble.model.requestID,
                "question_id": self.bubble.model.questionID,
                "option_id": option.id,
                "label": option.label
            ]
            let result = self.onChoice?(payload) ?? [:]
            self.onRead?(self.bubble.model.taskID)
            self.bubble.model.options = []
            let failed = (result["ok"] as? Bool) == false
            self.bubble.model.status = failed ? "Could not save" : "Sent"
            self.bubble.model.summary = option.label
            self.repositionBubble()
        }
        bubble.model.onOpen = { [weak self] in
            guard let self else { return }
            self.onRead?(self.bubble.model.taskID)
            self.onOpenAgent?(self.bubble.model.source, self.bubble.model.taskID)
        }
        bubble.model.onPick = { [weak self] source in
            guard let self else { return }
            self.onOpenApp?(source)
            self.closeBubble(retire: false)
        }
    }

    private func installMonitors() {
        let down = NSEvent.EventTypeMask([.leftMouseDown, .rightMouseDown])
        if let local = NSEvent.addLocalMonitorForEvents(matching: down, handler: { [weak self] event in
            self?.outside(NSEvent.mouseLocation)
            if event.type == .keyDown { return event }
            return event
        }) {
            monitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: down, handler: { [weak self] _ in
            self?.outside(NSEvent.mouseLocation)
        }) {
            monitors.append(global)
        }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.collapseFromOutside()
            return nil
        }) {
            monitors.append(keys)
        }
    }

    private func outside(_ point: NSPoint) {
        if hitFrame.insetBy(dx: -4, dy: -4).contains(point) { return }
        if let bubbleFrame = interactiveBubbleFrame, bubbleFrame.insetBy(dx: -4, dy: -4).contains(point) { return }
        if protectedFrames().contains(where: { $0.insetBy(dx: -4, dy: -4).contains(point) }) { return }
        collapseFromOutside()
    }

    private func collapseFromOutside() {
        let wasOpen = model.expanded || bubble.visible
        closeBubble(retire: true)
        guard model.expanded else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            model.expanded = false
        }
        layout(animated: true)
        if wasOpen { SoundPlayer.shared.play(.close, timbre: timbre) }
    }

    private func click(at local: NSPoint) {
        switch hitTarget(local) {
        case .kitten:
            if model.expanded {
                closeBubble(retire: true)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    model.expanded = false
                }
                SoundPlayer.shared.play(.close, timbre: timbre)
            } else {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    model.expanded = true
                }
                SoundPlayer.shared.play(.open, timbre: timbre)
            }
            layout(animated: true)
        case .agent(let index):
            toggleAgent(index)
        case .plus:
            togglePicker()
        case .gear:
            onSettings?()
        case nil:
            break
        }
    }

    private func toggleAgent(_ index: Int) {
        guard model.rows.indices.contains(index) else { return }
        let row = model.rows[index]
        if bubble.visible && model.selected == row.id {
            closeBubble(retire: true)
            return
        }
        showCard(index: index, kind: .card, sound: true)
        onRead?(row.id)
        model.rows[index].read = true
    }

    private func togglePicker() {
        if bubble.visible && bubble.model.kind == .picker {
            closeBubble(retire: false)
            return
        }
        model.selected = ""
        bubble.model.kind = .picker
        bubble.model.title = "Open"
        bubble.model.appName = ""
        bubble.model.summary = ""
        bubble.model.status = ""
        bubble.model.options = []
        bubble.model.taskID = ""
        SoundPlayer.shared.play(.select, timbre: timbre)
        bubble.show(anchor: plusFrame(), screen: canvas().visible)
    }

    private func showCard(index: Int, kind: BubbleKind, sound: Bool) {
        guard model.rows.indices.contains(index) else { return }
        let row = model.rows[index]
        model.selected = row.id
        let task = taskFields(for: row)
        bubble.model.kind = kind
        bubble.model.title = row.title
        bubble.model.appName = SlotFace.displayName(for: row.source)
        bubble.model.source = row.source
        bubble.model.icon = row.icon
        bubble.model.status = statusLine(row.status)
        bubble.model.summary = task.summary
        bubble.model.options = task.options
        bubble.model.taskID = row.id
        bubble.model.requestID = task.requestID
        bubble.model.questionID = task.questionID
        bubble.model.taskKind = task.kind
        if sound { SoundPlayer.shared.play(.select, timbre: timbre) }
        let anchor = model.expanded ? iconFrame(index) : hitFrame
        bubble.show(anchor: anchor, screen: canvas().visible)
    }

    private func closeBubble(retire: Bool) {
        let was = bubble.visible
        bubble.hide()
        model.selected = ""
        if was && retire { onRetire?() }
    }

    private func repositionBubble() {
        guard bubble.visible else { return }
        let anchor: CGRect
        if bubble.model.kind == .picker {
            anchor = plusFrame()
        } else if model.expanded, let index = model.rows.firstIndex(where: { $0.id == model.selected }) {
            anchor = iconFrame(index)
        } else {
            anchor = model.expanded ? hitFrame : hitFrame
        }
        bubble.show(anchor: anchor, screen: canvas().visible)
    }

    private func layout(animated: Bool = false) {
        let boxes = canvas()
        let placed = ShellGeometry.placeCapsule(
            anchorCenter: anchor,
            expanded: model.expanded,
            agentCount: model.rows.count,
            visible: boxes.visible
        )
        let count = model.rows.count
        let block: CGFloat = count == 0 ? 0 : CGFloat(count) * AppConfig.agentRow + CGFloat(count - 1) * AppConfig.rowGap
        let tops = ShellGeometry.stack(agentCount: count)
        let tail = (count == 0 ? 0 : AppConfig.rowGap) + AppConfig.controlRow + AppConfig.rowGap + AppConfig.controlRow + AppConfig.capsulePadY
        mouse.shadowPad = 0
        if dragging {
            stopSpring()
            applyFrame(placed.frame, agentBlock: block, agentsTop: tops.agents, tail: tail)
            return
        }
        if animated || springTimer != nil {
            if springTimer == nil {
                springHeight = panel.frame.height
                springVelocity = 0
            }
            springTarget = placed.frame
            startSpring(agentBlock: block, agentsTop: tops.agents, tail: tail)
            return
        }
        applyFrame(placed.frame, agentBlock: block, agentsTop: tops.agents, tail: tail)
    }

    private func applyFrame(_ frame: NSRect, agentBlock: CGFloat, agentsTop: CGFloat, tail: CGFloat) {
        let available = max(0, frame.height - agentsTop - tail)
        model.capsuleHeight = frame.height
        model.viewport = model.expanded ? min(agentBlock, available) : 0
        model.scroll = min(model.scroll, max(0, agentBlock - model.viewport))
        panel.setFrame(frame, display: true)
        mouse.frame = NSRect(origin: .zero, size: frame.size)
        hosting.frame = mouse.bounds
    }

    private func startSpring(agentBlock: CGFloat, agentsTop: CGFloat, tail: CGFloat) {
        guard springTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stepSpring(agentBlock: agentBlock, agentsTop: agentsTop, tail: tail)
            }
        }
        springTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stepSpring(agentBlock: CGFloat, agentsTop: CGFloat, tail: CGFloat) {
        guard let target = springTarget else {
            stopSpring()
            return
        }
        let dt = 1.0 / 60.0
        let response = 0.42
        let damping = 0.78
        let omega = 2 * Double.pi / response
        let delta = Double(target.height - springHeight)
        let accel = omega * omega * delta - 2 * damping * omega * Double(springVelocity)
        springVelocity += CGFloat(accel * dt)
        springHeight += CGFloat(Double(springVelocity) * dt)
        if springHeight < AppConfig.kittenSize { springHeight = AppConfig.kittenSize }
        if abs(delta) < 0.6, abs(springVelocity) < 14 {
            springHeight = target.height
            stopSpring()
        }
        let frame = NSRect(
            x: target.minX,
            y: target.maxY - springHeight,
            width: target.width,
            height: springHeight
        )
        applyFrame(frame, agentBlock: agentBlock, agentsTop: agentsTop, tail: tail)
    }

    private func stopSpring() {
        springTimer?.invalidate()
        springTimer = nil
        springVelocity = 0
    }

    private func ensurePosition() {
        guard !positioned else { return }
        let boxes = canvas()
        anchor = dock == "left"
            ? ShellGeometry.leftAnchor(screen: boxes.full, visible: boxes.visible)
            : ShellGeometry.defaultAnchor(screen: boxes.full, visible: boxes.visible)
        positioned = true
    }

    private func canvas() -> (full: CGRect, visible: CGRect) {
        if let host, host.frame.maxX < 0 || host.frame.minX < -500 {
            return (host.frame, host.frame)
        }
        let screen = host?.screen ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        let resolved = screen ?? NSScreen.screens[0]
        return (resolved.frame, resolved.visibleFrame)
    }

    private enum Hit {
        case kitten, agent(Int), plus, gear
    }

    private func hitTarget(_ local: NSPoint) -> Hit? {
        let pad = model.expanded ? Self.shadowPad : 0
        let fromTop = mouse.bounds.height - local.y - pad
        guard fromTop >= 0 else { return nil }
        if !model.expanded { return .kitten }
        let tops = ShellGeometry.stack(agentCount: model.rows.count)
        if fromTop < tops.agents { return .kitten }
        let plusTop = tops.agents + (model.rows.isEmpty ? 0 : model.viewport + AppConfig.rowGap)
        if !model.rows.isEmpty && fromTop < plusTop - AppConfig.rowGap {
            let contentY = fromTop - tops.agents + model.scroll
            let stride = AppConfig.agentRow + AppConfig.rowGap
            let index = Int(contentY / stride)
            let within = contentY - CGFloat(index) * stride
            guard index >= 0, index < model.rows.count, within <= AppConfig.agentRow else { return nil }
            return .agent(index)
        }
        if fromTop >= plusTop && fromTop < plusTop + AppConfig.controlRow { return .plus }
        let gearTop = plusTop + AppConfig.controlRow + AppConfig.rowGap
        if fromTop >= gearTop && fromTop < gearTop + AppConfig.controlRow { return .gear }
        return nil
    }

    private func iconFrame(_ index: Int) -> CGRect {
        let tops = ShellGeometry.stack(agentCount: model.rows.count)
        let contentY = CGFloat(index) * (AppConfig.agentRow + AppConfig.rowGap) - model.scroll
        let fromTop = tops.agents + contentY + (AppConfig.agentRow - AppConfig.agentIcon) / 2
        let capsule = hitFrame
        let y = capsule.maxY - fromTop - AppConfig.agentIcon
        let x = capsule.minX + (AppConfig.capsuleWidth - AppConfig.agentIcon) / 2
        return CGRect(x: x, y: y, width: AppConfig.agentIcon, height: AppConfig.agentIcon)
    }

    private func plusFrame() -> CGRect {
        let tops = ShellGeometry.stack(agentCount: model.rows.count)
        let plusTop = tops.agents + (model.rows.isEmpty ? 0 : model.viewport + AppConfig.rowGap)
        let capsule = hitFrame
        let y = capsule.maxY - plusTop - AppConfig.controlRow
        return CGRect(x: capsule.minX, y: y, width: capsule.width, height: AppConfig.controlRow)
    }

    private func cachedIcon(_ source: String) -> NSImage? {
        if let cached = iconCache[source] { return cached }
        let image = AgentIcon.image(source: source)
        if let image { iconCache[source] = image }
        return image
    }

    private struct TaskFields {
        var summary = ""
        var options: [BubbleChoice] = []
        var requestID = ""
        var questionID = ""
        var kind = ""
    }

    private func taskFields(for row: KittenRow) -> TaskFields {
        var fields = TaskFields()
        guard let task = taskCache[row.id] else { return fields }
        let prompt = string(task["prompt"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = string(task["detail"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty {
            fields.summary = prompt
        } else if !detail.isEmpty, detail != row.title {
            fields.summary = detail
        }
        fields.requestID = string(task["request_id"])
        fields.questionID = string(task["question_id"])
        fields.kind = string(task["kind"])
        fields.options = choices(task["options"])
        if fields.options.isEmpty, row.status == "wait", fields.kind == "permission" {
            fields.options = [
                BubbleChoice(id: "allow", label: "Allow"),
                BubbleChoice(id: "deny", label: "Deny")
            ]
        }
        return fields
    }

    private func choices(_ value: Any?) -> [BubbleChoice] {
        let rows: [[String: Any]]
        if let typed = value as? [[String: Any]] {
            rows = typed
        } else if let typed = value as? [[String: String]] {
            rows = typed.map { $0 as [String: Any] }
        } else {
            return []
        }
        return rows.compactMap { item in
            let label = string(item["label"])
            guard !label.isEmpty else { return nil }
            return BubbleChoice(id: string(item["id"]), label: label)
        }
    }

    private var taskCache: [String: [String: Any]] = [:]

    private func rememberTasks(_ tasks: [[String: Any]]) {
        taskCache = [:]
        for task in tasks {
            let id = string(task["id"])
            if !id.isEmpty { taskCache[id] = task }
        }
    }

    private func statusLine(_ status: String) -> String {
        switch status {
        case "running": return "Running"
        case "wait": return "Waiting"
        case "done": return "Done"
        case "fail": return "Failed"
        default: return ""
        }
    }

    private func css(_ rect: NSRect, host: NSWindow) -> [String: Any] {
        let x = rect.minX - host.frame.minX
        let y = host.frame.height - (rect.minY - host.frame.minY) - rect.height
        return ["x": x, "y": y, "w": rect.width, "h": rect.height, "left": x, "top": y, "right": x + rect.width, "bottom": y + rect.height]
    }

    private func string(_ value: Any?) -> String {
        value as? String ?? ""
    }

    private func bool(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return false
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
