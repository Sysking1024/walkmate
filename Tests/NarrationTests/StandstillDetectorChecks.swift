var failures = 0
func check(_ c: Bool, _ m: String) { if c { print("  ✓ \(m)") } else { print("  ✗ 失败：\(m)"); failures += 1 } }
let g: Float = 9.8
// 30Hz 采样，静止时模长在 9.8 附近微抖，行走时按步频 2Hz 起伏 ±2.5
func still(_ i: Int) -> SIMD3<Float> { SIMD3(0.05 * sin(Float(i)), g + 0.08 * cos(Float(i) * 0.7), 0.03) }
func walk(_ i: Int) -> SIMD3<Float> { SIMD3(0.4 * sin(Float(i) * 0.4), g + 2.5 * sin(Float(i) * 2 * .pi * 2 / 30), 0.3 * cos(Float(i) * 0.5)) }

print("用例1：样本不足时不判定")
var d1 = StandstillDetector()
var out = 0
for i in 0..<4 { out = d1.ingest(acceleration: still(i), timestampMs: Int64(i * 33)) }
check(out == 0, "4 个样本仍返回 0")

print("用例2：持续静止，返回值随时间累计")
var d2 = StandstillDetector()
var last = 0
for i in 0..<120 { last = d2.ingest(acceleration: still(i), timestampMs: Int64(i * 33)) }
check(last >= 3_000, "静止 4 秒后累计不少于 3 秒（实际 \(last)ms）")

print("用例3：行走时始终为 0")
var d3 = StandstillDetector()
var maxWalk = 0
for i in 0..<120 { maxWalk = max(maxWalk, d3.ingest(acceleration: walk(i), timestampMs: Int64(i * 33))) }
check(maxWalk == 0, "行走全程返回 0（最大 \(maxWalk)ms）")

print("用例4：静止后重新起步，计时归零")
var d4 = StandstillDetector()
for i in 0..<90 { _ = d4.ingest(acceleration: still(i), timestampMs: Int64(i * 33)) }
var after = 0
for i in 90..<150 { after = d4.ingest(acceleration: walk(i), timestampMs: Int64(i * 33)) }
check(after == 0, "起步后归零")

print("用例5：姿态旋转不影响判定（重力落在不同轴上）")
var d5 = StandstillDetector()
var rot = 0
for i in 0..<120 { rot = d5.ingest(acceleration: SIMD3(g + 0.06 * sin(Float(i)), 0.04, 0.05 * cos(Float(i))), timestampMs: Int64(i * 33)) }
check(rot >= 3_000, "重力在 x 轴时同样判定为静止")

print(failures == 0 ? "\n全部通过" : "\n有 \(failures) 项失败")
