var failures = 0
func assertTrue(_ c: Bool, _ m: String) { if c { print("  ✓ \(m)") } else { print("  ✗ 失败：\(m)"); failures += 1 } }

print("用例6：超长无标点句切分应均衡，不留孤儿片段")
let longClause = "头顶白色天花板装有平行排列的长条荧光灯，"   // 20 字
let segs = SubtitleComposer.splitIntoSegments(longClause)
print("    切分结果：\(segs.map { "\($0)(\($0.count))" }.joined(separator: " | "))")
assertTrue(segs.allSatisfy { $0.count >= 4 }, "无长度小于 4 字的碎片")
assertTrue(segs.allSatisfy { $0.count <= SubtitleComposer.maxCharactersPerCue }, "均不超过上限")
assertTrue(segs.joined().count == longClause.count, "无字符丢失")

print("用例7：极长无标点文本均衡切分")
let noPunct = String(repeating: "甲", count: 50)
let s2 = SubtitleComposer.splitIntoSegments(noPunct)
print("    各段长度：\(s2.map(\.count))")
assertTrue(s2.allSatisfy { $0.count >= 4 }, "无过短碎片")
assertTrue((s2.map(\.count).max()! - s2.map(\.count).min()!) <= 1, "各段长度差不超过 1，分布均衡")
assertTrue(s2.joined().count == 50, "无字符丢失")

print("用例8：真实模型输出的字幕条数应可控")
let real = "正前方是开放式办公区，多排浅木色长桌并列，桌上摆着亮屏的电脑、水杯和文件，约6人坐在黑色转椅上操作设备；头顶白色天花板装有平行排列的长条荧光灯，部分区域有裸露的银色管道。"
let cues = SubtitleComposer.compose(from: [SceneNarration(offsetMs: 0, frameFileName: "f.jpg", text: real, source: .model)], totalDurationMs: 120_000)
print("    条数：\(cues.count)")
assertTrue(cues.count <= 8, "条数不超过 8（实际 \(cues.count)）")
assertTrue(cues.allSatisfy { $0.text.count >= 4 }, "无过短字幕")

print(failures == 0 ? "\n全部通过" : "\n有 \(failures) 项失败")
