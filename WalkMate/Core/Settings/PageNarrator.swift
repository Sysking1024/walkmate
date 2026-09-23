import Foundation
import Observation
import UIKit

/// 页面朗读：进入一个页面时，用系统音色把这页是什么、能做什么说一遍。
///
/// 面向还没学会读屏的后天失明使用者。开着 VoiceOver 时不出声，避免两套声音打架；
/// 语音引导设为「静音」时也不出声。同一段话两秒内不重复。
@MainActor
final class PageNarrator {

    static let shared = PageNarrator()

    private let speech = SpeechRenderer()
    private var lastText = ""
    private var lastSpokenAt = Date.distantPast

    private init() {}

    var isEnabled: Bool {
        !UIAccessibility.isVoiceOverRunning && AppSettings.shared.guidanceLevel != .muted
    }

    /// 朗读一段页面说明；`force` 用于使用者主动要求再听一遍
    func announce(_ text: String, force: Bool = false) {
        guard force || isEnabled else { return }
        if !force, text == lastText, Date().timeIntervalSince(lastSpokenAt) < 2 { return }
        lastText = text
        lastSpokenAt = Date()
        speech.stopSpeaking()
        SpeechRenderer.activatePlaybackSession()
        speech.speak(text)
        Log.info("页面朗读：\(text.prefix(30))", category: .ui)
    }

    func stop() { speech.stopSpeaking() }
}
