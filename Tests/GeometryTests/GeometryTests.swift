//
//  GeometryTests.swift
//  GeometryTests
//
//  Created by Antigravity on 2026-09-23.
//

import simd
import XCTest
@testable import WalkMate

// MARK: - 几何反投影与地面拟合单元测试套件
final class GeometryTests: XCTestCase {
    
    private var projector: SphericalProjector!
    private var aligner: GravityAligner!
    private var groundEstimator: GroundPlaneEstimator!
    
    override func setUp() {
        super.setUp()
        projector = SphericalProjector()
        aligner = GravityAligner()
        groundEstimator = GroundPlaneEstimator()
    }
    
    override func tearDown() {
        projector = nil
        aligner = nil
        groundEstimator = nil
        super.tearDown()
    }
    
    // MARK: - 测试 1: 预计算 1.57MB 方向向量表 LUT 与右手坐标系对齐
    func testDirectionLUTCoordinateAlignment() {
        let lut = projector.directionLUT
        XCTAssertEqual(lut.count, DepthMatrix.width * DepthMatrix.height)
        
        let width = DepthMatrix.width   // 512
        let height = DepthMatrix.height // 256
        
        // 1. 正前方中心点 (u = 0.5, v = 0.5) 对应的索引为 y = 128, x = 256
        let centerIndex = 128 * width + 256
        let centerDir = lut[centerIndex]
        
        // 正前方应该严格为 -Z 方向 (x ≈ 0, y ≈ 0, z ≈ -1)
        XCTAssertEqual(centerDir.x, 0.0, accuracy: 0.05, "正前方 X 轴应接近 0")
        XCTAssertEqual(centerDir.y, 0.0, accuracy: 0.05, "正前方 Y 轴应接近 0")
        XCTAssertEqual(centerDir.z, -1.0, accuracy: 0.05, "正前方 Z 轴应为 -1.0")
        
        // 2. 右侧点 (u = 0.75, v = 0.5) -> x = 384, y = 128
        let rightIndex = 128 * width + 384
        let rightDir = lut[rightIndex]
        XCTAssertGreaterThan(rightDir.x, 0.8, "右侧方向 X 轴应大于 0")
        XCTAssertEqual(rightDir.z, 0.0, accuracy: 0.1, "右侧方向 Z 轴应接近 0")
        
        // 3. 左侧点 (u = 0.25, v = 0.5) -> x = 128, y = 128
        let leftIndex = 128 * width + 128
        let leftDir = lut[leftIndex]
        XCTAssertLessThan(leftDir.x, -0.8, "左侧方向 X 轴应小于 0")
        XCTAssertEqual(leftDir.z, 0.0, accuracy: 0.1, "左侧方向 Z 轴应接近 0")
        
        // 4. 正上方天顶点 (v = 0) -> y = 0, x = 256
        let topIndex = 0 * width + 256
        let topDir = lut[topIndex]
        XCTAssertGreaterThan(topDir.y, 0.9, "天顶方向 Y 轴应为正（向上）")
        
        // 5. 正下方地面点 (v = 1.0) -> y = 255, x = 256
        let bottomIndex = 255 * width + 256
        let bottomDir = lut[bottomIndex]
        XCTAssertLessThan(bottomDir.y, -0.9, "地面方向 Y 轴应为负（向下）")
    }
    
