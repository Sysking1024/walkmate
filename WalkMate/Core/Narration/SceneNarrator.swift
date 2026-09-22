import Foundation

/// 场景描述服务协议。
///
/// 上层只依赖本协议，具体实现可以是多模态大模型，也可以是离线兜底文案。
/// 这样做有两个目的：一是模型接口尚未接入时界面与导出链路可以先跑通；
/// 二是现场网络不可用时能无缝降级，保证演示不中断。
protocol SceneNarrator {
    /// 为一帧全景画面生成文字描述。
    ///
    /// - Parameters:
    ///   - frameData: 全景关键帧的 JPEG 数据
    ///   - offsetMs: 该帧相对本次训练开始时刻的毫秒偏移
    ///   - frameFileName: 该帧在沙盒中的文件名
    func describe(frameData: Data, offsetMs: Int, frameFileName: String) async throws -> SceneNarration
}

/// 离线兜底描述器。
///
/// 按预置文案轮转输出，不访问网络。用于两种场景：
/// 一是大模型接口尚未接入时的开发联调；二是现场网络异常时的演示降级。
struct FallbackSceneNarrator: SceneNarrator {

    /// 预置文案。措辞遵循访谈结论：只陈述看到的事实，不做启发式追问，不说安全判断。
    private static let presetTexts = [
        "前方是一条走廊，地面平整，尽头有一扇开着的门。",
        "右手边靠墙放着一排椅子，左手边是空的。",
        "正前方两米处有一张方桌，桌角朝向你。",
        "走廊尽头是落地窗，午后的光从那里照进来。",
    ]

    func describe(frameData: Data, offsetMs: Int, frameFileName: String) async throws -> SceneNarration {
        // 按时间偏移轮转选取文案，保证同一次训练内的描述不重复
        let index = abs(offsetMs / 1_000) % Self.presetTexts.count
        Log.info(.narration, "使用离线兜底文案生成描述，偏移 \(offsetMs) 毫秒")
        return SceneNarration(
            offsetMs: offsetMs,
            frameFileName: frameFileName,
            text: Self.presetTexts[index],
            source: .fallback
        )
    }
}
