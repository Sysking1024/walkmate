import AVFoundation
import Foundation

/// 基于阿里云百炼语音合成模型的朗读渲染器。
///
/// 为什么不用系统自带的 `AVSpeechSynthesizer`：系统音色机械、缺乏语调起伏，
/// 而这条线的产物是要分享进社群、由人反复收听的，音质直接决定成品观感。
/// 系统合成器降级为断网兜底，见 `SpeechRenderer`。
///
/// 走 DashScope 原生端点，返回的是一个临时 WAV 下载地址，需要再取一次。
struct QwenSpeechRenderer {

    /// 语音合成模型
    private let model = "qwen3-tts-flash"
    /// 音色。Cherry 为女声，语调自然、偏温和。
    private let voice = "Cherry"
    private let timeoutSeconds: TimeInterval = 45

    private let apiKey: String
    private let dashScopeURL: URL
    private let session: URLSession

    /// 从被版本库忽略的 Secrets.plist 读取凭据，缺失时返回 nil 以便上层走兜底
    init?(bundle: Bundle = .main) {
        guard
            let url = bundle.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
            let key = dict["QwenAPIKey"], !key.isEmpty,
            let base = dict["QwenDashScopeURL"], let dashScopeURL = URL(string: base)
        else {
            Log.warning(.narration, "未找到语音合成凭据，将退回系统音色")
            return nil
        }
        self.apiKey = key
        self.dashScopeURL = dashScopeURL

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeoutSeconds
        // 相机以自身热点提供视频流时手机没有外网，需要允许回落到蜂窝网络
        configuration.allowsCellularAccess = true
        self.session = URLSession(configuration: configuration)
    }

    /// 把一段文字合成为音频文件，并返回其实际时长。
    ///
    /// 时长由调用方用来反推字幕与画面的停留时间，因此必须取合成后的真实值，
    /// 不能按字数估算。
    func render(_ text: String, to audioURL: URL) async throws -> SpeechRenderer.RenderedSpeech {
        let downloadURL = try await requestAudioURL(for: text)

        let (temporaryURL, response) = try await session.download(from: downloadURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SpeechRenderError.downloadFailed
        }
        try? FileManager.default.removeItem(at: audioURL)
        try FileManager.default.moveItem(at: temporaryURL, to: audioURL)

        let durationMs = try await measureDurationMs(of: audioURL)
        Log.info(.narration, "云端语音渲染完成，时长 \(durationMs) 毫秒")
        return SpeechRenderer.RenderedSpeech(audioURL: audioURL, durationMs: durationMs, text: text)
    }

    /// 提交合成请求，取回音频的临时下载地址
    private func requestAudioURL(for text: String) async throws -> URL {
        var request = URLRequest(url: dashScopeURL.appendingPathComponent("services/aigc/multimodal-generation/generation"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "input": ["text": text, "voice": voice],
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            Log.error(.narration, "语音合成接口返回异常状态码 \(code)")
            throw SpeechRenderError.badStatus(code)
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let output = root["output"] as? [String: Any],
            let audio = output["audio"] as? [String: Any],
            let urlString = audio["url"] as? String
        else {
            throw SpeechRenderError.malformedResponse
        }

        // 接口返回的是明文 HTTP 地址，而 iOS 的 App Transport Security 默认拦截明文请求。
        // 对象存储同时支持 HTTPS，直接升级协议即可，无需为此放宽全局安全策略。
        let secured = urlString.hasPrefix("http://")
            ? "https://" + urlString.dropFirst("http://".count)
            : urlString
        guard let url = URL(string: secured) else { throw SpeechRenderError.malformedResponse }
        return url
    }

    /// 读取音频文件的实际时长
    private func measureDurationMs(of url: URL) async throws -> Int {
        let duration = try await AVURLAsset(url: url).load(.duration)
        return Int(CMTimeGetSeconds(duration) * 1_000)
    }
}
