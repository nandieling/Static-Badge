import CoreGraphics
import Foundation

/// 导出画布：正方形、预乘 BGRA、sRGB，并负责把内切圆以外的区域挖空。
///
/// 静态图片和动图的每一帧都走同一套绘制，两种勋章的圆边、抗锯齿表现完全一致。
/// 画布边长可以和裁剪边长不同：先按裁剪框坐标画，再由 CTM 整体缩放到画布大小。
enum BadgeCanvas {
    static func makeContext(side: Int) -> CGContext? {
        guard side >= 1,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: side, height: side,
                         bitsPerComponent: 8, bytesPerRow: side * 4,
                         space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                           | CGBitmapInfo.byteOrder32Little.rawValue)
    }

    /// 导出边长：没指定就跟着裁剪框走（原始分辨率）。
    static func outputSide(for crop: IntegralCrop, requested: Int?) throws -> Int {
        guard crop.side >= 1 else { throw BadgeError.invalidCrop }
        guard let requested else { return crop.side }
        guard requested >= 1 else { throw BadgeError.invalidOutputSize }
        return requested
    }

    /// 把 `crop` 区域画满画布，并把内切圆以外置为全透明。调用方负责 `flush()`。
    ///
    /// 缩放比例取自画布与裁剪框的边长差，所以调用方只要把画布建成目标尺寸即可。
    static func draw(_ image: CGImage, crop: IntegralCrop, in context: CGContext) throws {
        guard crop.side >= 1, crop.x >= 0, crop.y >= 0,
              crop.x + crop.side <= image.width,
              crop.y + crop.side <= image.height else {
            throw BadgeError.invalidCrop
        }

        let canvas = CGRect(x: 0, y: 0, width: crop.side, height: crop.side)
        context.clear(canvasRect(in: context))
        context.interpolationQuality = .none
        guard let cropped = image.cropping(to: crop.rect) else {
            throw BadgeError.invalidCrop
        }
        // CGBitmapContext 的缓冲首行对应画面顶行，与 libwebp 的行序一致，无需翻转。
        context.saveGState()
        applyScale(scale(of: context, crop: crop), in: context)
        context.draw(cropped, in: canvas)
        context.restoreGState()
        applyCircleMask(in: context)
    }

    /// 画布自身的像素矩形，挖圆和清屏都以它为准。
    private static func canvasRect(in context: CGContext) -> CGRect {
        CGRect(x: 0, y: 0, width: context.width, height: context.height)
    }

    /// 画布对裁剪框的放大倍数；等于 1 时保持像素不动，避免白白重采样。
    private static func scale(of context: CGContext, crop: IntegralCrop) -> CGFloat {
        CGFloat(context.width) / CGFloat(crop.side)
    }

    private static func applyScale(_ scale: CGFloat, in context: CGContext) {
        guard scale != 1 else { return }
        context.scaleBy(x: scale, y: scale)
        // 缩放意味着要重采样，这里交给 Core Graphics 挑质量最好的滤波器。
        context.interpolationQuality = .high
    }

    /// 视频帧专用：先按 preferredTransform 摆正，再按 `crop` 裁进画布并挖圆。
    ///
    /// AVFoundation 对 `preferredTransform` 的解释是“媒体像素空间（左上原点）”里的
    /// 变换：直接把画面乘上它就是摆正后的样子。而 Core Graphics 的绘制空间 y 轴朝上，
    /// 所以进变换之前、出变换之后各翻一次 y，方向才不会反过来。
    static func drawVideoFrame(_ image: CGImage, transform: CGAffineTransform,
                               naturalSize: CGSize, crop: IntegralCrop,
                               in context: CGContext) throws {
        let orientedBounds = CGRect(origin: .zero, size: naturalSize).applying(transform)
        guard crop.side >= 1, crop.x >= 0, crop.y >= 0,
              crop.x + crop.side <= Int(orientedBounds.width.rounded()),
              crop.y + crop.side <= Int(orientedBounds.height.rounded()) else {
            throw BadgeError.invalidCrop
        }

        let canvas = CGRect(x: 0, y: 0, width: crop.side, height: crop.side)
        context.clear(canvasRect(in: context))
        context.interpolationQuality = .none

        // 未加平移时，画面会落在 placed 这块区域里（内容正立，视觉左上角在 minX/maxY）。
        let placed = placementRect(naturalSize: naturalSize, transform: transform)
        let offsetX = -placed.minX - CGFloat(crop.x)
        let offsetY = CGFloat(crop.side) - placed.maxY + CGFloat(crop.y)

        // CGContext 的调用顺序与生效顺序相反：后写进去的矩阵先作用到点上。
        context.saveGState()
        applyScale(scale(of: context, crop: crop), in: context)
        context.translateBy(x: offsetX, y: offsetY)
        context.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0))
        context.concatenate(transform)
        context.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                             tx: 0, ty: naturalSize.height))
        context.draw(image, in: CGRect(origin: .zero, size: naturalSize))
        context.restoreGState()
        // 挖圆必须在画布自身坐标里做：上面那串缩放/平移/翻转只属于画面那一层，
        // 带着它们挖圆，裁剪框一有偏移，圆就跟着跑偏。
        applyCircleMask(in: context)
    }

    /// 算出“画进绘制空间后、未做裁剪平移前”画面所占的矩形。
    ///
    /// 这里手工串三个步骤，免得 CGAffineTransform 的组合顺序把人绕晕。
    private static func placementRect(naturalSize: CGSize,
                                      transform: CGAffineTransform) -> CGRect {
        let height = naturalSize.height
        func place(_ point: CGPoint) -> CGPoint {
            // 绘制空间 -> 媒体空间（左上原点）
            let media = CGPoint(x: point.x, y: height - point.y)
            // 媒体空间里按轨道信息摆正
            let oriented = media.applying(transform)
            // 翻回 y 轴朝上的绘制空间
            return CGPoint(x: oriented.x, y: -oriented.y)
        }
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: naturalSize.width, y: 0),
            CGPoint(x: 0, y: height),
            CGPoint(x: naturalSize.width, y: height),
        ].map(place)
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 挖掉内切圆以外的区域。Core Graphics 的 destinationIn 不会清除路径外的像素，
    /// 这里用奇偶填充的“整幅矩形减去内切圆”圆环配 destinationOut，
    /// 得到真正的半透明抗锯齿边缘。
    ///
    /// 调用时 CTM 必须回到画布坐标（即已经 `restoreGState()`），否则挖出来的
    /// 是个被平移过的位置，甚至是个椭圆。
    private static func applyCircleMask(in context: CGContext) {
        let canvas = canvasRect(in: context)
        context.setBlendMode(.destinationOut)
        context.setShouldAntialias(true)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        let ring = CGMutablePath()
        ring.addRect(canvas)
        ring.addEllipse(in: canvas)
        context.addPath(ring)
        context.fillPath(using: .evenOdd)
        context.setBlendMode(.normal)
    }
}
