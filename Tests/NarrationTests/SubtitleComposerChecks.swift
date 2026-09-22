// 字幕合成器验证脚本：断言不重叠、不超界、字数受控
func assertTrue(_ cond: Bool, _ msg: String) {
    if cond { print("  ✓ \(msg)") } else { print("  ✗ 失败：\(msg)"); failures += 1 }
}
var failures = 0

print("用例1：单条短描述")
let n1 = [SceneNarration(offsetMs: 0, frameFileName: "f0.jpg", text: "你在湖边。", source: .model)]
let c1 = SubtitleComposer.compose(from: n1, totalDurationMs: 30_000)
assertTrue(c1.count == 1, "生成 1 条字幕，实际 \(c1.count)")
assertTrue(c1[0].durationMs == SubtitleComposer.minDurationMs, "短句取最短时长 \(c1[0].durationMs)ms")

print("用例2：长描述按标点切分且每条不超字数上限")
let long = "你在湖边，水声来自湖边的小瀑布，笑声来自湖上划船的两个人，太阳快落下去了，水面是橙色的，音乐是从右手边二十米的咖啡店传来的。"
let c2 = SubtitleComposer.compose(from: [SceneNarration(offsetMs: 0, frameFileName: "f.jpg", text: long, source: .model)], totalDurationMs: 60_000)
assertTrue(c2.count > 1, "长句被切分为 \(c2.count) 条")
assertTrue(c2.allSatisfy { $0.text.count <= SubtitleComposer.maxCharactersPerCue }, "每条均不超过 \(SubtitleComposer.maxCharactersPerCue) 字")
assertTrue(c2.map(\.text).joined().count == long.count, "切分无字符丢失")

print("用例3：乱序输入 + 时间重叠")
let n3 = [
    SceneNarration(offsetMs: 2_000, frameFileName: "b.jpg", text: "右手边是一排长椅。", source: .model),
    SceneNarration(offsetMs: 0,     frameFileName: "a.jpg", text: "前方是一条很长的走廊，地面平整，尽头有一扇开着的门。", source: .model),
]
let c3 = SubtitleComposer.compose(from: n3, totalDurationMs: 30_000)
assertTrue(c3 == c3.sorted { $0.startMs < $1.startMs }, "输出按时间升序")
var overlap = false
for i in 1..<c3.count where c3[i].startMs < c3[i-1].endMs { overlap = true }
assertTrue(!overlap, "相邻字幕无重叠")
assertTrue(c3.allSatisfy { $0.durationMs > 0 }, "无零长度字幕")

print("用例4：超出视频长度的字幕被裁掉")
let c4 = SubtitleComposer.compose(from: [SceneNarration(offsetMs: 0, frameFileName: "f.jpg", text: long, source: .model)], totalDurationMs: 4_000)
assertTrue(c4.allSatisfy { $0.endMs <= 4_000 }, "全部字幕终点 <= 4000ms")
assertTrue(c4.count < c2.count, "片尾空间不足时丢弃多余字幕（\(c4.count) < \(c2.count)）")

print("用例5：空文本与纯空白")
assertTrue(SubtitleComposer.compose(from: [SceneNarration(offsetMs: 0, frameFileName: "f.jpg", text: "   ", source: .fallback)], totalDurationMs: 10_000).isEmpty, "空白描述不产生字幕")

print(failures == 0 ? "\n全部通过" : "\n有 \(failures) 项失败")
