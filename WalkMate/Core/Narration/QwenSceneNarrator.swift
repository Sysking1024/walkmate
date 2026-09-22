import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 基于阿里云百炼多模态模型的场景描述器。
///
/// 走 OpenAI 兼容端点（`/compatible-mode/v1/chat/completions`），
/// 请求体与响应结构均已通过真机联调实测验证。
///
/// 输入为等矩形全景图（由相机 SDK 的 FlatPanoOutput 拼接输出）。
/// 实测数据（qwen3-vl-plus）：耗时几乎完全由上传体积决定。
/// 全景图压到 768 像素长边、约 36KB 时，单次调用约 5 秒。
/// 因此描述必须在训练结束后批量生成，不能在行走过程中实时调用。
struct QwenSceneNarrator: SceneNarrator {

    /// 采用的模型。实测 plus 的描述细节优于 flash，而两者耗时相当（瓶颈在图片上传）。
    private let model = "qwen3-vl-plus"
    /// 单张图片的请求超时。留足余量，超时后由上层降级到兜底文案。
    private let timeoutSeconds: TimeInterval = 40

    /// 上传前的图片长边上限（像素）。
    ///
    /// 实测端到端耗时几乎完全由上传体积决定，与模型选择无关：
    /// 同一张全景图 1564KB 耗时 44 秒，压到 36KB 只需 5 秒。
    /// 768 像素是质量拐点——再往下压到 512 像素时，描述里开始混入英文词。
    private let maxPixelSize = 768
    /// 上传前的 JPEG 压缩质量
    private let compressionQuality: CGFloat = 0.45

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
    【画面格式】这是一张等矩形全景图，横向覆盖使用者周围完整 360 度。画面左右正中是使用者的正前方，往左是左手边，往右是右手边，画面最左端与最右端相接处是使用者的正后方。画面上方是头顶，下方是脚下。
    【方位规则】必须用使用者的身体方位说话：正前方、左手边、右手边、身后、头顶。绝对禁止出现『画面』『图像』『左侧』『右图』『镜头』『视角』这类描述图片本身的词——使用者看不见图片，他只想知道自己周围有什么。
    【内容规则】
    1. 只说你确实看到的，不推测。禁止『可能』『似乎』『好像』『大概』。
    2. 绝对不做安全判断，不说『可以走』『很安全』『注意避开』。
    3. 距离给大致米数。
    4. 多写具体细节：颜色、光线、物体、人在做什么。少用空泛形容词。
    5. 不要向使用者提问。
    6. 总共不超过 60 个字。这段文字会被朗读出来，太长会让人听不住。
    """

    /// 追问阶段的系统提示词。
    ///
    /// 与首次描述共享同样的事实与方位约束，但允许更自然的对话语气：
    /// 此时是使用者主动开口在问，不再是系统单向播报。
    private static let followUpSystemPrompt = """
    你是视障者随身的出行伙伴，正和他站在同一个地方聊天。你能看见他周围的环境，他看不见。
    【方位规则】用他的身体方位说话：正前方、左手边、右手边、身后、头顶。绝对禁止出现『画面』『图像』『照片』『镜头』这类描述图片本身的词。
    【内容规则】
    1. 只说你确实看到的。看不清或画面里没有，就直说「这我看不清」，绝不编造。
    2. 绝对不做安全判断，不说『可以走』『很安全』『注意避开』。
    3. 只回答他问的，不要主动扯开话题，也不要反过来考他。
    4. 像朋友说话那样自然，两句话以内。这段文字会被朗读出来。
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

    /// 回答使用者针对同一处环境提出的追问。
    ///
    /// 把此前的对话原样带上，并重新附上同一帧画面：追问往往需要画面里的细节
    /// （「那家店叫什么」「那个人在做什么」），只靠先前的文字描述答不上来。
    ///
    /// - Parameters:
    ///   - question: 使用者的追问
    ///   - history: 本次驻足期间已经发生的对话
    ///   - frameData: 当时那一帧画面，与首次描述用的是同一张
    func answer(question: String, history: [ConversationTurn], frameData: Data) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = compressForUpload(frameData) ?? frameData
        let dataURI = "data:image/jpeg;base64,\(payload.base64EncodedString())"

        // 首条用户消息携带画面，其后按原顺序还原对话
        var messages: [[String: Any]] = [
            ["role": "system", "content": Self.followUpSystemPrompt],
            ["role": "user", "content": [
                ["type": "image_url", "image_url": ["url": dataURI]],
                ["type": "text", "text": "描述我周围的环境。"],
            ]],
        ]
        for turn in history {
            messages.append([
                "role": turn.speaker == .companion ? "assistant" : "user",
                "content": turn.text,
            ])
        }
        messages.append(["role": "user", "content": question])

        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": messages,
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            Log.error(.narration, "追问接口返回异常状态码 \(code)")
            throw NarrationError.badStatus(code)
        }
        let text = try parseContent(from: data)
        Log.info(.narration, "已回答追问，长度 \(text.count) 字")
        return text
    }

    /// 构造 OpenAI 兼容格式的请求体，图片以 base64 data URI 内联
    private func requestBody(frameData: Data) -> [String: Any] {
        let payload = compressForUpload(frameData) ?? frameData
        let dataURI = "data:image/jpeg;base64,\(payload.base64EncodedString())"
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

    /// 按长边上限缩放并重新编码为 JPEG，把上传体积压到几十 KB 量级。
    /// 压缩失败时返回 nil，由调用方退回原图，宁可慢也不能不出结果。
    private func compressForUpload(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, scaled, [
            kCGImageDestinationLossyCompressionQuality: compressionQuality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }

        Log.debug(.narration, "上传图片已压缩至 \(output.length / 1024) KB")
        return output as Data
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
