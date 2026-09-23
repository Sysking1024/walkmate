import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import UIKit
import Observation

/// 伙伴会话：把实时全景帧、驻足检测、对谈状态机、场景描述与朗读串成运行中的闭环。
///
/// 数据从 `FrameBus` 进来，每帧做两件事：留下最新一帧，喂一条加速度给驻足检测器。
/// 检测到驻足满阈值就征询；使用者接受后，用驻足那一刻的画面生成描述并朗读，
/// 之后在同一帧上回答追问。每次描述都会落盘为一个「时刻」，供回家后粗剪使用。
///
/// 实时朗读用系统音色：离线、即时、稳定；云端音色留给成片。
@MainActor
@Observable
final class CompanionSession {

    /// 一次驻足留下的记录：那一刻的画面与伙伴的描述
    struct Moment: Identifiable {
        let id = UUID()
        let frameURL: URL
        let narration: SceneNarration
        /// 这次对谈期间录下的拼接预览视频，以及它开始录制的墙钟毫秒
        var clipURL: URL?
        var clipStartMs: Int?
        var clipDurationMs: Int?
    }

    private(set) var stage: ConversationStage = .silent
    private(set) var transcript: [ConversationTurn] = []
    private(set) var moments: [Moment] = []
    /// 当前已连续静止的毫秒数，供界面展示
    private(set) var standstillMs = 0
    /// 是否已收到过相机帧
    private(set) var hasFrames = false
    /// 正在等待模型或语音时为 true
    private(set) var isBusy = false
    /// 最近一次调试落盘的帧路径与尺寸
    private(set) var savedFrameNote: String?
    /// 语音指令是否在听
    private(set) var isListening = false
    /// 正在听到的话，供界面展示
    private(set) var heardText = ""

    private var conversation = CompanionConversation()
    private var detector = StandstillDetector()
    private let cloudNarrator = QwenSceneNarrator()
    private let fallbackNarrator = FallbackSceneNarrator()
    private let speech = SpeechRenderer()
    private let ciContext = CIContext()
    private let listener = VoiceCommandListener()
    private let recorder = ClipRecorder()
    /// 拼接预览视图，由训练页在相机连上后交给会话；对谈期间录它
    weak var captureView: UIView?
    /// 本次录制开始前已有的时刻数，停止时把视频挂到之后新增的时刻上
    private var momentsBeforeRecording = 0
    /// 唤醒时顺带问的问题，描述完立刻作答
    private var pendingQuestion: String?

    private var latestFrame: PanoramicFrame?
    /// 本次对谈锁定的那一帧，征询时就截下，保证描述的是使用者停下时看到的
    private var activeFrameJPEG: Data?
    private var subscription: UUID?
    private var ticker: Timer?

    private static let opener = "要我说说这儿吗？"
    /// 设置为「静音」时不再主动开口，只响应手动请求
    static var autoPromptEnabled = true

    // MARK: - 生命周期

    func start() {
        guard subscription == nil else { return }
        subscription = FrameBus.shared.subscribe { [weak self] frame in
            // 解码线程回调，切回主线程处理
            Task { @MainActor in self?.handle(frame) }
        }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        Log.info("伙伴会话已启动，开始订阅相机帧", category: .narration)
        startListening()
    }

    /// 开启语音指令：申请权限后持续听写，伙伴说话时暂停
    private func startListening() {
        speech.onSpeechFinished = { [weak self] in
            Task { @MainActor in self?.listener.resume() }
        }
        listener.onPartial = { [weak self] text in self?.heardText = text }
        listener.onUtterance = { [weak self] text in self?.handleVoice(text) }
        Task {
            guard await listener.requestAuthorization() else { return }
            listener.start()
            isListening = listener.isListening
        }
    }

    /// 语音指令：按当前对谈窗口解析并执行
    private func handleVoice(_ text: String) {
        heardText = ""
        let window: VoiceIntent.Window
        if isBusy { window = .busy } else {
            switch stage {
            case .awaitingConsent: window = .awaitingConsent
            case .awaitingFollowUp: window = .awaitingFollowUp
            case .silent: window = .idle
            case .describing, .answering: window = .busy
            }
        }
        guard let intent = VoiceIntent.parse(text, window: window) else { return }
        Log.info("语音意图：\(intent)", category: .narration)
        switch intent {
        case .yes: accept()
        case .no: decline()
        case .stop: dismiss()
        case .ask(let question): ask(question)
        case .describe(let question):
            pendingQuestion = question
            if stage == .awaitingConsent { accept() } else { describeNow() }
        }
    }

