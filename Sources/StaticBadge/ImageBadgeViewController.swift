import AppKit
import StaticBadgeCore
import UniformTypeIdentifiers

/// 静态勋章页：选图片、摆裁剪框、设输出尺寸，然后导出。
final class ImageBadgeViewController: BadgePageViewController {
    private let canvas = CropCanvasView()
    private let pathLabel = FormLayout.pathLabel("还没有选择图片")
    private let output = OutputOptionsControl()
    private let sourceButton = FormLayout.button(title: "选择图片", symbol: "photo.on.rectangle",
                                                 action: #selector(chooseImage(_:)),
                                                 keyEquivalent: "o")

    private var imageURL: URL?

    override var canRun: Bool { canvas.source != nil }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 720))

        configureSaveDir(placeholder: "保存目录（默认与原图片相同）")
        configureRunButton(#selector(runExport(_:)))
        output.onChange = { [weak self] in self?.refreshSummaries() }
        canvas.onCropChange = { [weak self] in self?.refreshSummaries() }
        canvasView = canvas
        refreshSummaries()

        let grid = FormLayout.grid(rows: [
            ("源文件", FormLayout.row([sourceButton, pathLabel])),
            ("保存目录", FormLayout.row([saveDirButton, saveDirField])),
            ("输出尺寸", output),
            ("", FormLayout.row([statusLabel, FormLayout.spacer(), runButton])),
        ])

        let stage = FormLayout.panel(canvas)
        let rule = FormLayout.separator()

        for control in [grid, rule, stage] as [NSView] {
            control.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(control)
        }
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: FormLayout.margin),
            grid.leadingAnchor.constraint(equalTo: root.leadingAnchor,
                                          constant: FormLayout.margin),
            grid.trailingAnchor.constraint(equalTo: root.trailingAnchor,
                                           constant: -FormLayout.margin),

            rule.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 14),
            rule.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: grid.trailingAnchor),

            stage.topAnchor.constraint(equalTo: rule.bottomAnchor, constant: 12),
            stage.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: FormLayout.margin),
            stage.trailingAnchor.constraint(equalTo: root.trailingAnchor,
                                            constant: -FormLayout.margin),
            stage.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -FormLayout.margin),
            stage.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.canvasMinHeight),
        ])

        view = root
    }

    // MARK - 状态

    private func refreshSummaries() {
        guard let cropSide = canvas.currentCrop?.side else {
            canvas.captionText = nil
            statusLabel.stringValue = "选一张图片，绿色框可以拖动和缩放"
            return
        }
        let side = output.outputSide ?? cropSide
        canvas.captionText = cropSide == side
            ? "\(side) × \(side) 圆形"
            : "\(cropSide) × \(cropSide) → \(side) × \(side) 圆形"
        statusLabel.stringValue = output.limitsSize
            ? "输出 \(side) × \(side) 圆形 · \(output.limitSummary)"
            : "输出 \(side) × \(side) 圆形，圆外全透明"
    }

    private func setCurrent(image: SourceImage, url: URL) {
        imageURL = url
        canvas.show(image)
        pathLabel.stringValue = url.path
        pathLabel.toolTip = url.path
        saveDirField.stringValue = url.deletingLastPathComponent().path
        runButton.isEnabled = true
        refreshSummaries()
    }

    // MARK - 动作

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
            statusLabel.stringValue = "导出失败"
            UI.present(style: .critical, title: "错误",
                       message: (error as? BadgeError)?.errorDescription ?? "导出失败。")
            return
        }

        guard let target = write(data, to: directory,
                                 baseName: imageURL.deletingPathExtension().lastPathComponent)
        else { return }

        // 与 Qt 版一致：导出成功后把结果图载回画布，方便再裁一轮。
        load(url: target)
        statusLabel.stringValue = "已导出 \(UI.byteText(data.count)) · \(target.lastPathComponent)"
        UI.present(style: .informational, title: "完成",
                   message: "\(message)，文件 \(UI.byteText(data.count))：\n\(target.path)")
    }
}
