import AppKit

/// 两页共用的输出选项：输出尺寸，加上可选的“文件不超过多大”。
final class OutputOptionsControl: NSStackView {
    private let sizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let limitCheck = NSButton(checkboxWithTitle: "限制大小", target: nil, action: nil)
    private let limitField = NSTextField()
    private let unitLabel = NSTextField(labelWithString: "MB")

    /// 下拉里可选的固定边长；“原始分辨率”用 tag 0 表示。
    private static let fixedSizes = [1080, 800, 600]

    /// 默认就把体积压在 5 MB 以内：绝大多数勋章远远用不完，又能挡住少数失控的大文件。
    private static let defaultMegabytes = "5"

    /// 选项变化时回调，用来刷新提示文字。
    var onChange: (() -> Void)?

    init() {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 8

        sizePopup.addItem(withTitle: "原始分辨率")
        sizePopup.lastItem?.tag = 0
        for side in Self.fixedSizes {
            sizePopup.addItem(withTitle: "\(side) × \(side)")
            sizePopup.lastItem?.tag = side
        }
        sizePopup.selectItem(withTag: 0)
        sizePopup.target = self
        sizePopup.action = #selector(changed(_:))

        limitCheck.target = self
        limitCheck.action = #selector(limitToggled(_:))
        limitCheck.state = .on

        limitField.placeholderString = "如 5"
        limitField.stringValue = Self.defaultMegabytes
        limitField.usesSingleLineMode = true
        limitField.alignment = .right
        limitField.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        limitField.target = self
        limitField.action = #selector(changed(_:))
        limitField.isEnabled = true

        unitLabel.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        unitLabel.textColor = .secondaryLabelColor

        for view in [sizePopup, limitCheck, limitField, unitLabel] as [NSView] {
            addArrangedSubview(view)
        }
        limitField.widthAnchor.constraint(equalToConstant: 56).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不用.storyboard") }

    // MARK - 读取

    /// 导出边长；nil 表示按裁剪框的原始分辨率。
    var outputSide: Int? {
        let tag = sizePopup.selectedItem?.tag ?? 0
        return tag > 0 ? tag : nil
    }

    var limitsSize: Bool { limitCheck.state == .on }

    /// 界面上的输出选项；体积上限填得不合法时弹窗并返回 nil。
    func read() -> (outputSide: Int?, maxBytes: Int?)? {
        guard limitsSize else { return (outputSide, nil) }
        guard let megabytes = UI.parseMegabytes(limitField.stringValue) else {
            UI.present(style: .critical, title: "错误",
                       message: "限制大小要填 MB 数，例如 5，或者 0.5。")
            return nil
        }
        let bytes = Int((megabytes * 1_048_576).rounded())
        guard bytes >= 1024 else {
            UI.present(style: .critical, title: "错误", message: "限制大小太小了，至少留 1 MB。")
            return nil
        }
        return (outputSide, bytes)
    }

    // MARK - 提示文字

    var sizeSummary: String {
        guard let side = outputSide else { return "原始分辨率" }
        return "\(side) × \(side)"
    }

    var limitSummary: String {
        guard limitsSize else { return "不限大小" }
        guard let megabytes = UI.parseMegabytes(limitField.stringValue) else { return "上限未填" }
        return "上限 \(UI.megabyteText(megabytes))"
    }

    /// 导出进行中要把选项锁住，但别把整行藏起来。
    func setEnabled(_ enabled: Bool) {
        sizePopup.isEnabled = enabled
        limitCheck.isEnabled = enabled
        limitField.isEnabled = enabled && limitCheck.state == .on
    }

    // MARK - 动作

    @objc private func changed(_ sender: Any?) {
        onChange?()
    }

    @objc private func limitToggled(_ sender: Any?) {
        limitField.isEnabled = limitCheck.state == .on
        onChange?()
    }
}
