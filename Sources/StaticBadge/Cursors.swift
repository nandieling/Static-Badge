import AppKit
import StaticBadgeCore

/// 裁剪框用的三个光标。
///
/// AppKit 公开 API 里没有对角缩放光标（`+[NSCursor moveCursor]` 在新 SDK 头文件里也不可见），
/// 这里自己画，保证 macOS 11 到最新版表现一致。
enum Cursors {
    static let move: NSCursor = arrowCursor(angles: [0, .pi / 2, .pi, 3 * .pi / 2])
    /// ↖↘ 方向（左上角、右下角手柄）。
    static let northwestSoutheast: NSCursor = arrowCursor(angles: [.pi / 4, -.pi / 4])
    /// ↗↙ 方向（右上角、左下角手柄）。
    static let northeastSouthwest: NSCursor = arrowCursor(angles: [3 * .pi / 4, -3 * .pi / 4])

    static func forCorner(_ corner: CropCorner) -> NSCursor {
        switch corner {
        case .topLeft, .bottomRight:
            return northwestSoutheast
        case .topRight, .bottomLeft:
            return northeastSouthwest
        }
    }

    private static let side: CGFloat = 19
    private static let center: CGFloat = 9.5
    private static let arm: CGFloat = 6.5
    private static let head: CGFloat = 4

    private static func arrowCursor(angles: [CGFloat]) -> NSCursor {
        let shape = NSBezierPath()
        shape.lineCapStyle = .round
        shape.lineJoinStyle = .round
        for angle in angles {
            let tip = point(angle: angle, length: arm)
            shape.move(to: point(angle: angle + .pi, length: arm * 0.55))
            shape.line(to: tip)
            shape.move(to: wing(of: tip, angle: angle, offset: 1))
            shape.line(to: tip)
            shape.line(to: wing(of: tip, angle: angle, offset: -1))
        }

        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        // 先描一圈白边再画深色，暗色图片上也看得清。
        NSColor.white.setStroke()
        shape.lineWidth = 3.4
        shape.stroke()
        NSColor(white: 0.12, alpha: 1).setStroke()
        shape.lineWidth = 1.4
        shape.stroke()
        image.unlockFocus()

        return NSCursor(image: image, hotSpot: NSPoint(x: center, y: center))
    }

    private static func point(angle: CGFloat, length: CGFloat) -> NSPoint {
        NSPoint(x: center + length * cos(angle), y: center + length * sin(angle))
    }

    private static func wing(of tip: NSPoint, angle: CGFloat, offset: CGFloat) -> NSPoint {
        let spread = angle + offset * (5 * .pi / 6)
        return NSPoint(x: tip.x + head * cos(spread), y: tip.y + head * sin(spread))
    }
}
