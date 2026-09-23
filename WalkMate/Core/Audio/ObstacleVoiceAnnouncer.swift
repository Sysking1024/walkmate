import Foundation

/// 外放时的避障语音：把最近的前向障碍说成「左前方一米有障碍」。
///
/// 手机外放是单声道，空间音频分不出左右，所以改用一句话报方位与距离。
/// 只报前向 130° 内、两米以内的最近一个；同一方位距离四秒内不重复；
/// 伙伴正在说话时不插嘴；障碍消失后报一次「前方畅通」。
@MainActor
final class ObstacleVoiceAnnouncer {

    /// 开口与说完的回调，供训练页暂停/恢复语音指令的听写
    var onSpeechStart: (() -> Void)?
    var onSpeechEnd: (() -> Void)?
    /// 是否允许此刻开口（伙伴在说话时返回 false）
    var canSpeak: () -> Bool = { true }

    private let speech = SpeechRenderer()
    private var lastKey = ""
    private var lastSpokenAt = Date.distantPast
    private var hadObstacle = false
    private var clearedAt: Date?

    init() {
        speech.onSpeechFinished = { [weak self] in
            Task { @MainActor in self?.onSpeechEnd?() }
        }
    }

    /// 报障碍的最远距离
    nonisolated static let maxDistance: Float = 2.0

    /// 一帧障碍数据对应的播报文案；没有需要报的返回 nil。纯函数，便于脚本测试。
    nonisolated static func phrase(for data: ObstacleData) -> (key: String, text: String)? {
        let candidates = data.obstacles.filter { abs($0.azimuth) <= 65 && $0.distance <= maxDistance && $0.distance > 0 }
        guard let nearest = candidates.min(by: { $0.distance < $1.distance }) else { return nil }

        let direction: String
        switch nearest.azimuth {
        case ..<(-60): direction = "左手边"
        case -60 ..< -20: direction = "左前方"
        case -20 ... 20: direction = "正前方"
        case 20 ... 60: direction = "右前方"
        default: direction = "右手边"
        }
        // 距离按半米取整
        let half = (nearest.distance * 2).rounded() / 2
        let distanceText: String
        if half <= 0.5 { distanceText = "半米" }
        else if half == half.rounded() { distanceText = "\(Int(half))米" }
        else { distanceText = String(format: "%.1f米", half) }
        return ("\(direction)|\(distanceText)", "\(direction)\(distanceText)有障碍")
    }

    func handle(_ data: ObstacleData) {
        let now = Date()
        guard let phrase = Self.phrase(for: data) else {
            // 刚才有障碍、现在没了：过 1.5 秒还是空，就说一声畅通
            if hadObstacle {
                if clearedAt == nil { clearedAt = now }
                if let clearedAt, now.timeIntervalSince(clearedAt) >= 1.5, canSpeak() {
                    say("前方畅通", key: "clear", at: now)
                    hadObstacle = false
                    self.clearedAt = nil
                }
            }
            return
        }
        clearedAt = nil
        hadObstacle = true
        let sinceLast = now.timeIntervalSince(lastSpokenAt)
        if phrase.key == lastKey, sinceLast < 4 { return }
        if sinceLast < 1.2 || speech.isSpeaking || !canSpeak() { return }
        say(phrase.text, key: phrase.key, at: now)
    }

    func stop() {
        speech.stopSpeaking()
    }

    private func say(_ text: String, key: String, at now: Date) {
        lastKey = key
        lastSpokenAt = now
        onSpeechStart?()
        speech.speak(text)
        Log.info("避障语音：\(text)", category: .audio)
    }
}