    func stop() {
        if recorder.isRecording { syncStageAfterStop() }
        listener.stop()
        isListening = false
        if let subscription { FrameBus.shared.unsubscribe(subscription) }
        subscription = nil
        ticker?.invalidate(); ticker = nil
        speech.stopSpeaking()
    }

    /// 训练结束时对谈可能还没收尾：先收掉录制
    private func syncStageAfterStop() {
        conversation.dismiss(nowMs: nowMs)
        syncStage()
    }

    // MARK: - 帧与时钟

    private func handle(_ frame: PanoramicFrame) {
        hasFrames = true
        latestFrame = frame
        standstillMs = detector.ingest(acceleration: frame.acceleration, timestampMs: frame.timestampMs)

        if conversation.handleStandstill(standstillDurationMs: standstillMs, nowMs: nowMs) {
            if Self.autoPromptEnabled { beginAsking() } else { conversation.handleConsent(.declined, nowMs: nowMs) }
        }
    }

    private func tick() {
        if conversation.tick(nowMs: nowMs) {
            Log.info("对谈阶段超时，回到静默", category: .narration)
        }
        syncStage()
    }

    private var nowMs: Int { Int(Date().timeIntervalSince1970 * 1_000) }

    private func syncStage() {
        stage = conversation.stage
        // 对谈一开始就录预览，回到静默时停下并挂到这轮留下的时刻上
        if stage != .silent, !recorder.isRecording, let captureView {
            momentsBeforeRecording = moments.count
            recorder.start(capturing: captureView, to: Self.momentsDirectory.appendingPathComponent("clip_\(nowMs).mp4"))
        } else if stage == .silent, recorder.isRecording {
            let startMs = recorder.startedAtMs
            Task { @MainActor in
                guard let clip = await recorder.stop() else { return }
                for index in momentsBeforeRecording..<moments.count {
                    moments[index].clipURL = clip.url
                    moments[index].clipStartMs = startMs
                    moments[index].clipDurationMs = clip.durationMs
                }
            }
        }
    }

    // MARK: - 对谈流程

    /// 驻足满阈值：截下当前画面并开口征询
    private func beginAsking() {
        activeFrameJPEG = latestFrame.flatMap { jpegData(from: $0.pixelBuffer) }
        say(Self.opener)
        syncStage()
        Log.info("检测到驻足 \(standstillMs) 毫秒，已开口征询", category: .narration)
    }

    /// 使用者答应了
    func accept() {
        conversation.handleConsent(.accepted, nowMs: nowMs)
        syncStage()
        Task { await describeActiveFrame() }
    }

    /// 使用者拒绝了：安静下来，进入长冷却
    func decline() {
        conversation.handleConsent(.declined, nowMs: nowMs)
        speech.stopSpeaking()
        syncStage()
    }

    /// 使用者主动要求描述，不经征询
    func describeNow() {
        guard conversation.handleManualRequest(nowMs: nowMs) else { return }
        activeFrameJPEG = latestFrame.flatMap { jpegData(from: $0.pixelBuffer) }
        syncStage()
        Task { await describeActiveFrame() }
    }

    /// 使用者提出追问
    func ask(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, stage == .awaitingFollowUp else { return }
        conversation.handleFollowUp(question: trimmed, nowMs: nowMs)
        transcript = conversation.turns
        syncStage()
        Task { await answerFollowUp(trimmed) }
    }

    /// 使用者叫停
    func dismiss() {
        conversation.dismiss(nowMs: nowMs)
        speech.stopSpeaking()
        syncStage()
    }