    // MARK: - 测试 2: vDSP 毫秒级反投影性能与点云生成
    func testFastBackprojectionPerformance() {
        let totalPoints = DepthMatrix.width * DepthMatrix.height
        let testDepths = ContiguousArray<Float>(repeating: 2.0, count: totalPoints)
        
        let depthMatrix = DepthMatrix(
            values: testDepths,
            minDepth: 2.0,
            maxDepth: 2.0,
            timestampMs: 1000
        )
        
        // 1. 预热运行排除冷启动缺页与首次加载开销
        _ = projector.project(depthMatrix: depthMatrix)
        
        // 2. 测量稳态反投影耗时
        let start = CFAbsoluteTimeGetCurrent()
        let pointCloud = projector.project(depthMatrix: depthMatrix)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        
        XCTAssertEqual(pointCloud.count, totalPoints)
        // 验证 13 万个点稳态反投影耗时满足 8ms 预算 (Debug 无优化模式下通常约为 3~5ms，Release 模式下 < 1ms)
        XCTAssertLessThanOrEqual(elapsedMs, 8.0, "反投影单帧计算耗时超出容差阈值: \(elapsedMs)ms")
        
        // 检查中心点距离是否为 2.0 米
        let centerPoint = pointCloud[128 * DepthMatrix.width + 256]
        let distance = simd_length(centerPoint)
        XCTAssertEqual(distance, 2.0, accuracy: 0.01)
    }
    
    // MARK: - 测试 3: IMU 重力姿态点云对齐
    func testGravityAlignment() {
        // 假设相机向下倾斜 30 度 (绕 X 轴旋转 30 度)
        let pitchAngle: Float = 30.0 * (.pi / 180.0)
        let tiltQuat = simd_quatf(angle: pitchAngle, axis: SIMD3<Float>(1, 0, 0))
        
        // 原始点原本在水平地面上 (y = -1.4m, z = -2.0m)
        let originalPoint = SIMD3<Float>(0, -1.4, -2.0)
        let tiltedPoint = tiltQuat.act(originalPoint)
        
        // 输入该姿态与倾斜后的点进行重力恢复校准
        let alignedPoints = aligner.align(points: [tiltedPoint], orientation: tiltQuat)
        
        XCTAssertEqual(alignedPoints.count, 1)
        let recovered = alignedPoints[0]
        XCTAssertEqual(recovered.x, originalPoint.x, accuracy: 0.01)
        XCTAssertEqual(recovered.y, originalPoint.y, accuracy: 0.01)
        XCTAssertEqual(recovered.z, originalPoint.z, accuracy: 0.01)
    }
    
    // MARK: - 测试 4: 动态 RANSAC 地面拟合与相机高度解算
    func testGroundPlaneRANSACFitting() {
        var testPoints: [SIMD3<Float>] = []
        let trueGroundHeight: Float = 1.4 // 相机离地高度 1.4 米，即地面处于 y = -1.4
        
        // 1. 生成 1000 个地面点 (y ≈ -1.4m，带 ±2cm 高斯/随机微小噪点)
        for i in 0..<1000 {
            let x = Float.random(in: -3.0...3.0)
            let z = Float.random(in: -5.0...(-0.5))
            let noise = Float.random(in: -0.02...0.02)
            testPoints.append(SIMD3<Float>(x, -trueGroundHeight + noise, z))
        }
        
        // 2. 生成 200 个上方障碍物点 (箱子 y = -1.0m，碰头物 y = 0.5m)
        for _ in 0..<200 {
            let x = Float.random(in: -1.0...1.0)
            let y = Float.random(in: -1.0...0.5)
            let z = Float.random(in: -3.0...(-1.0))
            testPoints.append(SIMD3<Float>(x, y, z))
        }
        
        // 3. 执行动态 RANSAC 拟合
        let result = groundEstimator.estimateGround(from: testPoints)
        
        // 4. 验证解算出的相机离地高度误差小于 5cm (SC-005)
        XCTAssertEqual(result.cameraHeight, trueGroundHeight, accuracy: 0.05, "地面拟合相机高度误差超过 5 厘米")
        
        // 5. 验证法向量严格向上 (0, 1, 0)
        XCTAssertEqual(result.groundPlane.y, 1.0, accuracy: 0.05, "地面法向量 Y 分量应接近 1.0")
        
        // 6. 验证已有效剥离地面，非地面点集中包含上述障碍物点
        XCTAssertGreaterThan(result.nonGroundPoints.count, 0)
        XCTAssertLessThanOrEqual(result.nonGroundPoints.count, 250)
    }
}
