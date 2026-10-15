import Foundation

/// 面向用户的错误，文案与 Qt 版弹窗保持一致。
public enum BadgeError: Error, Equatable, LocalizedError {
    case unreadImage(reason: String)
    case invalidCrop
    case contextUnavailable
    case encodingFailed
    case writeFailed(path: String)
    case webpDecodeFailed(status: Int)

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
        }
    }
}
