//
//  SpatialAudioKitTests.swift
//  ToolkitTests
//
//  Created by Antigravity on 2026-09-23.
//

import XCTest
import simd
@testable import WalkMate

// MARK: - 空间音频与几何转换工具箱单元测试
final class SpatialAudioKitTests: XCTestCase {
    
    // MARK: - 辅助方法：快速生成障碍物
    private func createObstacle(
        id: Int,
        x: Float,
        y: Float = 0.0,
        z: Float,
        width: Float = 0.4,
        depth: Float = 0.4
    ) -> ObstacleItem {
        let pos = SIMD3<Float>(x, y, z)
        let dist = simd_length(pos)
        let az = atan2(x, -z) * (180.0 / .pi)
        let el = atan2(y, sqrt(x * x + z * z)) * (180.0 / .pi)
        return ObstacleItem(
            id: id,
            position: pos,
            distance: dist,
            azimuth: az,
            elevation: el,
            size: SIMD3<Float>(width, 0.8, depth),
            category: .groundObstacle,
            relativeVelocity: SIMD3<Float>(0, 0, 0),
            approachRate: 0.0,
            priorityScore: 10.0 / max(dist, 0.3),
            threatLevel: .warning,
            isRearHazard: z > 0
        )
    }
    
    // MARK: - 测试 1: 钟表方位逆空间编码 100% 准确性与临界边界
    func testClockDirectionConversion() {
        // 1. 标准整点测试
        let p12 = SpatialAudioKit.toClockDirection(azimuth: 0.0, distance: 2.0, elevation: 0.0)
        XCTAssertEqual(p12.clockHour, 12, "0° 必须对应 12 点钟")
        
        let p1 = SpatialAudioKit.toClockDirection(azimuth: 30.0, distance: 2.0, elevation: 0.0)
        XCTAssertEqual(p1.clockHour, 1, "30° 必须对应 1 点钟")
        
        let p3 = SpatialAudioKit.toClockDirection(azimuth: 90.0, distance: 2.0, elevation: 0.0)
        XCTAssertEqual(p3.clockHour, 3, "90° 必须对应 3 点钟")
        
        let p6a = SpatialAudioKit.toClockDirection(azimuth: 180.0, distance: 2.0, elevation: 0.0)
        XCTAssertEqual(p6a.clockHour, 6, "+180° 必须对应 6 点钟")
        
        let p6b = SpatialAudioKit.toClockDirection(azimuth: -180.0, distance: 2.0, elevation: 0.0)
        XCTAssertEqual(p6b.clockHour, 6, "-180° 必须对应 6 点钟")
        
        let p9 = SpatialAudioKit.toClockDirection(azimuth: -90.0, distance: 2.0, elevation: 0.0)
        XCTAssertEqual(p9.clockHour, 9, "-90° 必须对应 9 点钟")
        
        let p11 = SpatialAudioKit.toClockDirection(azimuth: -30.0, distance: 2.0, elevation: 0.0)
        XCTAssertEqual(p11.clockHour, 11, "-30° 必须对应 11 点钟")
        
        // 2. 正前方 ±15° 严格映射为 12 点钟临界测试
        let p12_pos = SpatialAudioKit.toClockDirection(azimuth: 14.9, distance: 2.0, elevation: 0.0)
        XCTAssertEqual(p12_pos.clockHour, 12, "+14.9° 应处于 12 点钟扇区")
        
        let p12_neg = SpatialAudioKit.toClockDirection(azimuth: -14.9, distance: 2.0, elevation: 0.0)
        XCTAssertEqual(p12_neg.clockHour, 12, "-14.9° 应处于 12 点钟扇区")
        
        let p1_edge = SpatialAudioKit.toClockDirection(azimuth: 15.1, distance: 2.0, elevation: 0.0)
        XCTAssertEqual(p1_edge.clockHour, 1, "+15.1° 应进入 1 点钟扇区")
        
        // 3. 高矮层次修饰词与场景一完整文案测试
        let lowObs = SpatialAudioKit.toClockDirection(azimuth: -30.0, distance: 1.8, elevation: -16.0)
        XCTAssertEqual(lowObs.elevationLevel, "低矮地面")
        XCTAssertEqual(lowObs.readableSummary, "11点钟方向，前方1.8米，低矮地面")
        
        let eyeObs = SpatialAudioKit.toClockDirection(azimuth: 0.0, distance: 2.5, elevation: 5.0)
        XCTAssertEqual(eyeObs.elevationLevel, "平齐视线")
        
        let headObs = SpatialAudioKit.toClockDirection(azimuth: 0.0, distance: 1.2, elevation: 20.0)
        XCTAssertEqual(headObs.elevationLevel, "悬空碰头")
    }
    
