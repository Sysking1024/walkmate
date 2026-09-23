import Foundation
import Observation
import SwiftUI

/// 使用者偏好，落在 UserDefaults；改动立即作用到伙伴对谈与朗读
@MainActor
@Observable
final class AppSettings {

    static let shared = AppSettings()

    /// 语音引导档位：0 详细，1 简洁，2 静音
    var guidance: Double { didSet { save("guidance", guidance); apply() } }
    /// 语速 0 到 1
    var speechRate: Double { didSet { save("speechRate", speechRate); apply() } }
    /// 字体大小 0 到 1
    var textScale: Double { didSet { save("textScale", textScale); apply() } }
    /// 每日训练时长目标（分钟），首页「完成」环按它计算
    var dailyGoalMinutes: Int { didSet { UserDefaults.standard.set(dailyGoalMinutes, forKey: "walkmate.dailyGoalMinutes") } }
    /// 每日成功避障目标（次）
    var dailyGoalObstacles: Int { didSet { UserDefaults.standard.set(dailyGoalObstacles, forKey: "walkmate.dailyGoalObstacles") } }
    /// 是否已看过首次使用引导
    var hasSeenGuide: Bool { didSet { UserDefaults.standard.set(hasSeenGuide, forKey: "walkmate.hasSeenGuide") } }

    private init() {
        let defaults = UserDefaults.standard
        guidance = defaults.object(forKey: "walkmate.guidance") as? Double ?? 0.5
        speechRate = defaults.object(forKey: "walkmate.speechRate") as? Double ?? 0.5
        textScale = defaults.object(forKey: "walkmate.textScale") as? Double ?? 0.4
        dailyGoalMinutes = defaults.object(forKey: "walkmate.dailyGoalMinutes") as? Int ?? 20
        dailyGoalObstacles = defaults.object(forKey: "walkmate.dailyGoalObstacles") as? Int ?? 15
        hasSeenGuide = defaults.bool(forKey: "walkmate.hasSeenGuide")
        apply()
    }

    enum GuidanceLevel { case detailed, brief, muted }

    var guidanceLevel: GuidanceLevel {
        guidance < 0.33 ? .detailed : (guidance < 0.67 ? .brief : .muted)
    }

    /// 对应系统动态字体档位，与主题缩放同步
    var dynamicTypeSize: DynamicTypeSize {
        let sizes: [DynamicTypeSize] = [.small, .medium, .large, .xLarge, .xxLarge, .xxxLarge]
        return sizes[min(5, max(0, Int((textScale * 5).rounded())))]
    }

    private func save(_ key: String, _ value: Double) { UserDefaults.standard.set(value, forKey: "walkmate.\(key)") }

    /// 把偏好写到各模块的可调参数上
    private func apply() {
        switch guidanceLevel {
        case .detailed: QwenSceneNarrator.descriptionCharacterLimit = 60
        case .brief: QwenSceneNarrator.descriptionCharacterLimit = 40
        case .muted: QwenSceneNarrator.descriptionCharacterLimit = 40
        }
        CompanionSession.autoPromptEnabled = guidanceLevel != .muted
        // 系统合成器语速区间约 0.3 到 0.65 听感自然，把滑杆映射进去
        SpeechRenderer.speechRate = Float(0.3 + speechRate * 0.35)
        // 0.4 为默认档（原尺寸），向左最小八五折，向右最大一点三倍
        WalkMateTheme.Fonts.scale = textScale < 0.4
            ? 0.85 + (textScale / 0.4) * 0.15
            : 1 + ((textScale - 0.4) / 0.6) * 0.3
    }
}
