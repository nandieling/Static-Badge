import AppKit
import StaticBadgeCore
import UniformTypeIdentifiers

/// 静态勋章页：添加图片、选保存目录、运行导出，下面是画布。
final class ImageBadgeViewController: BadgePageViewController {
    private let canvas = CropCanvasView()
    private let pathLabel = NSTextField(labelWithString: "未选择图片")
    private let output = OutputOptionsControl()

    private var imageURL: URL?

    override var canRun: Bool { canvas.source != nil }

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
        configureSaveDirField(placeholder: "保存目录（默认与原图片相同）")
        configureRunButton(#selector(runExport(_:)))

        let topRow = NSStackView(views: [loadButton, pathLabel])
        topRow.orientation = .horizontal
        topRow.spacing = 8

        let saveRow = NSStackView(views: [saveDirButton, saveDirField])
        saveRow.orientation = .horizontal
        saveRow.spacing = 8

        for control in [topRow, saveRow, output, runButton, canvas] as [NSView] {
            control.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(control)
        }

        NSLayoutConstraint.activate([
            topRow.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            topRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            topRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),

            saveRow.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 8),
            saveRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            saveRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),

            output.topAnchor.constraint(equalTo: saveRow.bottomAnchor, constant: 8),
            output.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            output.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),

            runButton.topAnchor.constraint(equalTo: output.bottomAnchor, constant: 8),
            runButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            runButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),

            canvas.topAnchor.constraint(equalTo: runButton.bottomAnchor, constant: 12),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            canvas.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.canvasMinHeight),
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
        if let directory = saveDirField.stringValue.trimmedNilIfEmpty {
            panel.directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url: url)
    }

    /// 供“用本应用打开图片”等入口复用。
    override func load(url: URL) {
        do {
            setCurrent(image: try ImageLoader.load(from: url), url: url)
        } catch {
            UI.present(style: .critical, title: "错误",
                       message: (error as? BadgeError)?.errorDescription
                           ?? error.localizedDescription)
        }
    }

    override func runExport(_ sender: Any?) {
        guard let image = canvas.source, let crop = canvas.currentCrop, let imageURL else {
            UI.present(style: .warning, title: "提示", message: "请先添加图片。")
            return
        }
        guard let outputOptions = output.read() else { return }
        guard let directory = resolveSaveDirectory(fallback: imageURL.deletingLastPathComponent())
        else { return }

        let side = outputOptions.outputSide ?? crop.side
        var message = "已生成并显示（\(side) × \(side)）"
        if let maxBytes = outputOptions.maxBytes {
            message += "，压进 \(UI.byteText(maxBytes)) 以内"
        }

        let data: Data
        do {
            data = try CircularBadgeExporter.webPData(
                from: image, crop: crop,
                options: ExportOptions(outputSide: outputOptions.outputSide,
                                       maxBytes: outputOptions.maxBytes))
        } catch {
            UI.present(style: .critical, title: "错误",
                       message: (error as? BadgeError)?.errorDescription ?? "导出失败。")
            return
        }

        guard let target = write(data, to: directory,
                                 baseName: imageURL.deletingPathExtension().lastPathComponent)
        else { return }

        // 与 Qt 版一致：导出成功后把结果图载回画布，方便再裁一轮。
        load(url: target)
        UI.present(style: .informational, title: "完成",
                   message: "\(message)，文件 \(UI.byteText(data.count))：\n\(target.path)")
    }
}
