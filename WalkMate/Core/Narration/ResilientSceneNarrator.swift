import Foundation

/// 带降级的场景描述器。
///
/// 优先调用多模态模型；一旦凭据缺失、网络不可达或接口异常，立即退回离线兜底文案。
/// 这条降级路径是演示的生命线：现场网络不稳定时，描述功能必须照常出结果。
struct ResilientSceneNarrator: SceneNarrator {

    private let primary: SceneNarrator?
    private let fallback = FallbackSceneNarrator()

    init() {
        // 凭据缺失时 QwenSceneNarrator 构造失败，此处直接留空，全程走兜底
        primary = QwenSceneNarrator()
    }

    func describe(frameData: Data, offsetMs: Int, frameFileName: String) async throws -> SceneNarration {
        guard let primary else {
            return try await fallback.describe(frameData: frameData, offsetMs: offsetMs, frameFileName: frameFileName)
        }

        do {
            return try await primary.describe(frameData: frameData, offsetMs: offsetMs, frameFileName: frameFileName)
        } catch {
            Log.warning(.narration, "模型描述失败，退回离线兜底文案：\(error)")
            return try await fallback.describe(frameData: frameData, offsetMs: offsetMs, frameFileName: frameFileName)
        }
    }
}
