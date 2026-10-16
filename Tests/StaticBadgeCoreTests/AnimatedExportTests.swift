import AVFoundation
import CoreGraphics
import XCTest
@testable import StaticBadgeCore

final class AnimatedExportTests: XCTestCase {
    private var movies: [URL] = []

    override func tearDown() {
        for url in movies {
            try? FileManager.default.removeItem(at: url)
        }
        movies.removeAll()
        super.tearDown()
    }

    // MARK: - 工具

    private func movie(seconds: Double = 1, transform: CGAffineTransform = .identity) throws -> URL {
        let url = try VideoFixture.makeMovie(seconds: seconds, transform: transform)
        movies.append(url)
        return url
    }

    private func export(_ url: URL, crop: IntegralCrop, start: TimeInterval = 0,
                        duration: TimeInterval = 1, fps: Double = 8,
                        progress: ((Double) -> Void)? = nil) throws -> WebPAnimation {
        try exportDetailed(url, crop: crop, start: start, duration: duration, fps: fps,
                           progress: progress).animation
    }

    private func exportDetailed(_ url: URL, crop: IntegralCrop, start: TimeInterval = 0,
                                duration: TimeInterval = 1, fps: Double = 8,
                                progress: ((Double) -> Void)? = nil) throws
        -> (animation: WebPAnimation, result: AnimatedBadgeExporter.Result) {
        let source = try VideoBadgeSource(url: url)
        let result = try AnimatedBadgeExporter.webPData(
            source: source, crop: crop, start: start, duration: duration,
            options: AnimatedExportOptions(fps: fps), progress: progress)
        XCTAssertGreaterThan(result.frameCount, 0)
        let animation = try WebP.decodeAnimation(result.data)
        // 内容完全相同的相邻帧会被编码器合并成一帧，所以解码帧数只会更少。
        XCTAssertLessThanOrEqual(animation.frameCount, result.frameCount)
        XCTAssertEqual(animation.frames.count, animation.frameCount)
        return (animation, result)
    }

    private func rgba(_ frame: WebPAnimation.Frame) -> VideoFixture.RGBA {
        VideoFixture.RGBA(width: frame.width, height: frame.height, bytes: [UInt8](frame.bytes))
    }

