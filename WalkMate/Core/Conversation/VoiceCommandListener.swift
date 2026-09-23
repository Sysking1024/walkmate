import AVFoundation
import Foundation
import Speech

/// 训练中的持续听写：麦克风 → 系统语音识别 → 一句话说完就回调。
///
/// 为什么不用按住说话：使用者一只手拿相机或盲杖，另一只手要空出来。
/// 识别任务最长一分钟，到点自动重开；一句话以 1.2 秒没有新字为界。
/// 伙伴自己在说话时暂停听写，免得把自己的声音当成指令。
@MainActor
final class VoiceCommandListener {

    /// 一句话说完
    var onUtterance: ((String) -> Void)?
    /// 正在听到的内容，供界面展示
    var onPartial: ((String) -> Void)?

    private(set) var isListening = false
    private(set) var isAuthorized = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var lastPartial = ""
    private var settleTimer: Timer?
    private var restartTimer: Timer?
    private var suspended = false

    /// 申请麦克风与语音识别权限
    func requestAuthorization() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        isAuthorized = speech == .authorized && mic
        if !isAuthorized { Log.warning("语音指令未获授权：识别 \(speech.rawValue)，麦克风 \(mic)", category: .narration) }
        return isAuthorized
    }

    func start() {
        guard isAuthorized, !isListening, let recognizer, recognizer.isAvailable else {
            Log.warning("语音识别不可用，语音指令关闭", category: .narration)
            return
        }
        SpeechRenderer.recordingEnabled = true
        SpeechRenderer.activatePlaybackSession()
        do {
            try startEngine()
            isListening = true
            beginRecognition()
            NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
            Log.info("语音指令已开启，说「walkmate」唤起伙伴", category: .narration)
        } catch {
            Log.error("麦克风启动失败：\(error)", category: .narration)
        }
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        endRecognition()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isListening = false
        SpeechRenderer.recordingEnabled = false
    }

    /// 伙伴开口时暂停，说完再恢复；暂停期间听到的内容作废
    func suspend() {
        guard isListening, !suspended else { return }
        suspended = true
        endRecognition()
    }

    func resume() {
        guard isListening, suspended else { return }
        suspended = false
        beginRecognition()
    }

    // MARK: - 音频

    private func startEngine() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    /// 输出路由变了（比如队友的空间音频改了会话类别），把输入重新接上
    @objc private func handleRouteChange(_ notification: Notification) {
        guard isListening else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.isListening, !self.engine.isRunning else { return }
            do { try self.startEngine() } catch { Log.warning("路由变化后麦克风重启失败：\(error)", category: .narration) }
        }
    }

    // MARK: - 识别

    private func beginRecognition() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = false }
        self.request = request
        lastPartial = ""
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in self?.handle(result: result, error: error) }
        }
        // 系统限制单次任务约一分钟，提前重开
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.rollover() }
        }
    }

    private func endRecognition() {
        settleTimer?.invalidate(); settleTimer = nil
        restartTimer?.invalidate(); restartTimer = nil
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    /// 到点重开一个识别任务；手里有没说完的话就先交出去
    private func rollover() {
        guard isListening, !suspended else { return }
        let pending = lastPartial
        endRecognition()
        if !pending.isEmpty { deliver(pending) }
        beginRecognition()
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString
            if text != lastPartial {
                lastPartial = text
                onPartial?(text)
                // 1.2 秒没有新字，当作一句话说完
                settleTimer?.invalidate()
                settleTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
                    Task { @MainActor in self?.settle() }
                }
            }
            if result.isFinal { settle() }
        }
        if let error {
            // 长时间没人说话识别器会自己结束，重开即可
            let code = (error as NSError).code
            if isListening, !suspended {
                Log.debug("识别任务结束（\(code)），重开", category: .narration)
                let pending = lastPartial
                endRecognition()
                if !pending.isEmpty { deliver(pending) }
                beginRecognition()
            }
        }
    }

    private func settle() {
        let text = lastPartial
        guard !text.isEmpty, isListening, !suspended else { return }
        endRecognition()
        deliver(text)
        beginRecognition()
    }

    private func deliver(_ text: String) {
        Log.info("听到：\(text)", category: .narration)
        onUtterance?(text)
    }
}
