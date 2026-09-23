import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 基于阿里云百炼多模态模型的场景描述器。
///
/// 走 OpenAI 兼容端点（`/compatible-mode/v1/chat/completions`），
/// 请求体与响应结构均已通过真机联调实测验证。
///
/// 输入可以是等矩形全景图，也可以是未拼接的双鱼眼原图，按四角亮度自动判别并选用对应提示词。
/// 真机实测：相机 SDK 渲染管线取到的实时帧是 2656×1328 的双鱼眼原图。
/// 实测数据（qwen3-vl-plus）：耗时几乎完全由上传体积决定。
/// 全景图压到 768 像素长边、约 36KB 时，单次描述约 5 至 7 秒，追问约 2 至 3 秒，
/// 足以支撑使用者驻足时的即时对谈。
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

    /// 首次描述的字数上限。约合 10 秒朗读，再长使用者就听不住了。
    static let descriptionCharacterLimit = 45
    /// 追问应答的字数上限
    static let answerCharacterLimit = 40
    /// 生成长度的硬上限。只作兜底：实测模型并不稳定遵守提示词里的字数要求，
    /// 精确的字数控制由 `clamp(_:limit:)` 在句读处截断完成。
    private let maxOutputTokens = 150

    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession

    /// 全景帧的画面布局
    enum FrameLayout {
        /// 等矩形全景：横向 360 度展开，正中为正前方
        case equirectangular
        /// 未拼接的双鱼眼：两个圆形画面左右并排
        case dualFisheye
    }

    /// 判别一帧画面的布局。
    ///
    /// 相机 SDK 在不同取帧路径下给出的格式不同：渲染管线取到的是双鱼眼原图，
    /// 拼接输出取到的是等矩形全景。两者都要能描述，否则上游改动取帧方式时这里就会失效。
    /// 判别依据：鱼眼图的四角落在圆形画面之外，一律是黑的；全景图的四角是天花板或天空。
    static func detectLayout(of image: CGImage) -> FrameLayout {
        let width = image.width, height = image.height
        guard width > 16, height > 16,
              let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            return .equirectangular
        }
        let bytesPerRow = image.bytesPerRow
        let bytesPerPixel = max(1, image.bitsPerPixel / 8)
        // 取四角各一小块的平均亮度，避开单像素噪声
        let inset = 8
        var total = 0
        for (x, y) in [(inset, inset), (width - inset - 1, inset), (inset, height - inset - 1), (width - inset - 1, height - inset - 1)] {
            let offset = y * bytesPerRow + x * bytesPerPixel
            var sum = 0
            for channel in 0..<min(3, bytesPerPixel) { sum += Int(bytes[offset + channel]) }
            total += sum / min(3, bytesPerPixel)
        }
        let averageBrightness = total / 4
        return averageBrightness < 24 ? .dualFisheye : .equirectangular
    }

    /// 系统提示词。措辞逐条对应视障用户访谈结论，改动前请先复核：
    /// - 禁止图像空间用语：使用者看不见图片，只关心自己周围有什么；
    /// - 禁止模糊措辞：受访者明确表示「有就有没有就没有」，含糊表达会直接导致弃用；
    /// - 禁止安全判断：避障由端侧感知层负责，大模型有幻觉风险，不得介入安全决策；
    /// - 禁止反问：受访者指出过多启发式追问会显得聒噪。
    /// 两种布局各自的画面格式说明，拼进系统提示词
    private static func layoutDescription(_ layout: FrameLayout) -> String {
        switch layout {
        case .equirectangular:
            return "【画面格式】这是一张等矩形全景图，横向覆盖使用者周围完整 360 度。画面左右正中是使用者的正前方，往左是左手边，往右是右手边，画面最左端与最右端相接处是使用者的正后方。画面上方是头顶，下方是脚下。"
        case .dualFisheye:
            return "【画面格式】这是全景相机的原始双鱼眼图：左边的圆是使用者正前方的半个球面，右边的圆是使用者身后的半个球面。"
        }
    }

    private static func systemPrompt(for layout: FrameLayout) -> String {
        """
    你是视障者随身的出行伙伴，用中文向看不见的人描述他此刻周围的环境。
    \(layoutDescription(layout))
    【方位规则】必须用使用者的身体方位说话：正前方、左手边、右手边、身后、头顶。绝对禁止出现『画面』『图像』『左侧』『右图』『镜头』『视角』这类描述图片本身的词——使用者看不见图片，他只想知道自己周围有什么。
    【内容规则】
    1. 只说你确实看到的，不推测。禁止『可能』『似乎』『好像』『大概』。
    2. 绝对不做安全判断，不说『可以走』『很安全』『注意避开』。
    3. 距离给大致米数。
    4. 只挑两三处最值得说的，不要把每个方向都念一遍。优先说有人在做什么、有标志性的建筑或招牌、有路或门的地方。
    5. 细节要具体：颜色、材质、光线。少用空泛形容词。
    6. 离得最近、手里拿着或身上戴着相机的那个人就是使用者本人，连同他的手臂和自拍杆，一律不要提。
    7. 不要向使用者提问。
    8. 总共不超过 45 个字。这段文字会被朗读出来，太长会让人听不住。
    """
    }

    /// 追问阶段的系统提示词。
    ///
    /// 与首次描述共享同样的事实与方位约束，但允许更自然的对话语气：
    /// 此时是使用者主动开口在问，不再是系统单向播报。
    private static func followUpSystemPrompt(for layout: FrameLayout) -> String {
        """
    你是视障者随身的出行伙伴，正和他站在同一个地方聊天。你能看见他周围的环境，他看不见。
    \(layoutDescription(layout))
    【方位规则】用他的身体方位说话：正前方、左手边、右手边、身后、头顶。绝对禁止出现『画面』『图像』『照片』『镜头』这类描述图片本身的词。
    【内容规则】
    1. 只说你确实看到的。看不清或画面里没有，就直说「这我看不清」，绝不编造。
    2. 绝对不做安全判断，不说『可以走』『很安全』『注意避开』。
    3. 只回答他问的，不要主动扯开话题，也不要反过来考他。
    4. 离得最近、拿着或戴着相机的那个人就是他自己，不要把他当成路人来描述。
    5. 像朋友说话那样自然，不超过 40 个字。这段文字会被朗读出来。
    """
    }

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
            Log.warning("未找到有效的 Secrets.plist 凭据，将退回离线兜底描述", category: .narration)
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
            Log.error("描述接口返回异常状态码 \(code)", category: .narration)
            throw NarrationError.badStatus(code)
        }

        let text = Self.clamp(try parseContent(from: data), limit: Self.descriptionCharacterLimit)
        Log.info("已生成场景描述，偏移 \(offsetMs) 毫秒，长度 \(text.count) 字", category: .narration)
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

        let prepared = prepareForUpload(frameData)
        let dataURI = "data:image/jpeg;base64,\(prepared.data.base64EncodedString())"

        // 首条用户消息携带画面，其后按原顺序还原对话
        var messages: [[String: Any]] = [
            ["role": "system", "content": Self.followUpSystemPrompt(for: prepared.layout)],
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
            "max_tokens": maxOutputTokens,
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            Log.error("追问接口返回异常状态码 \(code)", category: .narration)
            throw NarrationError.badStatus(code)
        }
        let text = Self.clamp(try parseContent(from: data), limit: Self.answerCharacterLimit)
        Log.info("已回答追问，长度 \(text.count) 字", category: .narration)
        return text
    }

    /// 构造 OpenAI 兼容格式的请求体，图片以 base64 data URI 内联
    private func requestBody(frameData: Data) -> [String: Any] {
        let prepared = prepareForUpload(frameData)
        let dataURI = "data:image/jpeg;base64,\(prepared.data.base64EncodedString())"
        return [
            "model": model,
            "max_tokens": maxOutputTokens,
            "messages": [
                ["role": "system", "content": Self.systemPrompt(for: prepared.layout)],
                ["role": "user", "content": [
                    ["type": "image_url", "image_url": ["url": dataURI]],
                    ["type": "text", "text": "描述我周围的环境。"],
                ]],
            ],
        ]
    }

    /// 上传前的准备：压缩体积并判别布局。压缩失败时退回原图，宁可慢也不能不出结果。
    private func prepareForUpload(_ data: Data) -> (data: Data, layout: FrameLayout) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let scaled = compressForUpload(source) else {
            return (data, .equirectangular)
        }
        let layout = Self.detectLayout(of: scaled.image)
        Log.debug("画面布局判别为 \(layout == .dualFisheye ? "双鱼眼" : "等矩形全景")", category: .narration)
        return (scaled.data, layout)
    }

    /// 按长边上限缩放并重新编码为 JPEG，把上传体积压到几十 KB 量级
    private func compressForUpload(_ source: CGImageSource) -> (data: Data, image: CGImage)? {

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        // 缩略图统一转成 RGBA 位图，保证后续按字节读像素时布局可预期
        let width = scaled.width, height = scaled.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.draw(scaled, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let normalized = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, normalized, [
            kCGImageDestinationLossyCompressionQuality: compressionQuality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }

        Log.debug("上传图片已压缩至 \(output.length / 1024) KB", category: .narration)
        return (output as Data, normalized)
    }

    /// 把超长文字截到字数上限以内，并尽量落在句读处，避免念到半句戛然而止。
    ///
    /// 句号、问号、叹号、分号是更自然的收尾点，但只有在它能保住六成以上字数时才优先采用；
    /// 否则一个靠前的分号会把后面信息量更大的内容全部丢掉。此时改取最靠后的停顿，
    /// 包括逗号、顿号。截断点留下的逗号或分号改成句号，读起来是完整收尾。
    /// 一个标点都没有才按字数硬切。
    static func clamp(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))

        let strongStops: Set<Character> = ["。", "！", "？", "；"]
        let allStops = strongStops.union(["，", "、"])
        let minimumKept = limit * 6 / 10

        let strongCut = head.lastIndex(where: strongStops.contains)
        let cut: String.Index?
        if let strongCut, head.distance(from: head.startIndex, to: strongCut) + 1 >= minimumKept {
            cut = strongCut
        } else {
            cut = head.lastIndex(where: allStops.contains)
        }

        guard let cut else { return head + "。" }
        var clipped = String(head[...cut])
        if let last = clipped.last, last != "。", last != "！", last != "？" {
            clipped.removeLast()
            clipped.append("。")
        }
        return clipped
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
