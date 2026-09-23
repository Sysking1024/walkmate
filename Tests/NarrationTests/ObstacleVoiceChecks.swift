// 避障语音文案检查。运行：
//   cat Tests/NarrationTests/Stubs.swift WalkMate/Models/TelemetryModels.swift WalkMate/Models/PerceptionModels.swift WalkMate/Core/Audio/ObstacleVoiceAnnouncer.swift Tests/NarrationTests/ObstacleVoiceChecks.swift | xcrun swift -
var failures = 0
func item(_ azimuth: Float, _ distance: Float) -> ObstacleItem {
    ObstacleItem(id: Int(azimuth * 10 + distance), position: SIMD3(0, 0, -distance), distance: distance, azimuth: azimuth, elevation: 0,
                 size: SIMD3(0.3, 1, 0.3), category: .groundObstacle, relativeVelocity: SIMD3(repeating: 0),
                 approachRate: 0, priorityScore: 0, threatLevel: .warning, isRearHazard: false)
}
func check(_ items: [ObstacleItem], _ expected: String?) {
    let data = ObstacleData(frameId: 0, timestampMs: 0, obstacles: items)
    let got = ObstacleVoiceAnnouncer.phrase(for: data)?.text
    if got != expected { failures += 1; print("✗ 得到 \(String(describing: got))，期望 \(String(describing: expected))") }
    else { print("✓ \(String(describing: got))") }
}
check([item(0, 0.9)], "正前方1米有障碍")
check([item(-35, 0.4)], "左前方半米有障碍")
check([item(50, 1.6)], "右前方1.5米有障碍")
// 左手边 70° 在前向 130° 扇区之外，不报；报扇区内更远的那个
check([item(-70, 1.2), item(10, 1.9)], "正前方2米有障碍")
check([item(-62, 1.2)], "左手边1米有障碍")
check([item(0, 2.6)], nil)
check([item(120, 0.5)], nil)
check([], nil)
// 节流：同一句 4 秒内不重复，障碍消失后报畅通
MainActor.assumeIsolated {
    let announcer = ObstacleVoiceAnnouncer()
    announcer.handle(ObstacleData(frameId: 0, timestampMs: 0, obstacles: [item(0, 0.9)]))
    announcer.handle(ObstacleData(frameId: 1, timestampMs: 0, obstacles: [item(0, 0.9)]))
}
print(failures == 0 ? "全部通过" : "\(failures) 项失败")
