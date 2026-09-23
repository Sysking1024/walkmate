import UIKit

/// 操作成功的反馈：读屏播报 + 轻震动。
///
/// 看不见界面的使用者双击之后需要知道「成功了」：进了新页面，或者动作已经生效。
/// 播报只在读屏开着时发出，震动任何时候都给。
@MainActor
enum AccessibilityFeedback {

    private static let haptic = UIImpactFeedbackGenerator(style: .light)
    private static let notice = UINotificationFeedbackGenerator()

    /// 进入了新页面：读屏播「已进入 X」并把焦点移到新页面
    static func screenChanged(_ title: String) {
        Log.info("已进入 \(title)", category: .ui)
        haptic.impactOccurred()
        guard UIAccessibility.isVoiceOverRunning else { return }
        // 稍等页面挂上，再播报，否则会被上一页的收尾播报吞掉
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            UIAccessibility.post(notification: .screenChanged, argument: "已进入\(title)")
        }
    }

    /// 换了页面但页面自己会把读屏焦点落到页头：只给震动，不播报，避免焦点被甩回底栏
    static func pageSwitched() {
        haptic.impactOccurred()
    }

    /// 动作已生效：读屏播一句结果
    static func done(_ message: String) {
        notice.notificationOccurred(.success)
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}
