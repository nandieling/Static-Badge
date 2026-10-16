import AppKit
import StaticBadgeCore
import UniformTypeIdentifiers

/// 动态勋章页：从视频里选一个正方形区域，导出圆外透明的动态 WebP。
///
/// 预览走 `AVAssetImageGenerator`（拖动时间轴时按需精确取帧），
/// 导出走 `AnimatedBadgeExporter` 顺序解码，两条路共用同一个裁剪框。
final class VideoBadgeViewController: BadgePageViewController {
    private let canvas = CropCanvasView()
    private let pathLabel = NSTextField(labelWithString: "未选择视频")
    private let sourceButton = NSButton()
    private let saveDirButton = NSButton()
    private let fpsPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let startField = NSTextField()
    private let durationField = NSTextField()
    private let optionsLabel = NSTextField(labelWithString: "未选择视频")
    private let output = OutputOptionsControl()
    private let slider = NSSlider()
    private let timeLabel = NSTextField(labelWithString: "00:00.00 / 00:00.00")
    private let progress = NSProgressIndicator()

    private let frameRates: [Double] = [60, 30, 24, 15]
    private let defaultFrameRate: Double = 30
    /// 超过这个帧数先跟用户确认一声，免得等半天才发现选错了参数。
    private let frameCountWarning = 400

    private var source: VideoBadgeSource?
    private var previewTime: TimeInterval = 0
    private var exporting = false
    private var lastReportedProgress = 0.0

    private let previewQueue = DispatchQueue(label: "勋章制作.视频预览", qos: .userInitiated)
    private let exportQueue = DispatchQueue(label: "勋章制作.动图导出", qos: .userInitiated)
    /// 拖动时间轴时只关心最后一次请求。
    private let requestedTime = Box<TimeInterval?>(nil)
    private let cancelled = Box<Bool>(false)

    override var canRun: Bool {
        exporting || source != nil
    }