    private func describeActiveFrame() async {
        guard let frameJPEG = activeFrameJPEG else {
            say("我还没拿到画面，等相机连上再试。")
            conversation.dismiss(nowMs: nowMs); syncStage()
            return
        }
        isBusy = true
        defer { isBusy = false }

        let narration = await describe(frameJPEG)
        // say 会负责记录这一轮，这里不再单独记录，否则对话历史里会出现两遍
        say(narration.text)
        saveMoment(frameJPEG, narration: narration)

        // 朗读需要时间，估算念完再进入追问等待窗
        try? await Task.sleep(nanoseconds: UInt64(narration.text.count) * 230_000_000)
        conversation.finishDescribing(nowMs: nowMs)
        syncStage()

        // 唤醒时顺带问了问题：描述说完接着答
        if let question = pendingQuestion {
            pendingQuestion = nil
            Task { @MainActor in
                while speech.isSpeaking { try? await Task.sleep(nanoseconds: 200_000_000) }
                ask(question)
            }
        }
    }

    private func answerFollowUp(_ question: String) async {
        guard let frameJPEG = activeFrameJPEG else { return }
        isBusy = true
        defer { isBusy = false }

        let reply: String
        if let cloudNarrator {
            do {
                reply = try await cloudNarrator.answer(question: question, history: conversation.turns, frameData: frameJPEG)
            } catch {
                Log.warning("追问失败：\(error)", category: .narration)
                reply = "这会儿联系不上，稍后再问我。"
            }
        } else {
            reply = "这会儿联系不上，稍后再问我。"
        }
        say(reply)

        try? await Task.sleep(nanoseconds: UInt64(reply.count) * 230_000_000)
        conversation.finishAnswering(nowMs: nowMs)
        syncStage()
    }

    /// 云端描述优先，失败退回离线文案，保证一定出声
    private func describe(_ frameJPEG: Data) async -> SceneNarration {
        if let cloudNarrator {
            do {
                return try await cloudNarrator.describe(frameData: frameJPEG, offsetMs: nowMs, frameFileName: "live.jpg")
            } catch {
                Log.warning("云端描述失败，退回离线文案：\(error)", category: .narration)
            }
        }
        return (try? await fallbackNarrator.describe(frameData: frameJPEG, offsetMs: nowMs, frameFileName: "live.jpg"))
            ?? SceneNarration(offsetMs: nowMs, frameFileName: "live.jpg", text: "这会儿联系不上，稍后再试。", source: .fallback)
    }

    private func say(_ text: String) {
        conversation.record(.companion, text, nowMs: nowMs)
        transcript = conversation.turns
        // 自己说话时不听，免得把自己的声音当指令
        listener.suspend()
        speech.speak(text)
    }

    // MARK: - 落盘

    /// 把这一刻的画面与描述存下来，供回家后粗剪
    private func saveMoment(_ frameJPEG: Data, narration: SceneNarration) {
        let url = Self.momentsDirectory.appendingPathComponent("moment_\(nowMs).jpg")
        do {
            try frameJPEG.write(to: url)
            moments.append(Moment(frameURL: url, narration: narration))
        } catch {
            Log.error("时刻落盘失败：\(error)", category: .recording)
        }
    }

    /// 调试用：把最新一帧存成 JPEG，并记下尺寸与像素格式。
    /// 用来核实相机送来的到底是拼好的全景还是双鱼眼原图。
    func saveCurrentFrameForDebug() {
        guard let frame = latestFrame, let data = jpegData(from: frame.pixelBuffer) else {
            savedFrameNote = "还没有收到相机帧"
            return
        }
        let width = CVPixelBufferGetWidth(frame.pixelBuffer)
        let height = CVPixelBufferGetHeight(frame.pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(frame.pixelBuffer)
        let url = Self.momentsDirectory.appendingPathComponent("debug_\(nowMs).jpg")
        do {
            try data.write(to: url)
            savedFrameNote = "已保存 \(width)x\(height)，像素格式 \(format)，\(data.count / 1024) KB：\(url.lastPathComponent)"
            Log.info(savedFrameNote ?? "", category: .narration)
        } catch {
            savedFrameNote = "保存失败：\(error.localizedDescription)"
        }
    }

    private static var momentsDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("moments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 任意像素格式的全景帧转 JPEG；CoreImage 负责格式适配
    private func jpegData(from buffer: CVPixelBuffer) -> Data? {
        let image = CIImage(cvPixelBuffer: buffer)
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        return ciContext.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [quality: 0.8])
    }
}
