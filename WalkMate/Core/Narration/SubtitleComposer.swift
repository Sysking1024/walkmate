import Foundation

/// 字幕合成器：把场景描述列表转换为不重叠的字幕时间轴。
///
/// 纯计算逻辑，不依赖任何 iOS 框架，可独立单元测试。
/// 设计取舍：视障用户本人听语音即可，字幕服务的是分享出去之后的明眼观众，
/// 因此按明眼人的中文阅读速度排版，而非按语音播报节奏。
enum SubtitleComposer {

    /// 单条字幕的最大字数。超出则按标点切分，避免一屏文字过长。
    /// 取 24 字是按手机竖屏两行的容量定的：过小会把一句话切得过碎，读起来像机关枪。
    static let maxCharactersPerCue = 24
    /// 单条字幕的最小字数。短于此值的尾巴会并回上一条，避免出现「灯，」这类孤儿片段。
    static let minCharactersPerCue = 4
    /// 每个字的基准阅读耗时（毫秒）
    static let millisecondsPerCharacter = 180
    /// 单条字幕的最短显示时长（毫秒），保证短句也来得及看清
    static let minDurationMs = 1_500
    /// 单条字幕的最长显示时长（毫秒），避免长句占屏过久
    static let maxDurationMs = 5_000
    /// 相邻字幕之间的最小间隔（毫秒），防止视觉上连成一片
    static let minGapMs = 80

    /// 中文断句标点。切分后标点保留在前半句末尾，符合中文排版习惯。
    private static let breakPunctuation: Set<Character> = ["。", "！", "？", "，", "；", "、", "：", "\n"]

    /// 依据场景描述列表生成字幕时间轴。
    ///
    /// - Parameters:
    ///   - narrations: 场景描述列表，允许乱序
    ///   - totalDurationMs: 视频总时长，用于裁掉超出片尾的字幕
    /// - Returns: 按时间升序排列且互不重叠的字幕列表
    static func compose(from narrations: [SceneNarration], totalDurationMs: Int) -> [SubtitleCue] {
        // 先按时间排序，保证后续的重叠压缩逻辑只需向前看一条
        let sorted = narrations.sorted { $0.offsetMs < $1.offsetMs }

        // 每条描述先按标点切成若干短句，再依次排布到时间轴上
        var cues: [SubtitleCue] = []
        for narration in sorted {
            let segments = splitIntoSegments(narration.text)
            var cursorMs = max(0, narration.offsetMs)

            for segment in segments {
                // 超出视频长度的字幕直接丢弃，不做拉伸
                guard cursorMs < totalDurationMs else { break }

                let duration = estimateDurationMs(for: segment)
                let endMs = min(cursorMs + duration, totalDurationMs)
                // 压缩后若已无有效显示时长，说明片尾空间耗尽，停止排布
                guard endMs > cursorMs else { break }

                cues.append(SubtitleCue(startMs: cursorMs, endMs: endMs, text: segment))
                cursorMs = endMs + minGapMs
            }
        }

        return resolveOverlaps(cues)
    }

    /// 估算一段文字的显示时长，并钳制在上下限之间
    static func estimateDurationMs(for text: String) -> Int {
        let raw = text.count * millisecondsPerCharacter
        return min(max(raw, minDurationMs), maxDurationMs)
    }

    /// 按中文标点将长句切分为不超过字数上限的短句。
    /// 若某个标点片段本身仍然超长，则按字数硬切，保证不会产生超宽字幕。
    static func splitIntoSegments(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // 第一步：按标点切出自然短句，标点保留在句末
        var clauses: [String] = []
        var current = ""
        for character in trimmed {
            current.append(character)
            if breakPunctuation.contains(character) {
                let clause = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clause.isEmpty { clauses.append(clause) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { clauses.append(tail) }

        // 第二步：贪心合并相邻短句，在不超过字数上限的前提下尽量凑满一条
        var segments: [String] = []
        var buffer = ""
        for clause in clauses {
            if clause.count > maxCharactersPerCue {
                // 超长短句先落盘缓冲区，再对其本身做硬切
                if !buffer.isEmpty { segments.append(buffer); buffer = "" }
                segments.append(contentsOf: hardSplit(clause))
            } else if buffer.count + clause.count <= maxCharactersPerCue {
                buffer += clause
            } else {
                segments.append(buffer)
                buffer = clause
            }
        }
        if !buffer.isEmpty { segments.append(buffer) }

        return absorbShortTails(segments)
    }

    /// 对没有标点可依的超长文本按字数切分。
    ///
    /// 不采用「切满上限再留余数」的朴素做法：20 字按 18 切会得到 18 与 2，
    /// 那个 2 字尾巴在画面上就是一条孤儿字幕。改为先算需要几段，再按段数均分。
    private static func hardSplit(_ text: String) -> [String] {
        let total = text.count
        guard total > maxCharactersPerCue else { return [text] }

        // 向上取整算出段数与每段容量，使各段长度差不超过一个字
        let chunkCount = (total + maxCharactersPerCue - 1) / maxCharactersPerCue
        let chunkSize = (total + chunkCount - 1) / chunkCount

        var result: [String] = []
        var buffer = ""
        for character in text {
            buffer.append(character)
            if buffer.count == chunkSize {
                result.append(buffer)
                buffer = ""
            }
        }
        if !buffer.isEmpty { result.append(buffer) }
        return result
    }

    /// 把过短的片段并回上一条。
    ///
    /// 标点切分后贪心合并仍可能在末尾留下极短的一段（例如只剩「门，」两个字），
    /// 这里允许轻微超出字数上限，换取画面上不出现孤儿字幕。
    private static func absorbShortTails(_ segments: [String]) -> [String] {
        guard segments.count > 1 else { return segments }

        var result: [String] = []
        for segment in segments {
            if segment.count < minCharactersPerCue, let previous = result.last {
                result.removeLast()
                result.append(previous + segment)
            } else {
                result.append(segment)
            }
        }
        return result
    }

    /// 消除相邻字幕的时间重叠：后一条的起点优先，压缩前一条的终点。
    /// 若压缩后前一条已无有效时长，则将其丢弃，避免出现零长度字幕。
    ///
    /// 注意：字幕是逐条描述依次排布的，不同描述之间的时间区间会交叉，
    /// 因此必须先按起始时间重新排序，才能只向前看一条完成压缩。
    private static func resolveOverlaps(_ cues: [SubtitleCue]) -> [SubtitleCue] {
        guard cues.count > 1 else { return cues }

        var result: [SubtitleCue] = []
        for cue in cues.sorted(by: { $0.startMs < $1.startMs }) {
            guard let previous = result.last else {
                result.append(cue)
                continue
            }

            if cue.startMs < previous.endMs + minGapMs {
                let compressedEnd = cue.startMs - minGapMs
                result.removeLast()
                if compressedEnd > previous.startMs {
                    result.append(SubtitleCue(startMs: previous.startMs, endMs: compressedEnd, text: previous.text))
                }
            }
            result.append(cue)
        }
        return result
    }
}
