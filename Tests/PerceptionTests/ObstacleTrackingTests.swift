//
//  ObstacleTrackingTests.swift
//  PerceptionTests
//
//  Created by Antigravity on 2026-09-23.
//

import XCTest
import simd
@testable import WalkMate

// MARK: - 360° 障碍物检测与跨帧跟踪单元测试
final class ObstacleTrackingTests: XCTestCase {
    
    private var detector: ObstacleDetector!
    private var tracker: ObstacleTracker!
    
    override func setUp() {
        super.setUp()
        detector = ObstacleDetector()
        tracker = ObstacleTracker()
    }
    
    override func tearDown() {
        detector = nil
        tracker = nil
        super.tearDown()
    }
    
    // MARK: - 辅助方法：生成合成点云簇
    private func createCluster(
        center: SIMD3<Float>,
        size: SIMD3<Float>,
        pointCount: Int = 30
    ) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        let half = size / 2.0
        for _ in 0..<pointCount {
            let rx = Float.random(in: -half.x...half.x)
            let ry = Float.random(in: -half.y...half.y)
            let rz = Float.random(in: -half.z...half.z)
            points.append(center + SIMD3<Float>(rx, ry, rz))
        }
        return points
    }
    
    // MARK: - 测试 1: 基于高度阈值的高程分类 (地面、悬挂、跌落)
    func testObstacleClassificationByCategoryAndHeight() {
        let cameraHeight: Float = 1.4 // 相机离地 1.4 米，地面位于 y = -1.4
        
        // 1. 地面障碍物: 离地 0.3 米 (y = -1.1, y_rel = 0.3m, 在 [0.08, 1.4] 之间)
        let groundCluster = createCluster(center: SIMD3<Float>(0.0, -1.1, -2.0), size: SIMD3<Float>(0.4, 0.4, 0.4))
        
        // 2. 悬空碰头危险: 离地 1.8 米 (y = 0.4, y_rel = 1.8m, > 1.4m)
        let hangingCluster = createCluster(center: SIMD3<Float>(1.5, 0.4, -2.5), size: SIMD3<Float>(0.5, 0.3, 0.5))
        
        // 3. 地面下沉跌落危险: 离地 -0.3 米台阶 (y = -1.7, y_rel = -0.3m, < -0.15m)
        let dropOffCluster = createCluster(center: SIMD3<Float>(-1.5, -1.7, -1.8), size: SIMD3<Float>(0.6, 0.3, 0.6))
        
        let allPoints = groundCluster + hangingCluster + dropOffCluster
        let obstacles = detector.detectObstacles(from: allPoints, cameraHeight: cameraHeight)
        
        XCTAssertGreaterThanOrEqual(obstacles.count, 3, "应至少检出 3 个障碍物聚类簇")
        
        let hasGround = obstacles.contains { $0.category == .groundObstacle }
        let hasHanging = obstacles.contains { $0.category == .hangingHazard }
        let hasDropOff = obstacles.contains { $0.category == .dropOffHazard }
        
        XCTAssertTrue(hasGround, "必须正确检出地面障碍物 (.groundObstacle)")
        XCTAssertTrue(hasHanging, "必须正确检出悬挂危险 (.hangingHazard)")
        XCTAssertTrue(hasDropOff, "必须正确检出下沉跌落危险 (.dropOffHazard)")
    }
    
    // MARK: - 测试 2: AABB 三维包围盒与极坐标换算精度
    func testAABBSizeAndCoordinateCalculation() {
        let cameraHeight: Float = 1.4
        // 构造一个位于正前方 2.0 米处的地面箱子: x in [-0.2, 0.2], y in [-1.3, -0.9], z in [-2.2, -1.8]
        // 预期尺寸: 宽 0.4m, 高 0.4m, 深 0.4m, 中心点 (0.0, -1.1, -2.0)
        let cluster = createCluster(center: SIMD3<Float>(0.0, -1.1, -2.0), size: SIMD3<Float>(0.4, 0.4, 0.4), pointCount: 50)
        let obstacles = detector.detectObstacles(from: cluster, cameraHeight: cameraHeight)
        
        guard let obs = obstacles.first else {
            XCTFail("未检出障碍物")
            return
        }
        
        // 验证 AABB 尺寸
        XCTAssertEqual(obs.size.x, 0.4, accuracy: 0.1, "包围盒宽度误差超出预期")
        XCTAssertEqual(obs.size.y, 0.4, accuracy: 0.1, "包围盒高度误差超出预期")
        XCTAssertEqual(obs.size.z, 0.4, accuracy: 0.1, "包围盒深度误差超出预期")
        
        // 验证中心坐标与极坐标
        XCTAssertEqual(obs.position.x, 0.0, accuracy: 0.15)
        XCTAssertEqual(obs.position.z, -2.0, accuracy: 0.15)
        XCTAssertEqual(obs.azimuth, 0.0, accuracy: 5.0, "正前方偏转角应接近 0 度")
        XCTAssertFalse(obs.isRearHazard, "前向障碍物不应标记为后方危险")
    }
    
    // MARK: - 测试 3: 超近距离盲区兜底与威胁等级
    func testBlindZoneDetectionThreatLevel() {
        let cameraHeight: Float = 1.4
        // 构造贴近相机的危险障碍物 (< 0.3 米)
        let blindZoneCluster = createCluster(center: SIMD3<Float>(0.0, -0.1, -0.2), size: SIMD3<Float>(0.1, 0.1, 0.1), pointCount: 20)
        let obstacles = detector.detectObstacles(from: blindZoneCluster, cameraHeight: cameraHeight)
        
        guard let obs = obstacles.first else {
            XCTFail("盲区障碍物未检出")
            return
        }
        
        XCTAssertEqual(obs.distance, 0.3, accuracy: 0.001, "盲区距离应统一转换为 0.3 米极近距离")
        XCTAssertEqual(simd_length(obs.position), 0.3, accuracy: 0.001, "盲区障碍物坐标应统一换算至 0.3 米球面")
        XCTAssertEqual(obs.threatLevel, .danger, "贴身极近障碍物必须赋予 danger 威胁等级")
    }
    
    // MARK: - 测试 4: 连续 10 帧平滑位移下的 Tracking ID 稳定性 (>= 90%)
    func testTrackingIDStabilityAcrossFrames() {
        let cameraHeight: Float = 1.4
        var previousId: Int?
        var idMatchCount = 0
        let totalFrames = 10
        
        for frame in 0..<totalFrames {
            // 物体在正前方缓缓移动: z 从 -3.0m 移动到 -2.1m (每次 0.1m)
            let zPos = -3.0 + Float(frame) * 0.1
            let cluster = createCluster(center: SIMD3<Float>(0.0, -1.0, zPos), size: SIMD3<Float>(0.3, 0.3, 0.3), pointCount: 25)
            let detected = detector.detectObstacles(from: cluster, cameraHeight: cameraHeight)
            let tracked = tracker.track(obstacles: detected, timestampMs: Int64(frame * 100))
            
            guard let current = tracked.first else {
                XCTFail("第 \(frame) 帧丢失跟踪目标")
                continue
            }
            
            if let prev = previousId {
                if current.id == prev {
                    idMatchCount += 1
                }
            } else {
                previousId = current.id
            }
        }
        
        let stabilityRatio = Double(idMatchCount) / Double(totalFrames - 1)
        XCTAssertGreaterThanOrEqual(stabilityRatio, 0.9, "跨帧 ID 稳定性应达到 90% 以上，实测: \(stabilityRatio * 100)%")
    }
    
    // MARK: - 测试 5: 短暂 5 帧遮挡下的 ID 保持与恢复 (Occlusion & Re-identification)
    func testOcclusionCacheIDRetention() {
        let cameraHeight: Float = 1.4
        let cluster = createCluster(center: SIMD3<Float>(1.0, -1.0, -2.0), size: SIMD3<Float>(0.3, 0.3, 0.3), pointCount: 25)
        
        // 1. 第 1 帧建立追踪
        let detected1 = detector.detectObstacles(from: cluster, cameraHeight: cameraHeight)
        let tracked1 = tracker.track(obstacles: detected1, timestampMs: 0)
        guard let originalId = tracked1.first?.id else {
            XCTFail("初始追踪失败")
            return
        }
        
        // 2. 连续 3 帧目标消失 (被遮挡)
        for i in 1...3 {
            let emptyTracked = tracker.track(obstacles: [], timestampMs: Int64(i * 100))
            XCTAssertTrue(emptyTracked.isEmpty, "遮挡期间不输出已消失目标")
        }
        
        // 3. 第 5 帧目标在附近重新出现 (微小位移)
        let reappearCluster = createCluster(center: SIMD3<Float>(1.05, -1.0, -1.95), size: SIMD3<Float>(0.3, 0.3, 0.3), pointCount: 25)
        let detected5 = detector.detectObstacles(from: reappearCluster, cameraHeight: cameraHeight)
        let tracked5 = tracker.track(obstacles: detected5, timestampMs: 500)
        
        guard let recoveredId = tracked5.first?.id else {
            XCTFail("目标重新出现后未检出")
            return
        }
        
        XCTAssertEqual(recoveredId, originalId, "在 5 帧遮挡容差内重新出现的目标应继承原有 Tracking ID")
        
        // 4. 若遮挡超过 5 帧 (例如跳过 6 帧)，缓存失效，新出现的物体应分配新 ID
        for i in 6...12 {
            _ = tracker.track(obstacles: [], timestampMs: Int64(i * 100))
        }
        let lateCluster = createCluster(center: SIMD3<Float>(1.05, -1.0, -1.95), size: SIMD3<Float>(0.3, 0.3, 0.3), pointCount: 25)
        let detectedLate = detector.detectObstacles(from: lateCluster, cameraHeight: cameraHeight)
        let trackedLate = tracker.track(obstacles: detectedLate, timestampMs: 1300)
        
        XCTAssertNotEqual(trackedLate.first?.id, originalId, "超过 5 帧遮挡后应视为新目标，重新分配 ID")
    }
    
    // MARK: - 测试 6: 迎面快速逼近动态实体升级 (.dynamicEntity) 与相对接近速率
    func testDynamicEntityClassificationAndApproachRate() {
        let cameraHeight: Float = 1.4
        
        // 1. 第 1 帧: 目标位于正前方 4.0 米 (t = 0ms)
        let cluster1 = createCluster(center: SIMD3<Float>(0.0, -0.5, -4.0), size: SIMD3<Float>(0.4, 1.2, 0.4), pointCount: 30)
        let d1 = detector.detectObstacles(from: cluster1, cameraHeight: cameraHeight)
        _ = tracker.track(obstacles: d1, timestampMs: 0)
        
        // 2. 第 2 帧: 目标在 200ms 内快速逼近到 3.7 米 (位移 0.3m, 速度 (4.0 - 3.7) / 0.2s = 1.5 m/s > 0.4 m/s)
        let cluster2 = createCluster(center: SIMD3<Float>(0.0, -0.5, -3.7), size: SIMD3<Float>(0.4, 1.2, 0.4), pointCount: 30)
        let d2 = detector.detectObstacles(from: cluster2, cameraHeight: cameraHeight)
        let tracked2 = tracker.track(obstacles: d2, timestampMs: 200)
        
        guard let dynamicTarget = tracked2.first else {
            XCTFail("第 2 帧未检出目标")
            return
        }
        
        // 验证接近速率为正值且在合理区间 (~1.2 m/s)
        XCTAssertGreaterThan(dynamicTarget.approachRate, 0.4, "相对接近速率应大于 0.4m/s，实测: \(dynamicTarget.approachRate)")
        // 验证分类升级为 dynamicEntity
        XCTAssertEqual(dynamicTarget.category, .dynamicEntity, "高速迎面逼近目标应升级分类为 .dynamicEntity")
        // 验证威胁级别升级
        XCTAssertEqual(dynamicTarget.threatLevel, .danger, "高速逼近目标威胁级别应提升至 danger")
    }
    
    // MARK: - 测试 7: 偏航角与后方危险标志 (isRearHazard)
    func testRearHazardFlag() {
        let cameraHeight: Float = 1.4
        // 构造位于使用者后方的障碍物 (+Z = 2.0m)
        let rearCluster = createCluster(center: SIMD3<Float>(0.0, -1.0, 2.0), size: SIMD3<Float>(0.3, 0.3, 0.3), pointCount: 20)
        let obstacles = detector.detectObstacles(from: rearCluster, cameraHeight: cameraHeight)
        
        guard let obs = obstacles.first else {
            XCTFail("后方障碍物未检出")
            return
        }
        
        XCTAssertTrue(obs.isRearHazard, "+Z 轴后方障碍物必须标记 isRearHazard = true")
        XCTAssertEqual(abs(obs.azimuth), 180.0, accuracy: 10.0, "正后方方位角应接近 180 度")
    }
}
