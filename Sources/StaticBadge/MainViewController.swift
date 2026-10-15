import AppKit
import StaticBadgeCore
import UniformTypeIdentifiers

/// 主界面：添加图片、选保存目录、运行导出，下面是画布。
final class MainViewController: NSViewController, NSUserInterfaceValidations {
    private let canvas = CropCanvasView()
    private let pathLabel = NSTextField(labelWithString: "未选择图片")
    private let saveDirField = NSTextField()
    private let runButton = NSButton()

    private var imageURL: URL?

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))

        let loadButton = NSButton(title: "添加图片", target: self, action: #selector(chooseImage(_:)))
        loadButton.bezelStyle = .rounded
        loadButton.keyEquivalent = "o"
        loadButton.keyEquivalentModifierMask = .command

        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.isSelectable = true
        pathLabel.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        pathLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        pathLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        let saveDirButton = NSButton(title: "保存目录", target: self, action: #selector(chooseSaveDir(_:)))
        saveDirButton.bezelStyle = .rounded

        saveDirField.placeholderString = "保存目录（默认与原图片相同）"
        saveDirField.usesSingleLineMode = true
        saveDirField.cell?.wraps = false
        saveDirField.cell?.isScrollable = true
        saveDirField.lineBreakMode = .byTruncatingMiddle

        runButton.title = "运行"
        runButton.bezelStyle = .rounded
        runButton.target = self
        runButton.action = #selector(runExport(_:))
        runButton.keyEquivalent = "r"
        runButton.keyEquivalentModifierMask = .command
        runButton.isEnabled = false

        let topRow = NSStackView(views: [loadButton, pathLabel])
        topRow.orientation = .horizontal
        topRow.spacing = 8

        let saveRow = NSStackView(views: [saveDirButton, saveDirField])
        saveRow.orientation = .horizontal
        saveRow.spacing = 8

        for view in [topRow, saveRow, runButton, canvas] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }

        NSLayoutConstraint.activate([
            topRow.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            topRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            topRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),

            saveRow.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 8),
            saveRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            saveRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),

            runButton.topAnchor.constraint(equalTo: saveRow.bottomAnchor, constant: 8),
            runButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            runButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),

            canvas.topAnchor.constraint(equalTo: runButton.bottomAnchor, constant: 12),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            canvas.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
        ])

        view = root
    }

    // MARK: - 状态

    private func setCurrent(image: SourceImage, url: URL) {
        imageURL = url
        canvas.show(image)
        pathLabel.stringValue = url.path
        pathLabel.toolTip = url.path
        saveDirField.stringValue = url.deletingLastPathComponent().path
        runButton.isEnabled = true
    }

    // MARK: - 动作

    @objc func chooseImage(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "选择图片"
        panel.prompt = "打开"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        if let directory = saveDirField.stringValue.nilIfEmpty {
            panel.directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url: url)
    }

    /// 供“用本应用打开图片”等入口复用。
    func load(url: URL) {
        do {
            setCurrent(image: try ImageLoader.load(from: url), url: url)
        } catch {
            present(style: .critical, title: "错误",
                    message: (error as? BadgeError)?.errorDescription
                        ?? error.localizedDescription)
        }
    }

    @objc func chooseSaveDir(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "选择保存目录"
        panel.prompt = "选择"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        if let directory = saveDirField.stringValue.nilIfEmpty,
           FileManager.default.fileExists(atPath: directory) {
            panel.directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveDirField.stringValue = url.path
    }

    @objc func runExport(_ sender: Any?) {
        guard let image = canvas.source, let crop = canvas.currentCrop, let imageURL else {
            present(style: .warning, title: "提示", message: "请先添加图片。")
            return
        }

        let directory = saveDirField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? imageURL.deletingLastPathComponent().path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            present(style: .critical, title: "错误", message: "保存目录不存在，请重新选择。")
            return
        }

        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        let target = CircularBadgeExporter.uniqueFileURL(
            in: directoryURL, baseName: imageURL.deletingPathExtension().lastPathComponent)

        let data: Data
        do {
            data = try CircularBadgeExporter.webPData(from: image, crop: crop)
        } catch {
            present(style: .critical, title: "错误",
                    message: (error as? BadgeError)?.errorDescription ?? "导出失败。")
            return
        }

        do {
            try data.write(to: target, options: .atomic)
        } catch {
            present(style: .critical, title: "错误",
                    message: BadgeError.writeFailed(path: target.path).errorDescription ?? "写入失败。")
            return
        }

        // 与 Qt 版一致：导出成功后把结果图载回画布，方便再裁一轮。
        load(url: target)
        present(style: .informational, title: "完成", message: "已生成并显示：\n\(target.path)")
    }

    private func present(style: NSAlert.Style, title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: - 菜单项可用性

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(runExport(_:)) {
            return canvas.source != nil
        }
        return true
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
