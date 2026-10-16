import AppKit
import StaticBadgeCore

/// 页面要对容器暴露的能力。
@objc protocol BadgePage: AnyObject {
    /// 当前状态下能不能点“运行”。
    var canRun: Bool { get }
    func runExport(_ sender: Any?)
    func load(url: URL)
}

/// 静态/动态两个页面共用的部分：导出路径、运行按钮、弹窗、导出落盘。
class BadgePageViewController: NSViewController, BadgePage {
    /// 导出文件的完整路径，可以直接改。
    let savePathField = NSTextField()
    let saveDirButton = NSButton(title: "选择…", target: nil, action: nil)
    let runButton = NSButton()
    /// 运行按钮右边那句灰字，用来说当前设置和导出结果。
    let statusLabel = NSTextField(labelWithString: "")

    var canRun: Bool { false }

    /// 页面里的取景区。窗口开局把焦点给它：它能接焦点，又不会画出焦点框。
    weak var canvasView: NSView?

    /// 载入源文件时建议的导出文件名（不含后缀），留空路径框时回落到它。
    private(set) var suggestedBaseName: String?

    func runExport(_ sender: Any?) {}

    func load(url: URL) {}

    // MARK - 公共控件

    func configureSavePath(placeholder: String) {
        savePathField.placeholderString = placeholder
        savePathField.usesSingleLineMode = true
        savePathField.cell?.wraps = false
        savePathField.cell?.isScrollable = true
        savePathField.lineBreakMode = .byTruncatingMiddle
        savePathField.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        savePathField.setContentHuggingPriority(.init(1), for: .horizontal)
        savePathField.setContentCompressionResistancePriority(.init(40), for: .horizontal)

        saveDirButton.bezelStyle = .rounded
        saveDirButton.target = self
        saveDirButton.action = #selector(chooseSaveDir(_:))
        if let image = NSImage(systemSymbolName: "folder", accessibilityDescription: "选择保存位置") {
            saveDirButton.image = image
        }
    }

    /// 路径框只占行宽的一半，别把整行撑满。
    func constrainSavePath(widthOf container: NSView) {
        savePathField.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.5)
            .isActive = true
    }

    /// 运行按钮是窗口的默认按钮（回车即导出），⌘R 走菜单。
    func configureRunButton(_ action: Selector) {
        runButton.title = "运行"
        runButton.bezelStyle = .rounded
        runButton.controlSize = .large
        runButton.target = self
        runButton.action = action
        runButton.keyEquivalent = "\r"
        runButton.isEnabled = false

        statusLabel.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.init(200), for: .horizontal)
    }

    // MARK - 导出路径

    /// 路径框里的内容转成 URL（支持 `~`）；空着返回 nil。
    private var typedURL: URL? {
        guard let text = savePathField.stringValue.trimmedNilIfEmpty else { return nil }
        return URL(fileURLWithPath: (text as NSString).expandingTildeInPath)
    }

    private func isDirectory(_ url: URL) -> Bool {
        var flag: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &flag) else { return false }
        return flag.boolValue
    }

    /// 路径框当前指向的目录：填目录取它本身，填文件取父目录；空着返回 nil。
    var saveDirectory: URL? {
        guard let url = typedURL else { return nil }
        return isDirectory(url) ? url : url.deletingLastPathComponent()
    }

    /// 路径框当前填的文件名（不含 `.webp`）；填的是目录时返回 nil。
    private var typedFileName: String? {
        guard let url = typedURL, !isDirectory(url) else { return nil }
        let last = url.lastPathComponent
        guard !last.isEmpty else { return nil }
        return url.pathExtension.lowercased() == "webp"
            ? url.deletingPathExtension().lastPathComponent : last
    }

    /// 载入源文件后填一个默认路径：同目录、同文件名、`.webp`。
    func suggestSavePath(for source: URL) {
        let baseName = source.deletingPathExtension().lastPathComponent
        suggestedBaseName = baseName
        setSavePath(directory: source.deletingLastPathComponent(), fileName: baseName)
    }

    private func setSavePath(directory: URL, fileName: String) {
        let url = directory.appendingPathComponent(fileName).appendingPathExtension("webp")
        savePathField.stringValue = url.path
        savePathField.toolTip = url.path
    }

    @objc func chooseSaveDir(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "选择保存位置"
        panel.prompt = "选择"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        if let directory = saveDirectory, isDirectory(directory) {
            panel.directoryURL = directory
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // 换目录时保留当前文件名，没有就退回源文件名。
        setSavePath(directory: url, fileName: typedFileName ?? suggestedBaseName ?? "badge")
    }

    /// 校验路径框并给出真正要写的地址：补 `.webp`、补默认文件名、重名自动加序号。
    func resolveOutputURL(fallbackSource: URL) -> URL? {
        var directory = fallbackSource.deletingLastPathComponent()
        var fileName = fallbackSource.deletingPathExtension().lastPathComponent
        if let typed = typedURL {
            if isDirectory(typed) {
                directory = typed
            } else {
                directory = typed.deletingLastPathComponent()
                fileName = typedFileName ?? fileName
            }
        }
        guard ensureDirectory(directory) else { return nil }
        return CircularBadgeExporter.uniqueFileURL(in: directory, baseName: fileName)
    }

    /// 目录不存在就顺手建出来，建不了才报错。
    private func ensureDirectory(_ url: URL) -> Bool {
        if isDirectory(url) { return true }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            UI.present(style: .critical, title: "错误",
                       message: "保存位置不存在，而且没能创建：\(url.path)")
            return false
        }
    }

    /// 写下去，并把路径框回填成真正落盘的位置。
    func write(_ data: Data, to target: URL) -> URL? {
        do {
            try data.write(to: target, options: .atomic)
        } catch {
            UI.present(style: .critical, title: "错误",
                       message: BadgeError.writeFailed(path: target.path).errorDescription
                           ?? "写入失败。")
            return nil
        }
        savePathField.stringValue = target.path
        savePathField.toolTip = target.path
        return target
    }

    /// 拖窗口时别让裁剪框跟着乱跑：两个页面都用这条约束。
    static let canvasMinHeight: CGFloat = 240
}
