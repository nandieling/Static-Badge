import Foundation

/// 面向用户的错误，文案与 Qt 版弹窗保持一致。
public enum BadgeError: Error, Equatable, LocalizedError {
    case unreadImage(reason: String)
    case invalidCrop
    case contextUnavailable
    case encodingFailed
    case writeFailed(path: String)
    case webpDecodeFailed(status: Int)
    case unreadVideo(reason: String)
    case videoHasNoVideoTrack
    case videoRangeEmpty
    case animationFailed(reason: String)
    case cancelled
    case invalidOutputSize
    case sizeLimitExceeded(limit: Int, bestSize: Int)

    public var errorDescription: String? {
        switch self {
        case .unreadImage(let reason):
            return "无法读取图片：\(reason)"
        case .invalidCrop:
            return "裁剪区域无效。"
        case .contextUnavailable:
            return "无法创建导出画布。"
        case .encodingFailed:
            return "导出失败。"
        case .writeFailed(let path):
            return "写入失败：\(path)"
        case .webpDecodeFailed(let status):
            return "WebP 解码失败（状态码 \(status)）。"
        case .unreadVideo(let reason):
            return "无法读取视频：\(reason)"
        case .videoHasNoVideoTrack:
            return "这个视频里没有可用的画面轨道。"
        case .videoRangeEmpty:
            return "要导出的时间段是空的。"
        case .animationFailed(let reason):
            return "动态导出失败：\(reason)"
        case .cancelled:
            return "已取消导出。"
        case .invalidOutputSize:
            return "输出尺寸无效。"
        case .sizeLimitExceeded(let limit, let bestSize):
            return "即使压到最低画质仍有 \(byteText(bestSize))，超过 \(byteText(limit)) 的上限。"
                + "换成更小的输出尺寸、更低的帧率或更短的时长再试。"
        }
    }
}

private func byteText(_ count: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
}
