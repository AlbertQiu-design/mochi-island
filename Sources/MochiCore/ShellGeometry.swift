import CoreGraphics
import Foundation

/// Screen math for the kitten shell. Coordinates are y-up, origin at the bottom left.
public enum ShellGeometry {
    public static func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    public static func ratios(anchor: CGPoint, screen: CGRect) -> (x: Double, y: Double) {
        let width = Double(screen.width)
        let height = Double(screen.height)
        let x = width == 0 ? 0.5 : (Double(anchor.x) - Double(screen.minX)) / width
        let y = height == 0 ? 0.5 : (Double(anchor.y) - Double(screen.minY)) / height
        return (clamp01(x), clamp01(y))
    }

    public static func anchor(x: Double, y: Double, screen: CGRect) -> CGPoint {
        CGPoint(
            x: screen.minX + CGFloat(clamp01(x)) * screen.width,
            y: screen.minY + CGFloat(clamp01(y)) * screen.height
        )
    }

    /// 8pt in from the right edge, vertically centered, then clamped so the 56pt kitten stays visible.
    public static func defaultAnchor(screen: CGRect, visible: CGRect) -> CGPoint {
        let raw = CGPoint(x: screen.maxX - AppConfig.screenInset - AppConfig.kittenSize / 2, y: screen.midY)
        return clampCenter(raw, size: AppConfig.kittenSize, visible: visible)
    }

    public static func leftAnchor(screen: CGRect, visible: CGRect) -> CGPoint {
        let raw = CGPoint(x: screen.minX + AppConfig.screenInset + AppConfig.kittenSize / 2, y: screen.midY)
        return clampCenter(raw, size: AppConfig.kittenSize, visible: visible)
    }

    public static func clampCenter(_ center: CGPoint, size: CGFloat, visible: CGRect) -> CGPoint {
        let half = size / 2
        let x = min(max(center.x, visible.minX + half), visible.maxX - half)
        let y = min(max(center.y, visible.minY + half), visible.maxY - half)
        return CGPoint(x: x, y: y)
    }

    /// Height of the open capsule. The top 56pt is the kitten's circular base; the menu grows below it.
    public static func contentHeight(agentCount: Int) -> CGFloat {
        let count = max(0, agentCount)
        let agents: CGFloat = count == 0
            ? 0
            : CGFloat(count) * AppConfig.agentRow + CGFloat(count - 1) * AppConfig.rowGap
        let beforePlus: CGFloat = count == 0 ? 0 : AppConfig.rowGap
        return AppConfig.kittenSize
            + AppConfig.dividerGap
            + AppConfig.dividerHeight
            + AppConfig.dividerGap
            + agents
            + beforePlus
            + AppConfig.controlRow
            + AppConfig.rowGap
            + AppConfig.controlRow
            + AppConfig.capsulePadY
    }

    /// Distances from the top of the capsule. The kitten occupies the top 56pt and does not move when the menu opens.
    public static func stack(agentCount: Int) -> (kitten: CGFloat, divider: CGFloat, agents: CGFloat, plus: CGFloat, gear: CGFloat) {
        let kitten: CGFloat = 0
        let divider = AppConfig.kittenSize + AppConfig.dividerGap
        let agents = divider + AppConfig.dividerHeight + AppConfig.dividerGap
        let count = max(0, agentCount)
        let block: CGFloat = count == 0
            ? 0
            : CGFloat(count) * AppConfig.agentRow + CGFloat(max(0, count - 1)) * AppConfig.rowGap
        let plus = agents + block + (count == 0 ? 0 : AppConfig.rowGap)
        let gear = plus + AppConfig.controlRow + AppConfig.rowGap
        return (kitten, divider, agents, plus, gear)
    }

    /// Expanded frames keep the collapsed kitten's top edge and grow downward.
    public static func placeCapsule(
        anchorCenter: CGPoint,
        expanded: Bool,
        agentCount: Int,
        visible: CGRect
    ) -> (frame: CGRect, scrolls: Bool) {
        let center = clampCenter(anchorCenter, size: AppConfig.kittenSize, visible: visible)
        let top = center.y + AppConfig.kittenSize / 2
        if !expanded {
            return (
                CGRect(
                    x: center.x - AppConfig.kittenSize / 2,
                    y: center.y - AppConfig.kittenSize / 2,
                    width: AppConfig.kittenSize,
                    height: AppConfig.kittenSize
                ),
                false
            )
        }
        let natural = contentHeight(agentCount: agentCount)
        let room = max(AppConfig.kittenSize, top - visible.minY)
        let height = min(natural, room)
        let scrolls = natural > height + 0.5
        let x = center.x - AppConfig.capsuleWidth / 2
        let y = top - height
        return (CGRect(x: x, y: y, width: AppConfig.capsuleWidth, height: height), scrolls)
    }
}

public struct BubblePlacement: Equatable {
    public var frame: CGRect
    public var beakY: CGFloat
    public var pointsRight: Bool

    public init(frame: CGRect, beakY: CGFloat, pointsRight: Bool) {
        self.frame = frame
        self.beakY = beakY
        self.pointsRight = pointsRight
    }
}

public enum BubblePlacer {
    /// Places the bubble beside `anchor`. The kitten's screen half picks the side.
    /// Beak y stays inside `[radius+8, height-radius-8]` after the bubble is clamped.
    public static func place(anchor: CGRect, size: CGSize, screen: CGRect) -> BubblePlacement {
        let width = max(1, size.width)
        let height = max(1, size.height)
        let onLeftHalf = anchor.midX < screen.midX
        let pointsRight = !onLeftHalf
        var x = pointsRight
            ? anchor.minX - AppConfig.beakGap - width
            : anchor.maxX + AppConfig.beakGap
        var y = anchor.midY - height / 2
        x = min(max(x, screen.minX), max(screen.minX, screen.maxX - width))
        y = min(max(y, screen.minY), max(screen.minY, screen.maxY - height))
        let frame = CGRect(x: x, y: y, width: width, height: height)
        let fromBottom = anchor.midY - frame.minY
        var beakFromTop = height - fromBottom
        let lower = AppConfig.bubbleRadius + 8
        let upper = height - AppConfig.bubbleRadius - 8
        if upper >= lower {
            beakFromTop = min(max(beakFromTop, lower), upper)
        } else {
            beakFromTop = height / 2
        }
        return BubblePlacement(frame: frame, beakY: beakFromTop, pointsRight: pointsRight)
    }
}

public struct AlertSoundGate: Equatable {
    public var last: Double?
    public init() {}

    public mutating func shouldPlay(now: Double) -> Bool {
        if let last, now - last < 1 { return false }
        self.last = now
        return true
    }
}