    /// 把像素归类成四种颜色之一，避开有损编码带来的数值抖动。
    private func label(_ pixel: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> String {
        let (r, g, b) = (Int(pixel.r), Int(pixel.g), Int(pixel.b))
        if r > g + 40, r > b + 40 { return "红" }
        if g > r + 40, g > b + 40 { return "绿" }
        if b > r + 40, b > g + 40 { return "蓝" }
        return "白"
    }

    private func labels(_ image: VideoFixture.RGBA) -> [String] {
        [VideoFixture.topLeft, VideoFixture.topRight, VideoFixture.bottomLeft,
         VideoFixture.bottomRight].map { label(image.pixel($0.0, $0.1)) }
    }

    // MARK: - 用例

    func test导出的动图无限循环且尺寸等于裁剪框() throws {
        let exported = try exportDetailed(try movie(), crop: IntegralCrop(x: 0, y: 0, side: 128))
        let animation = exported.animation
        XCTAssertEqual(animation.width, 128)
        XCTAssertEqual(animation.height, 128)
        XCTAssertEqual(animation.loopCount, 0, "动态勋章要无限循环播放")

        // 一秒内容、8 帧每秒，应该取到 8 帧上下。
        XCTAssertGreaterThanOrEqual(exported.result.frameCount, 6)
        XCTAssertLessThanOrEqual(exported.result.frameCount, 9)

        // libwebp 报的是每帧的显示结束时刻：时间戳单调递增、覆盖到接近结尾，
        // 帧时长都是 1/8 秒的整数倍（内容相同的相邻帧被合并的结果）。
        let stamps = animation.frames.map(\.timestamp)
        XCTAssertEqual(stamps.first ?? -1, 1.0 / 8.0, accuracy: 0.001)
        XCTAssertTrue(zip(stamps, stamps.dropFirst()).allSatisfy { $0 < $1 }, "\(stamps)")
        XCTAssertGreaterThan(stamps.last ?? 0, 1 - 1.0 / 8.0)
        for frame in animation.frames.dropLast() {
            XCTAssertEqual(frame.duration.remainder(dividingBy: 0.125), 0, accuracy: 0.002,
                           "帧时长 \(frame.duration) 不是 1/8 秒的整数倍")
        }
    }

    func test动图圆外透明圆内不透明() throws {
        let animation = try export(try movie(), crop: IntegralCrop(x: 0, y: 0, side: 128))
        let frame = rgba(animation.frames[0])
        for corner in [(0, 0), (127, 0), (0, 127), (127, 127)] {
            XCTAssertLessThanOrEqual(frame.pixel(corner.0, corner.1).a, 2,
                                    "角 \(corner) 应当透明")
        }
        XCTAssertGreaterThanOrEqual(frame.pixel(64, 64).a, 250, "圆心应当不透明")
    }

    func test导出方向与系统解码一致() throws {
        let url = try movie()
        let reference = VideoFixture.rgba(try VideoBadgeSource(url: url).firstFrame)
        // 先确认参照物本身没被画反：左上红、右上绿、左下蓝、右下接近白。
        XCTAssertEqual(labels(reference), ["红", "绿", "蓝", "白"])

        let animation = try export(url, crop: IntegralCrop(x: 0, y: 0, side: 128))
        XCTAssertEqual(labels(rgba(animation.frames[0])), labels(reference),
                       "导出结果的方向要和系统解码器一致")
    }

    func test带旋转信息的视频会被摆正() throws {
        let rotated = try movie(transform: CGAffineTransform(rotationAngle: .pi / 2))
        let reference = VideoFixture.rgba(try VideoBadgeSource(url: rotated).firstFrame)
        // 旋转后的参照画面必须和原方向不同，否则这个用例什么也没验证。
        XCTAssertNotEqual(labels(reference), ["红", "绿", "蓝", "白"],
                          "测试素材的旋转信息没有生效")

        let animation = try export(rotated, crop: IntegralCrop(x: 0, y: 0, side: 128))
        let badge = labels(rgba(animation.frames[0]))
        XCTAssertEqual(badge, labels(reference), "导出结果要跟着 preferredTransform 一起摆正")
    }

    func test只裁切指定区域() throws {
        let animation = try export(try movie(), crop: IntegralCrop(x: 0, y: 0, side: 64))
        XCTAssertEqual(animation.width, 64)
        let frame = rgba(animation.frames[0])
        // 左上四分之一整块是红色，圆内的点都应该判成红色。
        for point in [(32, 32), (24, 40), (40, 24)] {
            XCTAssertEqual(label(frame.pixel(point.0, point.1)), "红", "点 \(point) 不属于左上区域")
        }
    }

    func test导出的是逐帧变化的画面() throws {
        let animation = try export(try movie(), crop: IntegralCrop(x: 0, y: 0, side: 128))
        let first = rgba(animation.frames.first!)
        let last = rgba(animation.frames.last!)
        let delta = abs(Int(first.pixel(96, 96).b) - Int(last.pixel(96, 96).b))
        XCTAssertGreaterThanOrEqual(delta, 20, "首帧和末帧的蓝色分量应该随帧号变化（实测差值 \(delta)）")
    }

    func test进度回调单调走到一() throws {
        var marks: [Double] = []
        _ = try export(try movie(), crop: IntegralCrop(x: 0, y: 0, side: 64),
                       progress: { marks.append($0) })
        XCTAssertFalse(marks.isEmpty)
        XCTAssertEqual(marks.last ?? 0, 1, accuracy: 0.001)
        XCTAssertTrue(marks.sorted { $0 < $1 } == marks, "进度不能倒退：\(marks)")
    }

    func test取消导出会中断并报已取消() throws {
        let source = try VideoBadgeSource(url: try movie())
        var checked = 0
        XCTAssertThrowsError(try AnimatedBadgeExporter.webPData(
            source: source, crop: IntegralCrop(x: 0, y: 0, side: 128), start: 0, duration: 1,
            options: AnimatedExportOptions(fps: 8),
            isCancelled: {
                checked += 1
                return checked > 3
            })) { error in
            XCTAssertEqual(error as? BadgeError, .cancelled)
        }
        XCTAssertLessThan(checked, 8, "取消后不该把剩下的帧全读一遍")
    }

    func test裁剪框越界会报错() {
        let url = try! movie()
        let source = try! VideoBadgeSource(url: url)
        XCTAssertThrowsError(try AnimatedBadgeExporter.webPData(
            source: source, crop: IntegralCrop(x: 1, y: 0, side: 128), start: 0, duration: 1)) { error in
            XCTAssertEqual(error as? BadgeError, .invalidCrop)
        }
    }

    func test空时间范围会报错() {
        let url = try! movie()
        let source = try! VideoBadgeSource(url: url)
        let crop = IntegralCrop(x: 0, y: 0, side: 128)
        XCTAssertThrowsError(try AnimatedBadgeExporter.webPData(source: source, crop: crop,
                                                               start: 0, duration: 0)) { error in
            XCTAssertEqual(error as? BadgeError, .videoRangeEmpty)
        }
        XCTAssertThrowsError(try AnimatedBadgeExporter.webPData(source: source, crop: crop,
                                                               start: 30, duration: 5)) { error in
            XCTAssertEqual(error as? BadgeError, .videoRangeEmpty)
        }
    }

    func test估算帧数与实际取到的帧数接近() throws {
        let url = try movie()
        let source = try VideoBadgeSource(url: url)
        let estimated = AnimatedBadgeExporter.estimatedFrameCount(duration: source.duration, fps: 8)
        let result = try AnimatedBadgeExporter.webPData(source: source,
                                                      crop: IntegralCrop(x: 0, y: 0, side: 64),
                                                      start: 0, duration: source.duration,
                                                      options: AnimatedExportOptions(fps: 8))
        XCTAssertLessThanOrEqual(abs(estimated - result.frameCount), 1)
        XCTAssertEqual(result.duration, Double(result.frameCount) / 8, accuracy: 0.001)
    }
}
