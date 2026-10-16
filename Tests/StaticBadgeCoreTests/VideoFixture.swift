import AVFoundation
import CoreGraphics
import CoreVideo
import XCTest
import StaticBadgeCore

/// 用 AVAssetWriter 现场生成一段测试视频。
///
/// 画面分成四个象限、各涂一种颜色，用来判断方向（上下、左右、旋转）有没有错；
/// 右下象限的蓝色分量逐帧递减，用来证明导出的是不同的帧而不是同一帧重复。
enum VideoFixture {
    static let size = 128
    /// 四个象限的中心点，都在裁剪框的内切圆之内。
    static let topLeft = (32, 32)
    static let topRight = (96, 32)
    static let bottomLeft = (32, 96)
    static let bottomRight = (96, 96)

    struct RGBA {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let offset = (y * width + x) * 4
            return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
        }
    }

    static func makeMovie(seconds: Double = 1, fps: Double = 30,
                          transform: CGAffineTransform = .identity) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StaticBadge-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.jpeg,
            AVVideoWidthKey: size,
            AVVideoHeightKey: size,
        ])
        input.transform = transform
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: size,
                kCVPixelBufferHeightKey as String: size,
            ])
        guard writer.canAdd(input) else {
            throw BadgeError.unreadVideo(reason: "测试写不出来：写不进这个容器")
        }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameCount = max(1, Int((seconds * fps).rounded()))
        for index in 0..<frameCount {
            let time = CMTime(value: CMTimeValue(index), timescale: Int32(fps))
            var waited = 0
            while !input.isReadyForMoreMediaData, waited < 2000 {
                usleep(5_000)
                waited += 1
            }
            XCTAssertTrue(adaptor.append(try pixelBuffer(frameIndex: index),
                                        withPresentationTime: time),
                          "第 \(index) 帧写入失败")
        }
        input.markAsFinished()
        writer.finishWriting {}
        var waited = 0
        while writer.status == .writing, waited < 6000 {
            usleep(5_000)
            waited += 1
        }
        guard writer.status == .completed else {
            throw writer.error ?? BadgeError.unreadVideo(reason: "生成测试视频失败")
        }
        return url
    }

    /// 把任意 CGImage 画成 RGBA 字节，首行对应画面顶行。
    static func rgba(_ image: CGImage) -> RGBA {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.flush()
        let pointer = context.data!.assumingMemoryBound(to: UInt8.self)
        return RGBA(width: image.width, height: image.height,
                    bytes: Array(UnsafeBufferPointer(start: pointer,
                                                     count: image.width * image.height * 4)))
    }

    private static func pixelBuffer(frameIndex: Int) throws -> CVPixelBuffer {
        var created: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, size, size,
                                        kCVPixelFormatType_32BGRA, nil, &created)
        guard status == kCVReturnSuccess, let buffer = created else {
            throw BadgeError.unreadVideo(reason: "无法创建像素缓冲")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw BadgeError.unreadVideo(reason: "无法锁定像素缓冲")
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pointer = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<size {
            for x in 0..<size {
                var color = quadrantColor(x: x, y: y)
                if x >= size / 2, y >= size / 2 {
                    color.2 = UInt8(255 - min(60, frameIndex * 6))
                }
                let offset = y * bytesPerRow + x * 4
                pointer[offset] = color.2
                pointer[offset + 1] = color.1
                pointer[offset + 2] = color.0
                pointer[offset + 3] = 255
            }
        }
        return buffer
    }

    private static func quadrantColor(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        switch (x < size / 2, y < size / 2) {
        case (true, false): return (30, 30, 235)     // 左下：蓝
        case (false, true): return (40, 205, 40)     // 右上：绿
        case (true, true): return (235, 30, 30)      // 左上：红
        case (false, false): return (240, 240, 255)  // 右下：接近白，蓝色分量逐帧变化
        }
    }
}
