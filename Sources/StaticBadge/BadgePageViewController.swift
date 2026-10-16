import AppKit
import StaticBadgeCore

/// 页面要对容器暴露的能力。
@objc protocol BadgePage: AnyObject {
    /// 当前状态下能不能点“运行”。
    var canRun: Bool { get }
    func runExport(_ sender: Any?)
    func load(url: URL)
}

/// 静态/动态两个页面共用的部分：保存目录、运行按钮、弹窗、导出落盘。
class BadgePageViewController: NSViewController, BadgePage {
    let saveDirField = NSTextField()
    let runButton = NSButton()

    var canRun: Bool { false }

    func runExport(_ sender: Any?) {}

    func load(url: URL) {}

    // MARK: - 公共控件

    func configureSaveDirField(placeholder: String) {
        saveDirField.placeholderString = placeholder
        saveDirField.usesSingleLineMode = true
        saveDirField.cell?.wraps = false
        saveDirField.cell?.isScrollable = true
        saveDirField.lineBreakMode = .byTruncatingMiddle
    }

    func configureRunButton(_ action: Selector) {
        runButton.title = "运行"
        runButton.bezelStyle = .rounded
        runButton.target = self
        runButton.action = action
        runButton.keyEquivalent = "r"
        runButton.keyEquivalentModifierMask = .command
        runButton.isEnabled = false
    }

    @objc func chooseSaveDir(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "选择保存目录"
        panel.prompt = "选择"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        if let directory = saveDirField.stringValue.trimmedNilIfEmpty,
           FileManager.default.fileExists(atPath: directory) {
            panel.directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveDirField.stringValue = url.path
    }

    /// 解析保存目录；为空时用 `fallback`，目录不存在会弹窗并返回 nil。
    func resolveSaveDirectory(fallback: URL?) -> URL? {
        let path = saveDirField.stringValue.trimmedNilIfEmpty ?? fallback?.path ?? ""
        guard !path.isEmpty else {
            UI.present(style: .critical, title: "错误", message: "还没有可保存的位置，请先选择文件。")
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            UI.present(style: .critical, title: "错误", message: "保存目录不存在，请重新选择。")
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// 按 Qt 版的命名规则找到不冲突的目标文件并写下去。
    func write(_ data: Data, to directory: URL, baseName: String) -> URL? {
        let target = CircularBadgeExporter.uniqueFileURL(in: directory, baseName: baseName)
        do {
            try data.write(to: target, options: .atomic)
            return target
        } catch {
            UI.present(style: .critical, title: "错误",
                       message: BadgeError.writeFailed(path: target.path).errorDescription
                           ?? "写入失败。")
            return nil
        }
    }

    /// 拖窗口时别让裁剪框跟着乱跑：两个页面都用这条约束。
    static let canvasMinHeight: CGFloat = 240
}