    // MARK: - 布局

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 760))

        sourceButton.title = "选择视频"
        sourceButton.bezelStyle = .rounded
        sourceButton.target = self
        sourceButton.action = #selector(chooseVideo(_:))
        sourceButton.keyEquivalent = "e"
        sourceButton.keyEquivalentModifierMask = .command

        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.isSelectable = true
        pathLabel.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        pathLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        pathLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        saveDirButton.title = "保存目录"
        saveDirButton.bezelStyle = .rounded
        saveDirButton.target = self
        saveDirButton.action = #selector(chooseSaveDir(_:))
        configureSaveDirField(placeholder: "保存目录（默认与原视频相同）")
        configureRunButton(#selector(runExport(_:)))

        for rate in frameRates {
            fpsPopup.addItem(withTitle: "\(Int(rate)) 帧/秒")
            fpsPopup.lastItem?.tag = Int(rate)
        }
        fpsPopup.selectItem(withTag: Int(defaultFrameRate))
        fpsPopup.target = self
        fpsPopup.action = #selector(optionsChanged(_:))

        for field in [startField, durationField] {
            field.usesSingleLineMode = true
            field.alignment = .right
            field.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
            field.target = self
            field.action = #selector(optionsChanged(_:))
        }
        startField.placeholderString = "起始(秒)"
        durationField.placeholderString = "时长(秒)"

        optionsLabel.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        optionsLabel.textColor = .secondaryLabelColor
        optionsLabel.lineBreakMode = .byTruncatingTail
        optionsLabel.setContentHuggingPriority(.init(1), for: .horizontal)

        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = 0
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(scrubbed(_:))
        slider.isEnabled = false

        timeLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small),
                                                   weight: .regular)
        timeLabel.alignment = .right
        timeLabel.setContentHuggingPriority(.init(1000), for: .horizontal)

        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 100
        progress.doubleValue = 0
        progress.controlSize = .small
        progress.isHidden = true

        canvas.placeholderText = "未选择视频"
        output.onChange = { [weak self] in self?.refreshOptionsLabel() }

        let topRow = NSStackView(views: [sourceButton, pathLabel])
        topRow.orientation = .horizontal
        topRow.spacing = 8

        let saveRow = NSStackView(views: [saveDirButton, saveDirField])
        saveRow.orientation = .horizontal
        saveRow.spacing = 8

        let optionsRow = NSStackView(views: [fpsPopup, startField, durationField])
        optionsRow.orientation = .horizontal
        optionsRow.spacing = 8

        let outputRow = NSStackView(views: [output, optionsLabel])
        outputRow.orientation = .horizontal
        outputRow.spacing = 8

        let timelineRow = NSStackView(views: [slider, timeLabel])
        timelineRow.orientation = .horizontal
        timelineRow.spacing = 8

        for control in [topRow, saveRow, optionsRow, outputRow, runButton, canvas,
                        timelineRow, progress] as [NSView] {
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

            optionsRow.topAnchor.constraint(equalTo: saveRow.bottomAnchor, constant: 8),
            optionsRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            optionsRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            startField.widthAnchor.constraint(equalToConstant: 72),
            durationField.widthAnchor.constraint(equalToConstant: 72),

            outputRow.topAnchor.constraint(equalTo: optionsRow.bottomAnchor, constant: 8),
            outputRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            outputRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),

            runButton.topAnchor.constraint(equalTo: outputRow.bottomAnchor, constant: 8),
            runButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            runButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),

            canvas.topAnchor.constraint(equalTo: runButton.bottomAnchor, constant: 12),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),

            timelineRow.topAnchor.constraint(equalTo: canvas.bottomAnchor, constant: 8),
            timelineRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            timelineRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),

            progress.topAnchor.constraint(equalTo: timelineRow.bottomAnchor, constant: 6),
            progress.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            progress.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            progress.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),

            canvas.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.canvasMinHeight),
        ])

        view = root
        enableIdleControls()
    }

    // MARK: - 状态

    private var selectedFrameRate: Double {
        Double(fpsPopup.selectedItem?.tag ?? Int(defaultFrameRate))
    }

    private func enableIdleControls() {
        let loaded = source != nil && !exporting
        for control in [sourceButton, saveDirButton, fpsPopup, startField, durationField, slider] as [NSControl] {
            control.isEnabled = source == nil ? (control === sourceButton) : loaded
        }
        output.setEnabled(loaded)
        runButton.isEnabled = source != nil
    }

    private func refreshTimeLabel() {
        guard let source else {
            timeLabel.stringValue = "00:00.00 / 00:00.00"
            return
        }
        timeLabel.stringValue = "\(UI.clock(previewTime, fractionDigits: 2)) / "
            + UI.clock(source.duration, fractionDigits: 2)
    }

    private func refreshOptionsLabel() {
        guard let source, let range = rangeOrDefault() else {
            optionsLabel.stringValue = "未选择视频"
            return
        }
        let frames = AnimatedBadgeExporter.estimatedFrameCount(duration: range.duration,
                                                              fps: selectedFrameRate)
        optionsLabel.stringValue = "导出约 \(frames) 帧 · \(output.sizeSummary) · \(output.limitSummary) "
            + "· 循环播放 · 整段 \(UI.clock(source.duration, fractionDigits: 1)) 秒"
    }

    /// 界面上填的区间；填得不合适时退回“整段”，真正校验在 `validatedRange()`。
    private func rangeOrDefault() -> (start: TimeInterval, duration: TimeInterval)? {
        guard let source else { return nil }
        let start = UI.parseSeconds(startField.stringValue) ?? 0
        let length = UI.parseSeconds(durationField.stringValue) ?? (source.duration - start)
        guard start < source.duration else { return nil }
        return (start, min(max(length, 0.05), source.duration - start))
    }

    private func validatedRange() -> (start: TimeInterval, duration: TimeInterval)? {
        guard let source else { return nil }
        if startField.stringValue.trimmedNilIfEmpty != nil, UI.parseSeconds(startField.stringValue) == nil {
            UI.present(style: .critical, title: "错误", message: "起始时间要填秒数，例如 1.5。")
            return nil
        }
        if durationField.stringValue.trimmedNilIfEmpty != nil,
           UI.parseSeconds(durationField.stringValue) == nil {
            UI.present(style: .critical, title: "错误", message: "时长要填大于 0 的秒数，留空表示整段。")
            return nil
        }
        let start = UI.parseSeconds(startField.stringValue) ?? 0
        guard start < source.duration else {
            UI.present(style: .critical, title: "错误",
                       message: String(format: "起始时间超过了视频长度（%.1f 秒）。", source.duration))
            return nil
        }
        let remaining = source.duration - start
        let length = min(UI.parseSeconds(durationField.stringValue) ?? remaining, remaining)
        guard length > 0 else {
            UI.present(style: .critical, title: "错误", message: "要导出的时间段是空的。")
            return nil
        }
        return (start, length)
    }

    // MARK: - 动作

    @objc func chooseVideo(_ sender: Any?) {
        guard !exporting else { return }
        let panel = NSOpenPanel()
        panel.title = "选择视频"
        panel.prompt = "打开"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        if let directory = saveDirField.stringValue.trimmedNilIfEmpty {
            panel.directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url: url)
    }

    /// 供“用本应用打开视频”等入口复用。
    override func load(url: URL) {
        do {
            let loaded = try VideoBadgeSource(url: url)
            source = loaded
            previewTime = 0
            requestedTime.set(0)
            canvas.show(SourceImage(cgImage: loaded.firstFrame))
            pathLabel.stringValue = url.path
            pathLabel.toolTip = url.path
            saveDirField.stringValue = url.deletingLastPathComponent().path
            slider.minValue = 0
            slider.maxValue = max(loaded.duration, 0.001)
            slider.doubleValue = 0
            enableIdleControls()
            refreshTimeLabel()
            refreshOptionsLabel()
        } catch {
            UI.present(style: .critical, title: "错误",
                       message: (error as? BadgeError)?.errorDescription
                           ?? error.localizedDescription)
        }
    }

    @objc private func optionsChanged(_ sender: Any?) {
        refreshOptionsLabel()
    }

    @objc private func scrubbed(_ sender: Any?) {
        guard let source else { return }
        previewTime = source.clamped(slider.doubleValue)
        refreshTimeLabel()
        refreshOptionsLabel()
        guard !exporting else { return }
        requestPreview(at: previewTime)
    }

    /// 取帧放到后台，并且只画最后一次请求对应的那一帧。
    private func requestPreview(at seconds: TimeInterval) {
        requestedTime.set(seconds)
        previewQueue.async { [weak self] in
            guard let self, let source = self.source else { return }
            guard self.requestedTime.get() == seconds else { return }
            guard let image = try? source.previewImage(at: seconds) else { return }
            DispatchQueue.main.async {
                guard self.requestedTime.get() == seconds else { return }
                self.canvas.updatePreview(image)
            }
        }
    }

    override func runExport(_ sender: Any?) {
        if exporting {
            cancelled.set(true)
            runButton.isEnabled = false
            runButton.title = "正在取消…"
            return
        }
        guard source != nil else {
            UI.present(style: .warning, title: "提示", message: "请先选择视频。")
            return
        }
        guard let source, let crop = canvas.currentCrop else {
            UI.present(style: .warning, title: "提示", message: "请先选择视频。")
            return
        }
        guard let range = validatedRange() else { return }
        guard let directory = resolveSaveDirectory(fallback: source.url.deletingLastPathComponent())
        else { return }
        guard let outputOptions = output.read() else { return }

        let options = AnimatedExportOptions(fps: selectedFrameRate, quality: 90, loopCount: 0,
                                            outputSide: outputOptions.outputSide,
                                            maxBytes: outputOptions.maxBytes)
        let estimated = AnimatedBadgeExporter.estimatedFrameCount(duration: range.duration,
                                                                  fps: options.fps)
        if estimated > frameCountWarning,
           !UI.confirm(title: "帧数有点多",
                       message: "这次会导出约 \(estimated) 帧，可能慢一些、文件也更大。\n"
                           + "想更快可以调低帧率，或者填一个短一点的时长。") {
            return
        }

        let baseName = source.url.deletingPathExtension().lastPathComponent
        beginExport()
        exportQueue.async { [weak self] in
            let outcome: Result<AnimatedBadgeExporter.Result, Error>
            do {
                outcome = .success(try AnimatedBadgeExporter.webPData(
                    source: source, crop: crop, start: range.start, duration: range.duration,
                    options: options,
                    progress: { ratio in self?.reportProgress(ratio) },
                    isCancelled: { self?.cancelled.get() ?? true }))
            } catch {
                outcome = .failure(error)
            }
            DispatchQueue.main.async {
                self?.finishExport(outcome, directory: directory, baseName: baseName)
            }
        }
    }

    private func reportProgress(_ ratio: Double) {
        guard ratio >= 1 || ratio - lastReportedProgress >= 0.02 else { return }
        lastReportedProgress = ratio
        DispatchQueue.main.async {
            self.progress.doubleValue = ratio * 100
        }
    }

    private func beginExport() {
        exporting = true
        cancelled.set(false)
        lastReportedProgress = 0
        for control in [sourceButton, saveDirButton, fpsPopup, startField, durationField, slider] as [NSControl] {
            control.isEnabled = false
        }
        output.setEnabled(false)
        progress.isHidden = false
        progress.doubleValue = 0
        runButton.title = "取消"
        runButton.isEnabled = true
    }

    private func endExport() {
        exporting = false
        progress.isHidden = true
        runButton.title = "运行"
        enableIdleControls()
    }

    private func finishExport(_ outcome: Result<AnimatedBadgeExporter.Result, Error>,
                              directory: URL, baseName: String) {
        endExport()
        switch outcome {
        case .success(let result):
            guard let target = write(result.data, to: directory, baseName: baseName) else { return }
            UI.present(style: .informational, title: "完成",
                       message: "已生成 \(result.frameCount) 帧、\(result.side) × \(result.side) 的"
                           + "动态勋章（无限循环）：\n\(target.path)\n"
                           + "文件 \(UI.byteText(result.data.count)) · 画质 \(result.quality)"
                           + (result.attempts > 1 ? " · 试了 \(result.attempts) 次" : ""))
        case .failure(BadgeError.cancelled):
            optionsLabel.stringValue = "已取消导出。"
        case .failure(let error):
            UI.present(style: .critical, title: "错误",
                       message: (error as? BadgeError)?.errorDescription
                           ?? error.localizedDescription)
        }
    }
}
