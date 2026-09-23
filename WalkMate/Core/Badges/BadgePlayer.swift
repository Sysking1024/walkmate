import AVFoundation
import Foundation

/// 徽章的听觉形态：每枚徽章一段 5 秒的专属旋律，点一下就播放并报出名字。
///
/// 看不见徽章长什么样，也能靠这段旋律认出它、收集它。
@MainActor
final class BadgePlayer {

    static let shared = BadgePlayer()

    private var player: AVAudioPlayer?
    private let speech = SpeechRenderer()

    private init() {}

    /// 播放旋律，并在旋律起头后报出徽章名
    func play(soundName: String, title: String) {
        SpeechRenderer.activatePlaybackSession()
        speech.stopSpeaking()
        player?.stop()
        guard let url = Bundle.main.url(forResource: soundName, withExtension: "m4a") else {
            Log.warning("找不到徽章旋律：\(soundName)", category: .ui)
            speech.speak(title)
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.8
            player.play()
            self.player = player
        } catch {
            Log.warning("徽章旋律播放失败：\(error)", category: .ui)
        }
        // 旋律起头 0.6 秒后报名字，声音压在旋律之上
        Task { [speech] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            speech.speak(title)
        }
        Log.info("播放徽章：\(title)", category: .ui)
    }
}
