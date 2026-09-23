import AVFoundation
import Foundation

/// 徽章的听觉形态：每枚徽章一段 5 秒的专属旋律，点一下就播放。名字由系统读屏念，这里不重复。
///
/// 看不见徽章长什么样，也能靠这段旋律认出它、收集它。
@MainActor
final class BadgePlayer {

    static let shared = BadgePlayer()

    private var player: AVAudioPlayer?

    private init() {}

    /// 播放旋律
    func play(soundName: String, title: String) {
        SpeechRenderer.activatePlaybackSession()
        player?.stop()
        guard let url = Bundle.main.url(forResource: soundName, withExtension: "m4a") else {
            Log.warning("找不到徽章旋律：\(soundName)", category: .ui)
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
        Log.info("播放徽章：\(title)", category: .ui)
    }
}
