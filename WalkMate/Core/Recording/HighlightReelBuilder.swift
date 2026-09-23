import Foundation
import ImageIO
import Observation

/// 视频集锦生成器：把一次训练留下的「时刻」剪成带朗读与配乐的竖屏短片。
///
/// 这就是「回家后粗剪」：素材不是全程录像，而是使用者驻足并听了描述的那几帧——
/// 内容筛选在训练过程中已经由使用者自己完成了，这里只负责合成。
@MainActor
@Observable
final class HighlightReelBuilder {

    enum State: Equatable {
        case idle
        /// 正在生成，附带当前步骤说明
        case rendering(String)
        case ready(URL)
        case failed(String)
    }

    private(set) var state: State = .idle

    private let cloudVoice = QwenSpeechRenderer()
    private let systemVoice = SpeechRenderer()
    /// 两段之间的留白
    private let paddingMs = 700

    /// 生成集锦；没有时刻时直接返回，不产生空片
    func build(from moments: [CompanionSession.Moment]) async {
        guard !moments.isEmpty else { return }
        if case .rendering = state { return }

        var segments: [TrainingClipComposer.FrameSegment] = []
        var cues: [SubtitleCue] = []
        var speeches: [TrainingClipComposer.SpeechTrack] = []
        var cursorMs = 0

        do {
            for (index, moment) in moments.enumerated() {
                state = .rendering("正在合成第 \(index + 1) 段语音，共 \(moments.count) 段")
                let speech = try await renderSpeech(moment.narration.text, index: index)
                speeches.append(.init(audioURL: speech.audioURL, startMs: cursorMs))
                cues += SubtitleComposer.compose(forSpeech: moment.narration.text, startMs: cursorMs, speechDurationMs: speech.durationMs)
                segments.append(.init(
                    source: .image(moment.frameURL),
                    durationMs: speech.durationMs + paddingMs,
                    viewRange: Self.viewRange(forFrameAt: moment.frameURL)
                ))
                cursorMs += speech.durationMs + paddingMs
            }

            state = .rendering("正在剪辑画面")
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("walkmate_highlight.mp4")
            try await TrainingClipComposer.compose(
                segments: segments, cues: cues, speeches: speeches,
                musicURL: Bundle.main.url(forResource: "bgm", withExtension: "m4a"),
                outputURL: output
            )
            state = .ready(output)
            Log.info("视频集锦已生成，共 \(moments.count) 个时刻，时长 \(cursorMs / 1000) 秒", category: .recording)
        } catch {
            Log.error("视频集锦生成失败：\(error)", category: .recording)
            state = .failed("短片生成失败，稍后再试")
        }
    }

    /// 云端音色优先，失败退回系统音色，保证一定能出片
    private func renderSpeech(_ text: String, index: Int) async throws -> SpeechRenderer.RenderedSpeech {
        let directory = FileManager.default.temporaryDirectory
        if let cloudVoice {
            do {
                return try await cloudVoice.render(text, to: directory.appendingPathComponent("reel_\(index).wav"))
            } catch {
                Log.warning("云端语音失败，退回系统音色：\(error)", category: .recording)
            }
        }
        return try await systemVoice.render(text, to: directory.appendingPathComponent("reel_\(index).caf"))
    }

    /// 取景范围：双鱼眼原图只看正前方那个圆的中心区域，避免扫到圆外的黑边；
    /// 等矩形全景则横扫整幅画面
    private static func viewRange(forFrameAt url: URL) -> ClosedRange<CGFloat>? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 512,
              ] as CFDictionary) else { return nil }
        return QwenSceneNarrator.detectLayout(of: image) == .dualFisheye ? 0.22...0.28 : nil
    }
}
