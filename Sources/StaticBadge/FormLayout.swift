import AppKit

/// 界面共用的排版小工具：两列对齐的表单、统一风格按钮、路径文字等。
enum FormLayout {
    /// 页面四周留白与行距，两个页面共用同一套数值。
    static let margin: CGFloat = 16
    static let rowGap: CGFloat = 10

    /// 表单左列的说明文字（右对齐、次要色）。
    static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        return label
    }

    /// 行内的小注释。
    static func note(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        label.textColor = .tertiaryLabelColor
        return label
    }

    /// 横向控件组；第一个传 `.stretch` 的那个会被拉开。
    static func row(_ views: NSView...) -> NSStackView {
        row(views)
    }

    static func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    /// 会把剩余宽度全吃掉的可伸缩空位。
    static func spacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return spacer
    }

    /// 带 SF Symbols 图标的圆角按钮。
    static func button(title: String, symbol: String?, action: Selector,
                       keyEquivalent: String = "") -> NSButton {
        let button = NSButton(title: title, target: nil, action: action)
        button.bezelStyle = .rounded
        button.keyEquivalent = keyEquivalent
        if !keyEquivalent.isEmpty {
            button.keyEquivalentModifierMask = .command
        }
        if let symbol = symbol,
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
            button.image = image
            button.imagePosition = .imageLeading
        }
        return button
    }

    /// 只显示用的路径文字：可选中、中间截断。
    static func pathLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        label.lineBreakMode = .byTruncatingMiddle
        label.isSelectable = true
        label.textColor = .secondaryLabelColor
        label.setContentHuggingPriority(.init(1), for: .horizontal)
        label.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return label
    }

    /// 两列表单：左列说明（宽度取最宽那条）、右列控件（吃掉剩余宽度）。
    static func grid(rows: [(title: String, view: NSView)]) -> NSStackView {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.distribution = .fill
        column.spacing = rowGap

        let labelWidth = max(56, ceil(rows.map { label($0.title).fittingSize.width }.max() ?? 56))
        for entry in rows {
            let title = label(entry.title)
            title.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
            entry.view.setContentHuggingPriority(.init(1), for: .horizontal)

            let row = NSStackView(views: [title, entry.view])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fill
            row.spacing = 10
            column.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }
        return column
    }

    /// 一条分隔线。
    static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    /// 圆角、带细分隔线描边的容器，画布用它包住自己。
    static func panel(_ view: NSView) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }
}
