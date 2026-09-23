import Foundation

/// 把一句口语解析成伙伴能执行的意图。纯函数，便于脚本测试。
///
/// 唤醒词：「walkmate」「伴行」（识别器对英文词的拼写不稳定，收录了几种常见写法）。
/// 没有唤醒词的话只在两种窗口里响应：伙伴刚问过「要我说说这儿吗」，或描述完等追问时。
enum VoiceIntent: Equatable {
    /// 描述周围（可带一句具体想问的）
    case describe(question: String?)
    /// 追问
    case ask(String)
    /// 答应征询
    case yes
    /// 拒绝征询
    case no
    /// 叫停
    case stop

    /// 对谈所处的窗口，决定不带唤醒词时怎么理解
    enum Window { case idle, awaitingConsent, awaitingFollowUp, busy }

    private static let wakeWords = ["walkmate", "walk mate", "walkmade", "workmate", "work mate", "walkme", "伴行", "沃克", "walk"]
    private static let stopWords = ["够了", "停", "安静", "别说", "不用了", "闭嘴", "谢谢", "可以了", "好了"]
    private static let noWords = ["不用", "不要", "不了", "算了", "别", "不"]
    private static let yesWords = ["好", "可以", "要", "嗯", "行", "说吧", "说说", "来", "是"]

    /// 解析一句话；返回 nil 表示与伙伴无关，忽略
    static func parse(_ raw: String, window: Window) -> VoiceIntent? {
        let text = normalize(raw)
        guard !text.isEmpty else { return nil }

        let (woke, command) = stripWakeWord(text)

        // 伙伴正在征询：先看是答应还是拒绝，「不用了」是拒绝而不是叫停
        if window == .awaitingConsent {
            if noWords.contains(where: { command.hasPrefix($0) }) { return .no }
            if yesWords.contains(where: { command.hasPrefix($0) }) { return .yes }
            if woke, isGenericDescribe(command) { return .yes }
            if woke { return .describe(question: command.isEmpty ? nil : command) }
            return nil
        }

        // 叫停：带唤醒词随时有效；不带的话只在伙伴正说话或等追问时听
        if stopWords.contains(where: { command.hasPrefix($0) }) {
            if woke || window != .idle { return .stop }
        }

        switch window {
        case .awaitingFollowUp:
            return command.count >= 2 ? .ask(command) : nil
        case .busy, .awaitingConsent:
            return nil
        case .idle:
            guard woke else { return nil }
            return isGenericDescribe(command) ? .describe(question: nil) : .describe(question: command)
        }
    }

    /// 「说说周围」这类泛泛的要求，和「左手边是什么」这类具体问题分开
    private static let genericPhrases = ["", "说说", "说说看", "描述", "描述一下", "看看", "说一下", "讲讲"]
    private static let surroundingWords = ["周围", "这儿", "这里", "环境", "四周", "附近", "旁边"]

    static func isGenericDescribe(_ command: String) -> Bool {
        if genericPhrases.contains(command) { return true }
        return surroundingWords.contains(where: { command.contains($0) })
    }

    /// 去掉标点空格，英文小写
    static func normalize(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let stripped = lowered.unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) && !CharacterSet.symbols.contains($0) }
        return String(String.UnicodeScalarView(stripped)).replacingOccurrences(of: "，", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 找唤醒词；返回是否命中，以及唤醒词之后的内容（英文词之间的空格一并去掉）
    static func stripWakeWord(_ text: String) -> (Bool, String) {
        for wake in wakeWords {
            if let range = text.range(of: wake) {
                let after = text[range.upperBound...].replacingOccurrences(of: " ", with: "")
                return (true, after.trimmingCharacters(in: .whitespaces))
            }
        }
        return (false, text.replacingOccurrences(of: " ", with: ""))
    }
}
