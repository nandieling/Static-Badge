import Foundation

/// 跨线程读写一个值用的小盒子：闭包里捕获它会按引用走，`inout` 语义的写法在
/// 非转义闭包里会被判定为越界访问。
final class Box<Value> {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }
}
