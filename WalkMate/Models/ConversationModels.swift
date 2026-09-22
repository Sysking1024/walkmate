import Foundation

/// 伙伴对谈的所处阶段。
///
/// 整条对谈由「使用者驻足」触发，走完「征询 → 描述 → 应答」后回到静默。
/// 任何一步都可以被使用者叫停，叫停后进入静默冷却，不再主动打扰。
enum ConversationStage: Equatable {
    /// 静默。不主动出声，等待下一次驻足。
    case silent
    /// 已征询，等待使用者答复是否需要描述
    case awaitingConsent
    /// 正在描述环境
    case describing
    /// 描述完毕，留出一段时间接受追问
    case awaitingFollowUp
    /// 正在回答追问
    case answering
}

/// 对谈中的一轮发言
struct ConversationTurn: Identifiable, Equatable {
    enum Speaker: String, Codable {
        /// 伙伴（系统）
        case companion
        /// 使用者
        case user
    }

    let id: UUID
    let speaker: Speaker
    let text: String
    /// 相对本次出行开始时刻的毫秒偏移
    let offsetMs: Int

    init(id: UUID = UUID(), speaker: Speaker, text: String, offsetMs: Int) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.offsetMs = offsetMs
    }
}

/// 使用者对征询的答复
enum ConsentReply: Equatable {
    /// 接受，需要描述
    case accepted
    /// 拒绝
    case declined
    /// 没有答复（超时）
    case noReply
}
