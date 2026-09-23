import AVFoundation
import Foundation

/// 语音合成器：把场景描述转成可朗读的声音。
///
/// 承担两个职责，且第二个才是关键：
/// 1. 在应用内即时朗读，供使用者当场收听；
/// 2. 把描述渲染成音频文件，混入导出的短片。
///
/// 第二点不可省略：这条线的产物是要分享进社群的，而社群里的接收方同样看不见。
/// 一段只有字幕没有语音的视频，对目标受众等于空白。
final class SpeechRenderer {

    /// 中文朗读音色。系统内置、离线可用，无需联网也无额外费用。
    private static let voiceIdentifier = "zh-CN"
    /// 朗读语速。系统默认值偏快，放慢一档以便听清方位与距离。
    private static let speechRate: Float = 0.48

    /// 合成器需在整个渲染过程中持有，提前释放会导致回调中断
    private let synthesizer = AVSpeechSynthesizer()

    /// 一段渲染好的语音
    struct RenderedSpeech {
        /// 音频文件路径（caf 格式，由系统合成器直接写出）
        let audioURL: URL
        /// 实际时长（毫秒）
        let durationMs: Int
        /// 对应的描述正文
        let text: String
    }

    /// 在应用内即时朗读一段文字
    func speak(_ text: String) {
        let utterance = makeUtterance(text)
        synthesizer.speak(utterance)
        Log.info("开始朗读描述，长度 \(text.count) 字", category: .narration)
    }

    /// 停止当前朗读
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// 把一段文字渲染成音频文件。
    ///
    /// 系统合成器以回调方式逐块吐出 PCM 缓冲，最后以一个零长度缓冲表示结束。
    /// 首个缓冲到达时才能确定音频格式，因此音频文件延迟到那时再创建。
    func render(_ text: String, to audioURL: URL) async throws -> RenderedSpeech {
        try? FileManager.default.removeItem(at: audioURL)

        var audioFile: AVAudioFile?
        var totalFrames: AVAudioFramePosition = 0
        var sampleRate: Double = 0

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var hasResumed = false
            synthesizer.write(makeUtterance(text)) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }

                // 零长度缓冲是结束信号
                guard pcm.frameLength > 0 else {
                    if !hasResumed { hasResumed = true; continuation.resume() }
                    return
                }

                do {
                    if audioFile == nil {
                        audioFile = try AVAudioFile(forWriting: audioURL, settings: pcm.format.settings)
                        sampleRate = pcm.format.sampleRate
                    }
                    try audioFile?.write(from: pcm)
                    totalFrames += AVAudioFramePosition(pcm.frameLength)
                } catch {
                    if !hasResumed { hasResumed = true; continuation.resume(throwing: error) }
                }
            }
        }

        guard audioFile != nil, sampleRate > 0, totalFrames > 0 else {
            throw SpeechRenderError.emptyOutput
        }
        // 主动释放句柄，确保文件头写盘完成后再被读取
        audioFile = nil

        let durationMs = Int(Double(totalFrames) / sampleRate * 1_000)
        Log.info("语音渲染完成，时长 \(durationMs) 毫秒", category: .narration)
        return RenderedSpeech(audioURL: audioURL, durationMs: durationMs, text: text)
    }

    private func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Self.voiceIdentifier)
        utterance.rate = Self.speechRate
        return utterance
    }
}

/// 语音渲染过程中的可预期错误
enum SpeechRenderError: Error {
    /// 合成器没有产出任何音频数据
    case emptyOutput
    /// 云端接口返回了非 200 状态码
    case badStatus(Int)
    /// 响应结构与预期不符
    case malformedResponse
    /// 音频文件下载失败
    case downloadFailed
}
