var failures = 0
func check(_ c: Bool, _ m: String) { if c { print("  ✓ \(m)") } else { print("  ✗ 失败：\(m)"); failures += 1 } }
let f = QwenSceneNarrator.clamp

print("用例1：未超限原样返回")
check(f("左手边是竹林。", 45) == "左手边是竹林。", "短句不变")

print("用例2：靠前的分号不应吞掉后文，取最靠后的停顿")
let a = "左手边一排竹子，沿石板路种到尽头；右手边是红褐色竖条外墙的玻璃楼，楼门开在正前方约五米处，门口摆着两盆绿植。"
let r2 = f(a, 45); print("    → \(r2)（\(r2.count)字）")
check(r2.count <= 45, "不超 45 字")
check(r2.hasSuffix("。"), "以句号收尾")
check(r2.contains("玻璃楼"), "保住了右手边玻璃楼的信息")

print("用例2b：强停顿足够靠后时优先采用")
let c = "正前方是石板路，两旁种着细长的竹子，右手边是一栋红褐色外墙的玻璃楼。楼门口有两盆绿植，门上挂着招牌。"
let r2b = f(c, 45); print("    → \(r2b)")
check(r2b == "正前方是石板路，两旁种着细长的竹子，右手边是一栋红褐色外墙的玻璃楼。", "截在句号处")

print("用例3：没有强停顿时退到逗号")
let b = "正前方是一条很长的石板路，两旁种满了细长的竹子，右手边是一栋红褐色外立面的玻璃大楼，门口摆着绿植"
let r3 = f(b, 30); print("    → \(r3)")
check(r3.count <= 30 && r3.hasSuffix("。"), "不超限且句号收尾")
check(!r3.contains("，。"), "不出现逗号接句号")

print("用例4：完全无标点时硬切")
let r4 = f(String(repeating: "竹", count: 60), 45)
check(r4.count == 46 && r4.hasSuffix("。"), "45 字加句号")

print(failures == 0 ? "\n全部通过" : "\n有 \(failures) 项失败")
