import AppKit
import StaticBadgeCore

/// 画布：等比绘制图片，并叠上正方形裁剪框、内切圆和四角控制点。
///
/// 裁剪框以图像像素坐标保存，缩放窗口只改变绘制比例，不会改变裁剪结果。
final class CropCanvasView: NSView {
    private static let squareColor = NSColor(srgbRed: 46 / 255, green: 204 / 255, blue: 113 / 255, alpha: 1)
    private static let circleColor = NSColor(srgbRed: 52 / 255, green: 152 / 255, blue: 219 / 255, alpha: 1)
    private static let handleFill = NSColor.white
    private static let handleStroke = NSColor(srgbRed: 20 / 255, green: 20 / 255, blue: 20 / 255, alpha: 1)
    private static let lineWidth: CGFloat = 2
    private static let handleLineWidth: CGFloat = 1

    /// 画布底色：比窗口背景再沉一点，圆角容器里看起来像一块“取景区”。
    private static let background = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return dark
            ? NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1)
            : NSColor(srgbRed: 0.937, green: 0.937, blue: 0.945, alpha: 1)
    }
    /// 内切圆以外压暗用的那层。
    private static let scrim = NSColor(white: 0, alpha: 0.22)
    private static let accent = circleColor

    /// 没有画面时中间显示的提示语。
    var placeholderText = "未选择图片" { didSet { needsDisplay = true } }

    /// 裁剪框左上角那行小字，例如 `480 × 480 → 800 × 800`。
    var captionText: String? { didSet { needsDisplay = true } }

    /// 导出进度，0 表示不画进度条。
    var progress: Double = 0 { didSet { needsDisplay = true } }

    /// 裁剪框被挪动或换图后回调，页面用它刷新尺寸提示。
    var onCropChange: (() -> Void)?

    private(set) var source: SourceImage?
    private var displayImage: NSImage?
    private(set) var cropBox = CropBox(origin: .zero, side: 0)

    private enum Drag {
        /// 记录按下点相对裁剪框左上角的偏移（图像坐标），拖动时按该偏移跟随。
        case move(offset: CGPoint)
        /// 按下那一刻的对角，整个拖动过程中保持不动。
        case resize(corner: CropCorner, anchor: CGPoint)
    }

    private var drag: Drag?

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    var currentCrop: IntegralCrop? {
        guard let source else { return nil }
        return cropBox.integralCrop(imageSize: source.pixelSize)
    }

    /// 换一张图：裁剪框重画成最大内切正方形。
    func show(_ source: SourceImage?) {
        self.source = source
        displayImage = Self.bitmap(of: source)
        cropBox = source.map { CropBox.inscribed(in: $0.pixelSize) } ?? CropBox(origin: .zero, side: 0)
        drag = nil
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
        onCropChange?()
    }

    /// 只换预览帧、保留用户摆好的裁剪框，给视频时间轴用。
    func updatePreview(_ source: SourceImage) {
        guard let current = self.source, current.pixelSize == source.pixelSize else {
            show(source)
            return
        }
        self.source = source
        displayImage = Self.bitmap(of: source)
        needsDisplay = true
    }

    private static func bitmap(of source: SourceImage?) -> NSImage? {
        source.map {
            NSImage(cgImage: $0.cgImage, size: NSSize(width: $0.pixelSize.width,
                                                      height: $0.pixelSize.height))
        }
    }

    // MARK: - 坐标换算

    private struct Geometry {
        let imageSize: CGSize
        let imageRect: CGRect
        let cropRect: CGRect
        let handles: [CropCorner: CGRect]
    }

    /// 图片等比缩放后落在视图里的矩形。
    private func fittedImageRect(for size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0, bounds.width > 1, bounds.height > 1 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: bounds.midX - drawn.width / 2, y: bounds.midY - drawn.height / 2,
                      width: drawn.width, height: drawn.height)
    }

    private func geometry() -> Geometry? {
        guard let source else { return nil }
        let imageSize = source.pixelSize
        let imageRect = fittedImageRect(for: imageSize)
        guard imageRect.width > 0 else { return nil }

        let scale = imageRect.width / imageSize.width
        let topLeft = CGPoint(x: imageRect.minX + cropBox.origin.x * scale,
                             y: imageRect.maxY - cropBox.origin.y * scale)
        let length = cropBox.side * scale
        let cropRect = CGRect(x: topLeft.x, y: topLeft.y - length, width: length, height: length)

        let handle = CropBox.handleSize
        let corners: [CropCorner: NSPoint] = [
            .topLeft: NSPoint(x: cropRect.minX, y: cropRect.maxY),
            .topRight: NSPoint(x: cropRect.maxX, y: cropRect.maxY),
            .bottomLeft: NSPoint(x: cropRect.minX, y: cropRect.minY),
            .bottomRight: NSPoint(x: cropRect.maxX, y: cropRect.minY),
        ]
        let handles = corners.mapValues {
            NSRect(x: $0.x - handle / 2, y: $0.y - handle / 2, width: handle, height: handle)
        }
        return Geometry(imageSize: imageSize, imageRect: imageRect, cropRect: cropRect, handles: handles)
    }

    /// 视图坐标 -> 图像坐标（原点在图片左上角）。
    private func imagePoint(from viewPoint: NSPoint, _ geometry: Geometry) -> CGPoint {
        let scale = geometry.imageRect.width / geometry.imageSize.width
        return CGPoint(x: (viewPoint.x - geometry.imageRect.minX) / scale,
                       y: (geometry.imageRect.maxY - viewPoint.y) / scale)
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        Self.background.setFill()
        bounds.fill()
        let frame = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                 xRadius: 10, yRadius: 10)
        frame.lineWidth = 1
        NSColor.separatorColor.setStroke()
        frame.stroke()

        guard let geometry = geometry(), let displayImage else {
            drawPlaceholder()
            drawProgressBar()
            return
        }

        NSGraphicsContext.current?.imageInterpolation = .high
        displayImage.draw(in: geometry.imageRect, from: .zero, operation: .sourceOver, fraction: 1)

        let crop = geometry.cropRect
        // 圆外压暗：整块裁剪区盖一层再挖掉内切圆，一眼能看出最终留下的是哪块。
        let overlay = NSBezierPath(rect: crop)
        overlay.appendOval(in: crop)
        overlay.windingRule = .evenOdd
        Self.scrim.setFill()
        overlay.fill()

        let square = NSBezierPath(rect: crop)
        square.lineWidth = Self.lineWidth
        Self.squareColor.setStroke()
        square.stroke()

        let circle = NSBezierPath(ovalIn: crop)
        circle.lineWidth = Self.lineWidth
        Self.circleColor.setStroke()
        circle.stroke()

        let handles = NSBezierPath()
        for rect in geometry.handles.values {
            handles.appendRoundedRect(rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
        }
        handles.lineWidth = Self.handleLineWidth
        Self.handleFill.setFill()
        handles.fill()
        Self.handleStroke.setStroke()
        handles.stroke()

        drawCaption(over: crop)
        drawProgressBar()
    }

    private func drawPlaceholder() {
        let text = placeholderText
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes)
    }

    /// 裁剪框左上角的尺寸说明，贴在框内侧，留出角上手柄的位置。
    private func drawCaption(over crop: CGRect) {
        guard let text = captionText, !text.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let chip = NSRect(x: crop.minX + 12,
                          y: crop.maxY - 12 - size.height - 6,
                          width: size.width + 14,
                          height: size.height + 6)
        NSColor(white: 0, alpha: 0.62).setFill()
        NSBezierPath(roundedRect: chip, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: NSPoint(x: chip.minX + 7, y: chip.minY + 3),
                                withAttributes: attributes)
    }

    /// 贴在画布顶边的一条细进度条，不额外占布局位置。
    private func drawProgressBar() {
        guard progress > 0 else { return }
        let track = NSRect(x: bounds.minX + 10, y: bounds.maxY - 16,
                           width: bounds.width - 20, height: 4)
        NSColor(white: 1, alpha: 0.3).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        let ratio = CGFloat(min(max(progress, 0), 1))
        let filled = NSRect(x: track.minX, y: track.minY,
                            width: max(4, track.width * ratio), height: track.height)
        Self.accent.setFill()
        NSBezierPath(roundedRect: filled, xRadius: 2, yRadius: 2).fill()
    }

    // MARK: - 交互

    override func mouseDown(with event: NSEvent) {
        guard let geometry = geometry() else { return }
        let point = convert(event.locationInWindow, from: nil)

        if let corner = corner(containing: point, in: geometry) {
            drag = .resize(corner: corner, anchor: cropBox.anchor(for: corner))
            Cursors.forCorner(corner).push()
            return
        }
        if geometry.cropRect.contains(point) {
            let imagePoint = imagePoint(from: point, geometry)
            drag = .move(offset: CGPoint(x: imagePoint.x - cropBox.origin.x,
                                        y: imagePoint.y - cropBox.origin.y))
            Cursors.move.push()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let source, let geometry = geometry(), let drag else { return }
        let imagePoint = self.imagePoint(from: convert(event.locationInWindow, from: nil), geometry)

        switch drag {
        case .move(let offset):
            cropBox = cropBox.moved(
                to: CGPoint(x: imagePoint.x - offset.x, y: imagePoint.y - offset.y),
                within: source.pixelSize)
        case .resize(let corner, let anchor):
            if let resized = CropBox.square(anchor: anchor, corner: corner, mouse: imagePoint,
                                            imageSize: source.pixelSize) {
                cropBox = resized
            }
        }

        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        onCropChange?()
    }

    override func mouseUp(with event: NSEvent) {
        guard drag != nil else { return }
        drag = nil
        NSCursor.pop()
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let geometry = geometry() else { return }
        // 后加入的光标矩形优先，所以手柄要盖在整体移动区之上。
        addCursorRect(geometry.cropRect, cursor: Cursors.move)
        for (corner, rect) in geometry.handles {
            addCursorRect(rect, cursor: Cursors.forCorner(corner))
        }
    }

    private func corner(containing point: NSPoint, in geometry: Geometry) -> CropCorner? {
        for corner in CropCorner.allCases where geometry.handles[corner]?.contains(point) == true {
            return corner
        }
        return nil
    }
}