    // MARK: - 测试 2: 原生 3D 空间音频声源锚点与衰减参数
    func testSpatialAudioRenderParams() {
        let position = SIMD3<Float>(0.5, 0.0, -2.0)
        let boundingSize = SIMD3<Float>(0.4, 0.4, 0.4)
        
        let params = SpatialAudioKit.toSpatialAudioRenderParams(position: position, boundingSize: boundingSize)
        
        // 验证三维坐标无损传递（右手坐标系）
        XCTAssertEqual(params.sourcePosition.x, 0.5)
        XCTAssertEqual(params.sourcePosition.y, 0.0)
        XCTAssertEqual(params.sourcePosition.z, -2.0)
        
        // 验证距离衰减系数在 [0.0, 1.0] 范围内
        XCTAssertGreaterThan(params.attenuation, 0.0)
        XCTAssertLessThanOrEqual(params.attenuation, 1.0)
        
        // 验证声源扩展角在合理度数范围内
        XCTAssertGreaterThan(params.spreadAngle, 0.0)
        XCTAssertLessThanOrEqual(params.spreadAngle, 180.0)
    }
    
    // MARK: - 测试 3: 双声道普通耳机立体声降级参数换算
    func testStereoFallbackParams() {
        // 场景三：偏角 45°，距离 1.0 米
        let params = SpatialAudioKit.toStereoFallbackParams(azimuth: 45.0, distance: 1.0)
        
        // 45° 处于右前方，pan = sin(45°) ≈ 0.707
        XCTAssertEqual(params.stereoPan, 0.707, accuracy: 0.01, "45° 偏角声相 Pan 应为 0.707 (偏右耳)")
        
        // 极左偏角 -90° 处 pan 应为 -1.0
        let leftParams = SpatialAudioKit.toStereoFallbackParams(azimuth: -90.0, distance: 2.0)
        XCTAssertEqual(leftParams.stereoPan, -1.0, accuracy: 0.01)
        
        // 验证 pan 严格限制在 [-1.0, 1.0]
        XCTAssertGreaterThanOrEqual(leftParams.stereoPan, -1.0)
        XCTAssertLessThanOrEqual(leftParams.stereoPan, 1.0)
        
        // 验证脉冲周期在 [100ms, 800ms]
        XCTAssertGreaterThanOrEqual(params.recommendedPulseIntervalMs, 100)
        XCTAssertLessThanOrEqual(params.recommendedPulseIntervalMs, 800)
        
        // 验证音调乘率在 [0.5, 2.0]
        XCTAssertGreaterThanOrEqual(params.pitchMultiplier, 0.5)
        XCTAssertLessThanOrEqual(params.pitchMultiplier, 2.0)
    }
    
    // MARK: - 测试 4: 几何净空快速碰撞校验
    func testClearanceDetection() {
        // 在正前方 1.5 米处放置一个障碍物 (x = 0, z = -1.5, 宽 0.4m)
        let block = createObstacle(id: 101, x: 0.0, z: -1.5, width: 0.4, depth: 0.4)
        
        // 1. 正前方 (heading = 0°) 探测：应发生碰撞
        let resultBlocked = SpatialAudioKit.checkClearance(heading: 0.0, userWidth: 0.6, depth: 2.0, against: [block])
        XCTAssertFalse(resultBlocked.isClear, "正前方存在障碍物时通道必须判定为不畅通")
        XCTAssertEqual(resultBlocked.conflictingObstacleId, 101)
        XCTAssertEqual(resultBlocked.nearestObstacleDistance, 1.5, accuracy: 0.25)
        
        // 2. 右侧偏航 45° (heading = 45°) 探测：应畅通无阻
        let resultClear = SpatialAudioKit.checkClearance(heading: 45.0, userWidth: 0.6, depth: 2.0, against: [block])
        XCTAssertTrue(resultClear.isClear, "向空旷方向探测通道必须判定为畅通")
        XCTAssertNil(resultClear.conflictingObstacleId)
        XCTAssertEqual(resultClear.nearestObstacleDistance, 2.0, accuracy: 0.01)
    }
    
    // MARK: - 测试 5: 工具箱纯函数微秒级高性能验证 (<= 0.05ms)
    func testToolkitPerformanceMicroseconds() {
        let block = createObstacle(id: 1, x: 0.2, z: -1.8)
        let obstacles = [block]
        
        let iterations = 1000
        let startTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            _ = SpatialAudioKit.toClockDirection(azimuth: -25.0, distance: 1.5, elevation: -5.0)
            _ = SpatialAudioKit.toSpatialAudioRenderParams(position: SIMD3<Float>(0.2, 0, -1.8), boundingSize: SIMD3<Float>(0.4, 0.4, 0.4))
            _ = SpatialAudioKit.toStereoFallbackParams(azimuth: -25.0, distance: 1.5)
            _ = SpatialAudioKit.checkClearance(heading: 0.0, userWidth: 0.6, depth: 2.0, against: obstacles)
        }
        let totalElapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        let avgMsPerSet = totalElapsedMs / Double(iterations)
        
        // 4 个纯函数合计单次耗时必须 <= 0.05ms (50 微秒)
        XCTAssertLessThanOrEqual(avgMsPerSet, 0.05, "工具箱 4 个方法联合耗时超出 0.05ms 预算: \(avgMsPerSet)ms")
    }
}
