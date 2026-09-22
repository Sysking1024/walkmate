import AVFoundation
import Foundation
import Observation

/// 训练记录编排：把关键帧走完「描述 → 朗读 → 字幕 → 成片」的完整流程。
///
/// 各阶段的先后是有约束的：语音必须先渲染出来，才知道每段实际多长，
/// 字幕与画面停留时长都由语音时长反推，而不是按字数估算。
@MainActor
@Observable
final class TrainingRecordViewModel {

    /// 流水线所处阶段。对外只暴露一句中文状态，供界面与读屏直接使用。
    enum Phase: Equatable {
        case idle
        case describing
        case rendering
        case composing
        case ready
        case failed(String)

        var statusText: String {
            switch self {
            case .idle: return "尚未生成记录"
            case .describing: return "正在识别环境"
            case .rendering: return "正在合成语音"
            case .composing: return "正在生成短片"
            case .ready: return "记录已生成"
            case .failed(let reason): return "生成失败，\(reason)"
            }
        }

        var isBusy: Bool {
            switch self {
            case .describing, .rendering, .composing: return true
            default: return false
                }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var narrations: [SceneNarration] = []
    /// 生成好的短片路径，可直接交给系统分享面板
    private(set) var clipURL: URL?

    private let narrator: SceneNarrator = ResilientSceneNarrator()
    private let speechRenderer = SpeechRenderer()

    /// 关键帧之间的留白，让听者在两段描述之间有停顿
    private let paddingMs = 700

    /// 朗读指定描述
    func speak(_ narration: SceneNarration) {
        configureAudioSessionForPlayback()
        speechRenderer.speak(narration.text)
    }

    /// 依次朗读全部描述
    func speakAll() {
        configureAudioSessionForPlayback()
        for narration in narrations {
            speechRenderer.speak(narration.text)
        }
    }

    func stopSpeaking() {
        speechRenderer.stopSpeaking()
    }

    /// 跑完整条流水线。
    ///
    /// 相机管线接通前先用工程内置的全景样张，接通后把 `sampleFrameURLs()` 换成真实关键帧即可。
    func generateRecord() async {
        let frameURLs = sampleFrameURLs()
        guard !frameURLs.isEmpty else {
            phase = .failed("未找到全景样张")
            return
        }

        // 第一步：识别环境。各帧互不依赖，并发请求以掩盖单帧约 12 秒的网络耗时
        phase = .describing
        let produced = await describeConcurrently(frameURLs: frameURLs)
        guard !produced.isEmpty else {
            phase = .failed("未能生成任何描述")
            return
        }
        narrations = produced

        // 第二步：渲染语音。合成器是有状态的，必须串行
        phase = .rendering
        do {
            let timeline = try await renderTimeline(narrations: produced, frameURLs: frameURLs)

            // 第三步：合成短片
            phase = .composing
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("walkmate_record.mp4")
            try await TrainingClipComposer.compose(
                segments: timeline.segments,
                cues: timeline.cues,
                speeches: timeline.speeches,
                musicURL: Bundle.main.url(forResource: "bgm", withExtension: "m4a"),
                outputURL: output
            )
            clipURL = output
            phase = .ready
            Log.info(.recording, "训练记录短片已生成，共 \(produced.count) 段描述")
        } catch {
            Log.error(.recording, "短片合成失败：\(error)")
            phase = .failed("短片合成出错")
        }
    }

    // MARK: - 各阶段实现

    /// 并发生成各帧描述，再按帧序归位
    private func describeConcurrently(frameURLs: [URL]) async -> [SceneNarration] {
        await withTaskGroup(of: (Int, SceneNarration)?.self) { group in
            for (index, url) in frameURLs.enumerated() {
                group.addTask { [narrator] in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    do {
                        // 此处的偏移仅用于排序，真实时间轴在语音渲染后重建
                        let narration = try await narrator.describe(
                            frameData: data,
                            offsetMs: index,
                            frameFileName: url.lastPathComponent
                        )
                        return (index, narration)
                    } catch {
                        Log.error(.narration, "第 \(index + 1) 帧描述失败：\(error)")
                        return nil
                    }
                }
            }
            var collected: [(Int, SceneNarration)] = []
            for await item in group {
                if let item { collected.append(item) }
            }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private struct Timeline {
        let segments: [TrainingClipComposer.FrameSegment]
        let cues: [SubtitleCue]
        let speeches: [TrainingClipComposer.SpeechTrack]
    }

    /// 逐段渲染语音，并以实际语音时长为准构建画面与字幕时间轴
    private func renderTimeline(narrations: [SceneNarration], frameURLs: [URL]) async throws -> Timeline {
        var segments: [TrainingClipComposer.FrameSegment] = []
        var cues: [SubtitleCue] = []
        var speeches: [TrainingClipComposer.SpeechTrack] = []
        var cursorMs = 0

        for (index, narration) in narrations.enumerated() {
            let audioURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("speech_\(index).caf")
            let speech = try await speechRenderer.render(narration.text, to: audioURL)

            speeches.append(.init(audioURL: audioURL, startMs: cursorMs))
            cues += SubtitleComposer.compose(
                forSpeech: narration.text,
                startMs: cursorMs,
                speechDurationMs: speech.durationMs
            )
            segments.append(.init(
                imageURL: frameURLs[min(index, frameURLs.count - 1)],
                durationMs: speech.durationMs + paddingMs
            ))
            cursorMs += speech.durationMs + paddingMs
        }

        return Timeline(segments: segments, cues: cues, speeches: speeches)
    }

    /// 工程内置的等矩形全景样张，用于相机管线接通前的完整流程验证
    private func sampleFrameURLs() -> [URL] {
        (1...3).compactMap { Bundle.main.url(forResource: "sample_erp_\($0)", withExtension: "jpg") }
    }

    /// 朗读前把音频会话切到播放模式，否则静音开关打开时听不到声音
    private func configureAudioSessionForPlayback() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Log.warning(.narration, "音频会话配置失败：\(error)")
        }
        #endif
    }
}
