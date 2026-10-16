import AppKit

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var trimmedNilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

/// 界面上共用的小东西：弹窗、秒数显示。
enum UI {
    static func present(style: NSAlert.Style, title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    /// 需要用户点头的确认框。
    static func confirm(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 秒表式时间：`01:23`，带小数位时是 `01:23.45`。
    static func clock(_ seconds: TimeInterval, fractionDigits: Int = 0) -> String {
        let total = max(0, seconds)
        let minutes = Int(total) / 60
        let rest = total - Double(minutes * 60)
        guard fractionDigits > 0 else {
            return String(format: "%02d:%02d", minutes, Int(rest))
        }
        return String(format: "%02d:%0\(fractionDigits + 3).\(fractionDigits)f", minutes, rest)
    }

    /// 用户在输入框里写的秒数，容错中文逗号和空格。
    static func parseSeconds(_ text: String?) -> TimeInterval? {
        guard var text = text?.trimmedNilIfEmpty else { return nil }
        if text.hasSuffix("秒") { text = String(text.dropLast()) }
        let normalized = text.replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(normalized), value.isFinite else { return nil }
        return max(0, value)
    }

    static func byteText(_ count: Int) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
        return size
    }

    /// 体积上限（MB）。允许写 `5`、`5.5`、`5 MB`、`5兆` 这类写法。
    static func parseMegabytes(_ text: String?) -> Double? {
        guard let raw = text?.trimmedNilIfEmpty else { return nil }
        // 只取开头的数字部分，后面的单位直接忽略。
        var kept = ""
        for character in raw {
            guard character.isNumber || character == "." || character == "," || character == "，"
            else { break }
            kept.append(character)
        }
        let normalized = kept.replacingOccurrences(of: "，", with: ".")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, value > 0 else { return nil }
        return value
    }

    /// MB 数的好看写法：整数不带小数点，其余保留两位。
    static func megabyteText(_ megabytes: Double) -> String {
        megabytes == megabytes.rounded()
            ? String(format: "%.0f MB", megabytes)
            : String(format: "%.2f MB", megabytes)
    }
}

/// 主线程和后台线程共用一个值时的最小安全盒。
final class Box<Value> {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
