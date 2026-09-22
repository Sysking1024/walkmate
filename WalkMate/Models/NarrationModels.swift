import Foundation

/// 场景描述的来源。用于在界面与日志中区分真实模型输出与离线兜底文案。
enum NarrationSource: String, Codable {
    /// 多模态大模型实时生成
    case model
    /// 网络不可用时的预置兜底文案
    case fallback
}

/// 单条场景描述：一帧全景画面对应的一段文字描述。
///
/// 这是描述线的核心数据单元，同时承担三个用途：
/// 界面上的图文时间线、语音播报的文本、以及导出短片的字幕来源。
struct SceneNarration: Codable, Identifiable, Equatable {
    let id: UUID
    /// 相对于本次训练开始时刻的毫秒偏移
    let offsetMs: Int
    /// 对应全景关键帧在沙盒中的文件名
    let frameFileName: String
    /// 描述正文
    let text: String
    /// 文字来源
    let source: NarrationSource

    init(id: UUID = UUID(), offsetMs: Int, frameFileName: String, text: String, source: NarrationSource) {
        self.id = id
        self.offsetMs = offsetMs
        self.frameFileName = frameFileName
        self.text = text
        self.source = source
    }
}

/// 单条字幕。时间轴单位统一为毫秒，便于与视频帧时间戳直接对齐。
struct SubtitleCue: Equatable {
    /// 起始时间（毫秒）
    let startMs: Int
    /// 结束时间（毫秒）
    let endMs: Int
    /// 字幕正文
    let text: String

    /// 持续时长（毫秒）
    var durationMs: Int { endMs - startMs }
}
