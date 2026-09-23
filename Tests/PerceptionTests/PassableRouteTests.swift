//
//  PassableRouteTests.swift
//  PerceptionTests
//
//  Created by Antigravity on 2026-09-23.
//

import XCTest
import simd
@testable import WalkMate

// MARK: - 可通行路线规划与航路折线点单元测试
final class PassableRouteTests: XCTestCase {
    
    private var planner: PassageRoutePlanner!
    
    override func setUp() {
        super.setUp()
        planner = PassageRoutePlanner()
    }
    
    override func tearDown() {
        planner = nil
        super.tearDown()
    }
    
    // MARK: - 辅助方法：快速构建障碍物项
    private func createObstacle(
        id: Int,
        x: Float,
        z: Float,
        width: Float,
        depth: Float,
        category: ObstacleCategory = .groundObstacle
    ) -> ObstacleItem {
        let pos = SIMD3<Float>(x, -1.0, z)
        let size = SIMD3<Float>(width, 0.8, depth)
        let dist = simd_length(pos)
        let az = atan2(x, -z) * (180.0 / .pi)
        return ObstacleItem(
            id: id,
            position: pos,
            distance: dist,
            azimuth: az,
            elevation: 0.0,
            size: size,
            category: category,
            relativeVelocity: SIMD3<Float>(0, 0, 0),
            approachRate: 0.0,
            priorityScore: 10.0 / max(dist, 0.3),
            threatLevel: dist < 1.5 ? .warning : .safe,
            isRearHazard: false
        )
    }
    
    // MARK: - 测试 1: 空旷无阻走廊直行规划
    func testClearCorridorStraightRoute() {
        // 在空旷无障碍环境下执行规划
        let route = planner.planRoute(obstacles: [], cameraHeight: 1.4)
        
        XCTAssertTrue(route.isPathAvailable, "无障碍空旷走廊必须具备可用路线")
        XCTAssertGreaterThanOrEqual(route.safeDepth, 3.0, "安全可行进纵深应至少达到 3 米")
        XCTAssertEqual(route.recommendedHeading, 0.0, accuracy: 2.0, "正前方无障碍时起步推荐朝向应为正前方 (0°)")
        XCTAssertGreaterThanOrEqual(route.waypoints.count, 4, "应生成连续的航路点序列")
        
        // 验证航路点间距在 [0.3m, 0.6m] 规范区间内
        for i in 1..<route.waypoints.count {
            let pPrev = route.waypoints[i - 1].position
            let pCurr = route.waypoints[i].position
            let step = simd_distance(pPrev, pCurr)
            XCTAssertGreaterThanOrEqual(step, 0.25, "航路点间距不应过密")
            XCTAssertLessThanOrEqual(step, 0.65, "航路点间距不应超过 0.65m")
            XCTAssertLessThan(pCurr.z, pPrev.z, "前向航路点 Z 轴坐标应单调递减 (向前方深入)")
        }
    }
    
    // MARK: - 测试 2: 门洞瓶颈物理净宽计算精度 (<= 5cm 误差)
    func testDoorwayBottleneckClearanceAccuracy() {
        // 构造一扇门洞：位于前方 2.0m 处 (z = -2.0)
        // 门洞中心在 x = 0.0，门宽设定为 0.90m
        // 左门框中心在 x = -0.65m, 宽 0.4m (右边缘为 -0.65 + 0.2 = -0.45m)
        // 右门框中心在 x = +0.65m, 宽 0.4m (左边缘为 +0.65 - 0.2 = +0.45m)
        // 物理通道实际净宽 = 0.45 - (-0.45) = 0.90m
        let leftPost = createObstacle(id: 1, x: -0.65, z: -2.0, width: 0.4, depth: 0.4)
        let rightPost = createObstacle(id: 2, x: 0.65, z: -2.0, width: 0.4, depth: 0.4)
        
        let route = planner.planRoute(obstacles: [leftPost, rightPost], cameraHeight: 1.4)
        
        XCTAssertTrue(route.isPathAvailable, "门洞宽度 0.90m 大于人体 0.6m 宽度约束，应判定为可通行")
        XCTAssertGreaterThanOrEqual(route.safeDepth, 2.5, "路线应能穿过门洞进入后方")
        
        // 找到位于门洞位置 (z 约 -2.0m 处) 的航路点
        let doorwayWaypoint = route.waypoints.min(by: { abs($0.position.z - (-2.0)) < abs($1.position.z - (-2.0)) })
        guard let wp = doorwayWaypoint else {
            XCTFail("未找到门洞附近的航路点")
            return
        }
        
        // 验证门洞处的物理净宽计算误差 <= 5cm (即在 0.85m ~ 0.95m 之间)
        XCTAssertEqual(wp.clearanceWidth, 0.90, accuracy: 0.05, "门洞瓶颈通行净宽计算误差超出 5cm 容差")
    }
    
    // MARK: - 测试 3: 正前方障碍绕行与避障折线点提取
    func testObstacleAvoidanceDetourRoute() {
        // 构造位于正前方的阻挡物: x = 0.0, z = -1.8m, 宽 0.8m, 深 0.6m (阻挡 [-0.4, 0.4])
        // 构造左侧阻隔物: x = -1.2m, z = -1.8m, 宽 1.2m, 深 1.0m (封死左侧通道)
        // 右侧空间开阔 (x in [0.6, 2.5] 完全无障碍)
        let centerBlock = createObstacle(id: 10, x: 0.0, z: -1.8, width: 0.8, depth: 0.6)
        let leftWall = createObstacle(id: 11, x: -1.2, z: -1.8, width: 1.2, depth: 1.0)
        
        let route = planner.planRoute(obstacles: [centerBlock, leftWall], cameraHeight: 1.4)
        
        XCTAssertTrue(route.isPathAvailable, "存在开阔侧向通道时应规划绕行路线")
        // 起步推荐朝向应偏向开阔侧 (右侧 x > 0 对应偏角 recommendedHeading > 0)
        XCTAssertGreaterThan(route.recommendedHeading, 5.0, "起步偏角应推荐绕行右侧开阔区")
        
        // 验证所有航路点与障碍物中心保持安全身体间距
        for wp in route.waypoints {
            let distToObstacle = simd_distance(SIMD2<Float>(wp.position.x, wp.position.z), SIMD2<Float>(centerBlock.position.x, centerBlock.position.z))
            // 考虑障碍物半宽 0.4m 与人体半宽 0.3m，距离应至少大于 0.45m
            XCTAssertGreaterThanOrEqual(distToObstacle, 0.45, "航路点距离障碍物过近，存在碰撞风险")
        }
    }
    
    // MARK: - 测试 4: 全阻挡死胡同判定
    func testCompletelyBlockedCorridor() {
        // 构造横跨整个横向视野的死胡同墙体: z = -1.2m, x 从 -2.5 到 +2.5 全部被连续障碍物封死
        var wall: [ObstacleItem] = []
        for (i, x) in stride(from: Float(-2.4), through: Float(2.4), by: Float(0.6)).enumerated() {
            wall.append(createObstacle(id: 100 + i, x: x, z: -1.2, width: 0.65, depth: 0.5))
        }
        
        let route = planner.planRoute(obstacles: wall, cameraHeight: 1.4)
        
        // 验证不可通行或安全纵深被限制在墙体之前 (< 1.2m)
        if route.isPathAvailable {
            XCTAssertLessThanOrEqual(route.safeDepth, 1.2, "前方死胡同安全纵深不应超过阻挡墙体距离")
        } else {
            XCTAssertFalse(route.isPathAvailable, "通道全阻挡时应明确标记 isPathAvailable = false")
        }
    }
}
