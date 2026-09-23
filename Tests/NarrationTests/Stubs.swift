// 脚本测试用的桩：替代 Log 与 SpeechRenderer，避免引入 UIKit/AVFoundation
enum Log {
    enum Category { case audio, ui, general, narration, recording, camera, perception }
    static func info(_ message: String, category: Category = .general) {}
    static func warning(_ message: String, category: Category = .general) {}
    static func error(_ message: String, category: Category = .general) {}
}
final class SpeechRenderer {
    var onSpeechFinished: (() -> Void)?
    var isSpeaking = false
    func speak(_ text: String) { print("  [朗读] \(text)") }
    func stopSpeaking() {}
}
