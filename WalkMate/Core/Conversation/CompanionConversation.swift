import Foundation

/// 伙伴对谈状态机。
///
/// 纯逻辑，不依赖任何 iOS 框架，也不自己读时钟——所有时间都由调用方以毫秒传入，
/// 因此可以完整单元测试。真实的传感器、网络与语音合成由外层接入。
///
/// 设计依据来自视障用户访谈：
/// - 主动开口，因为使用者「走过去的时候有很多，也不知道该问什么」；
/// - 但开场只征询一句，不做感官启发式追问（「你闻到花香了吗」这类会显得聒噪）；
/// - 一旦被拒绝就安静下来，冷却期内不再主动打扰。
struct CompanionConversation {

    /// 判定为驻足所需的持续时长。太短会在等红灯、侧身避让时误触发。
    static let standstillThresholdMs = 3_000
    /// 两次主动征询之间的最小间隔
    static let cooldownAfterSessionMs = 60_000
    /// 被拒绝后的冷却时长。明显长于常规冷却，体现「拒绝了就别再烦我」。
    static let cooldownAfterDeclineMs = 300_000
    /// 描述完毕后留给使用者追问的时间窗
    static let followUpWindowMs = 15_000
    /// 征询后等待答复的时间窗，超时按没有答复处理
    static let consentWindowMs = 8_000

    private(set) var stage: ConversationStage = .silent
    private(set) var turns: [ConversationTurn] = []

    /// 本轮对谈允许再次主动征询的最早时刻
    private var nextAllowedAskMs = 0
    /// 当前阶段的截止时刻，用于超时判定
    private var stageDeadlineMs = 0

    // MARK: - 外部事件

    /// 使用者已驻足达到阈值。返回是否应当开口征询。
    ///
    /// - Parameters:
    ///   - standstillDurationMs: 已经连续静止的时长
    ///   - nowMs: 当前时刻
    mutating func handleStandstill(standstillDurationMs: Int, nowMs: Int) -> Bool {
        // 仅在完全静默时考虑开口，避免打断正在进行的描述或应答
        guard stage == .silent else { return false }
        guard standstillDurationMs >= Self.standstillThresholdMs else { return false }
        guard nowMs >= nextAllowedAskMs else { return false }

        stage = .awaitingConsent
        stageDeadlineMs = nowMs + Self.consentWindowMs
        return true
    }

    /// 使用者对征询作出了答复
    mutating func handleConsent(_ reply: ConsentReply, nowMs: Int) {
        guard stage == .awaitingConsent else { return }

        switch reply {
        case .accepted:
            stage = .describing
        case .declined, .noReply:
            // 没有答复与明确拒绝同等对待：使用者可能根本不想被打扰
            stage = .silent
            nextAllowedAskMs = nowMs + Self.cooldownAfterDeclineMs
        }
    }

    /// 一段描述播报完毕，进入追问等待窗
    mutating func finishDescribing(nowMs: Int) {
        guard stage == .describing else { return }
        stage = .awaitingFollowUp
        stageDeadlineMs = nowMs + Self.followUpWindowMs
    }

    /// 使用者提出了追问
    mutating func handleFollowUp(question: String, nowMs: Int) {
        guard stage == .awaitingFollowUp else { return }
        record(.user, question, nowMs: nowMs)
        stage = .answering
    }

    /// 一次应答播报完毕，重新回到追问等待窗
    mutating func finishAnswering(nowMs: Int) {
        guard stage == .answering else { return }
        stage = .awaitingFollowUp
        stageDeadlineMs = nowMs + Self.followUpWindowMs
    }

    /// 使用者主动叫停整段对谈
    mutating func dismiss(nowMs: Int) {
        stage = .silent
        nextAllowedAskMs = nowMs + Self.cooldownAfterDeclineMs
    }

    /// 推进时钟，处理各阶段超时。返回超时后是否落回静默。
    @discardableResult
    mutating func tick(nowMs: Int) -> Bool {
        switch stage {
        case .awaitingConsent where nowMs >= stageDeadlineMs:
            // 征询无人应答，按拒绝处理并进入长冷却
            handleConsent(.noReply, nowMs: nowMs)
            return true
        case .awaitingFollowUp where nowMs >= stageDeadlineMs:
            // 没有追问，安静收尾，走常规冷却
            stage = .silent
            nextAllowedAskMs = nowMs + Self.cooldownAfterSessionMs
            return true
        default:
            return false
        }
    }

    /// 记录一轮发言
    mutating func record(_ speaker: ConversationTurn.Speaker, _ text: String, nowMs: Int) {
        turns.append(ConversationTurn(speaker: speaker, text: text, offsetMs: nowMs))
    }

    /// 距离下次可以主动征询还剩多久，已可征询时为 0
    func remainingCooldownMs(nowMs: Int) -> Int {
        max(0, nextAllowedAskMs - nowMs)
    }
}
