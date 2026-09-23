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
                if let clip = Self.clipRange(for: index, in: moments, maxSeconds: Double(speech.durationMs + paddingMs) / 1_000) {
                    // 录下的预览是拼好的等矩形全景：按全景裁出竖向窗口并横扫，描述里的左右两边都会扫到
                    segments.append(.init(source: .video(clip.url, start: clip.start, end: clip.end),
                                          durationMs: speech.durationMs + paddingMs))
                } else {
                    segments.append(.init(
                        source: .image(moment.frameURL),
                        durationMs: speech.durationMs + paddingMs,
                        viewRange: Self.viewRange(forFrameAt: moment.frameURL)
                    ))
                }
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
    /// 这一刻在录下的视频里对应的区间：从它被描述的时间起，到下一刻或视频结束
    private static func clipRange(for index: Int, in moments: [CompanionSession.Moment], maxSeconds: Double) -> (url: URL, start: Double, end: Double)? {
        let moment = moments[index]
        guard let url = moment.clipURL, let startMs = moment.clipStartMs, let durationMs = moment.clipDurationMs,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        let total = Double(durationMs) / 1_000
        var start = Double(moment.narration.offsetMs - startMs) / 1_000
        var end = total
        if index + 1 < moments.count, moments[index + 1].clipURL == url {
            end = Double(moments[index + 1].narration.offsetMs - startMs) / 1_000
        }
        // 描述是对停下来那一刻说的：从开口描述前 1 秒起，按原速放到这段配音结束，不把后面走路的画面压缩进来
        start = min(max(0, start - 1), total)
        end = min(end, start + maxSeconds, total)
        // 剩余素材不够时往前挪，尽量凑满原速时长
        if end - start < maxSeconds { start = max(0, end - maxSeconds) }
        guard end - start >= 0.5 else { return nil }
        return (url, start, end)
    }

    private static func viewRange(forFrameAt url: URL) -> ClosedRange<CGFloat>? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 512,
              ] as CFDictionary) else { return nil }
        return QwenSceneNarrator.detectLayout(of: image) == .dualFisheye ? 0.22...0.28 : nil
    }
}
