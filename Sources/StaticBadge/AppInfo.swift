import AppKit
import StaticBadgeCore

enum AppInfo {
    static let title = "勋章制作"

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    static var credits: NSAttributedString {
        let text = """
        正方形裁剪框 + 内切圆，一键导出圆形透明背景的 WebP；
        视频可以裁成循环播放的动态勋章。

        Swift / AppKit 重写版本，WebP 编码由内嵌 libwebp \(WebP.libraryVersion) 完成。
        """
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }
}
