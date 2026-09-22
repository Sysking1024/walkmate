import Foundation

/// 基于阿里云百炼多模态模型的场景描述器。
///
/// 走 OpenAI 兼容端点（`/compatible-mode/v1/chat/completions`），
/// 请求体与响应结构均已通过真机联调实测验证。
///
/// 实测数据（1536×768 全景图，qwen3-vl-plus）：单次调用约 11 至 13 秒。
/// 因此描述必须在训练结束后批量生成，不能在行走过程中实时调用。
struct QwenSceneNarrator: SceneNarrator {

    /// 采用的模型。实测 plus 的描述细节优于 flash，而两者耗时相当（瓶颈在图片上传）。
    private let model = "qwen3-vl-plus"
    /// 单张图片的请求超时。留足余量，超时后由上层降级到兜底文案。
    private let timeoutSeconds: TimeInterval = 40

    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession

    /// 系统提示词。措辞逐条对应视障用户访谈结论，改动前请先复核：
    /// - 禁止图像空间用语：使用者看不见图片，只关心自己周围有什么；
    /// - 禁止模糊措辞：受访者明确表示「有就有没有就没有」，含糊表达会直接导致弃用；
    /// - 禁止安全判断：避障由端侧感知层负责，大模型有幻觉风险，不得介入安全决策；
    /// - 禁止反问：受访者指出过多启发式追问会显得聒噪。
    private static let systemPrompt = """
    你是视障者随身的出行伙伴，用中文向看不见的人描述他此刻周围的环境。
    【画面格式】这是全景相机的原始双鱼眼图：左边的圆是使用者正前方的半个球面，右边的圆是使用者身后的半个球面。
    【方位规则】必须用使用者的身体方位说话：正前方、左手边、右手边、身后。绝对禁止出现『左侧画面』『右图』『鱼眼』『镜头』『视角』这类描述图片本身的词——使用者看不见图片，他只想知道自己周围有什么。
    【内容规则】
    1. 只说你确实看到的，不推测。禁止『可能』『似乎』『好像』『大概』。
    2. 绝对不做安全判断，不说『可以走』『很安全』『注意避开』。
    3. 距离给大致米数。
    4. 多写具体细节：颜色、光线、物体、人在做什么。少用空泛形容词。
    5. 不要向使用者提问。
    6. 三句话以内。
    """

    /// 从被版本库忽略的 Secrets.plist 读取凭据。
    /// 凭据缺失时返回 nil，由上层切换到离线兜底描述器。
    init?(bundle: Bundle = .main) {
        guard
            let url = bundle.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
            let key = dict["QwenAPIKey"], !key.isEmpty,
            let base = dict["QwenBaseURL"], let baseURL = URL(string: base)
        else {
            Log.warning(.narration, "未找到有效的 Secrets.plist 凭据，将退回离线兜底描述")
            return nil
        }
        self.apiKey = key
        self.baseURL = baseURL

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeoutSeconds
        // 相机以自身热点提供视频流时手机没有外网，需要允许回落到蜂窝网络
        configuration.allowsCellularAccess = true
        self.session = URLSession(configuration: configuration)
    }

    func describe(frameData: Data, offsetMs: Int, frameFileName: String) async throws -> SceneNarration {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(frameData: frameData))

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            Log.error(.narration, "描述接口返回异常状态码 \(code)")
            throw NarrationError.badStatus(code)
        }

        let text = try parseContent(from: data)
        Log.info(.narration, "已生成场景描述，偏移 \(offsetMs) 毫秒，长度 \(text.count) 字")
        return SceneNarration(offsetMs: offsetMs, frameFileName: frameFileName, text: text, source: .model)
    }

    /// 构造 OpenAI 兼容格式的请求体，图片以 base64 data URI 内联
    private func requestBody(frameData: Data) -> [String: Any] {
        let dataURI = "data:image/jpeg;base64,\(frameData.base64EncodedString())"
        return [
            "model": model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": [
                    ["type": "image_url", "image_url": ["url": dataURI]],
                    ["type": "text", "text": "描述我周围的环境。"],
                ]],
            ],
        ]
    }

    /// 从响应中取出描述正文
    private func parseContent(from data: Data) throws -> String {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw NarrationError.malformedResponse
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NarrationError.malformedResponse }
        return trimmed
    }
}

/// 场景描述过程中的可预期错误
enum NarrationError: Error {
    /// 接口返回了非 200 状态码
    case badStatus(Int)
    /// 响应结构与预期不符
    case malformedResponse
}
