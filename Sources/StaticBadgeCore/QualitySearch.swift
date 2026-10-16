import Foundation

/// 在“文件不超过上限”的前提下尽量保住画质。
///
/// libwebp 没有目标体积模式，只能多试几个画质点：先按 100 编一次，超限就再探 40，
/// 之后用 `体积 ≈ A × 画质^b` 这条幂律猜一个贴着上限的画质，猜歪了就在已知区间里
/// 对半折，总共不超过 `maxPasses` 次。
enum QualitySearch {
    struct Result {
        let quality: Int
        let data: Data
        let attempts: Int
    }

    /// `encode` 收到画质（1~100）和“本次压缩内部进度”的回调。
    static func search(limitBytes: Int, maxPasses: Int = 5,
                       encode: (Int, (Double) -> Void) throws -> Data,
                       progress: ((Double) -> Void)? = nil) throws -> Result {
        var tried: [(quality: Int, size: Int)] = []
        var best: (quality: Int, data: Data)?
        var attempt = 0
        while attempt < maxPasses {
            guard let quality = suggest(attempt: attempt, tried: tried,
                                        maxPasses: maxPasses, limitBytes: limitBytes) else { break }
            let data = try encode(quality) { ratio in
                progress?(min(0.99, (Double(attempt) + ratio) / Double(maxPasses)))
            }
            tried.append((quality, data.count))
            if data.count <= limitBytes, best == nil || quality > best!.quality {
                best = (quality, data)
            }
            attempt += 1
        }
        progress?(1)
        guard let best else {
            throw BadgeError.sizeLimitExceeded(limit: limitBytes,
                                               bestSize: tried.map(\.size).min() ?? 0)
        }
        return Result(quality: best.quality, data: best.data, attempts: attempt)
    }

    /// 下一个要试的画质；返回 nil 表示不用再试了。
    private static func suggest(attempt: Int, tried: [(quality: Int, size: Int)],
                                maxPasses: Int, limitBytes: Int) -> Int? {
        guard attempt < maxPasses else { return nil }
        if attempt == 0 { return 100 }

        let lo = tried.filter { $0.size <= limitBytes }.map(\.quality).max()
        let hi = tried.filter { $0.size > limitBytes }.map(\.quality).min()
        if let lo, lo >= 100 { return nil }
        if let lo, let hi {
            // 已知“lo 塞得进、hi 塞不进”，只在这个区间里往上拱。
            guard hi - lo > 1 else { return nil }
            return pick(predict(tried: tried, limitBytes: limitBytes),
                        low: lo + 1, high: hi - 1, tried: tried)
        }
        if let hi {
            // 目前每一次都超限：一路往下压，留最后一次保底探到画质 1。
            if attempt >= maxPasses - 1 {
                return tried.contains { $0.quality == 1 } ? nil : 1
            }
            let guess = tried.count >= 2 ? predict(tried: tried, limitBytes: limitBytes) : 40
            return pick(guess, low: 1, high: hi - 1, tried: tried)
        }
        return nil
    }

    /// 猜的值要落在还没试过的区间里，否则退回区间中点。
    private static func pick(_ guess: Int, low: Int, high: Int,
                             tried: [(quality: Int, size: Int)]) -> Int? {
        guard low <= high else { return nil }
        let clamped = min(max(guess, low), high)
        if !tried.contains(where: { $0.quality == clamped }) { return clamped }
        let midpoint = (low + high) / 2
        guard !tried.contains(where: { $0.quality == midpoint }) else { return nil }
        return midpoint
    }

    /// 用跨度最大的两个点拟合 `体积 = A × 画质^b`，反解出贴着上限的画质。
    private static func predict(tried: [(quality: Int, size: Int)], limitBytes: Int) -> Int {
        let points = tried.sorted { $0.quality < $1.quality }
        guard let first = points.first, let last = points.last,
              first.quality >= 1, last.quality > first.quality,
              first.size >= 1, last.size > first.size else { return 1 }
        let exponent = log(Double(last.size) / Double(first.size))
            / log(Double(last.quality) / Double(first.quality))
        guard exponent > 0.01 else { return 1 }
        let logA = log(Double(first.size)) - exponent * log(Double(first.quality))
        let guess = exp((log(Double(max(1, limitBytes))) - logA) / exponent)
        guard guess.isFinite else { return 1 }
        return min(100, max(1, Int(guess.rounded())))
    }
}
