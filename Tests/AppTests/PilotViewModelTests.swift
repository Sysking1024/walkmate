//
//  PilotViewModelTests.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-23.
//

import XCTest
import Combine
import simd
import UIKit
@testable import WalkMate

// MARK: - 测试替身 Mocks

/// 模拟相机数据流管道
final class MockCameraPipeline: CameraPipelineProtocol {
    weak var delegate: CameraPipelineDelegate?
    var currentState: CameraConnectionState = .noConnection
    var previewView: UIView? = UIView()
    var connectCalled = false
    var disconnectCalled = false
    
    func connect() {
        connectCalled = true
        currentState = .connecting
        delegate?.cameraPipeline(self, didUpdateState: .connecting)
    }
    
    func disconnect() {
        disconnectCalled = true
        currentState = .noConnection
        delegate?.cameraPipeline(self, didUpdateState: .noConnection)
    }
    
    func simulateConnected() {
        currentState = .connected
        delegate?.cameraPipeline(self, didUpdateState: .connected)
    }
    
    func simulateFailed() {
        currentState = .failed
        delegate?.cameraPipeline(self, didUpdateState: .failed)
    }
    
    func simulateDisconnected() {
        currentState = .noConnection
        delegate?.cameraPipeline(self, didUpdateState: .noConnection)
    }
}

/// 模拟空间感知计算引擎
final class MockPerceptionEngine: SpatialPerceptionEngineProtocol {
    weak var delegate: SpatialPerceptionDelegate?
    var isRunning: Bool = false
    var startCalled = false
    var stopCalled = false
    var processedFrames: [PanoramicFrame] = []
    
    var obstacleStream: AsyncStream<ObstacleData> {
        AsyncStream { continuation in continuation.finish() }
    }
    
    var routeStream: AsyncStream<PassableRouteData> {
        AsyncStream { continuation in continuation.finish() }
    }
    
    var latestObstacles: ObstacleData?
    var latestRoute: PassableRouteData?
    
    func start() {
        startCalled = true
        isRunning = true
    }
    
    func stop() {
        stopCalled = true
        isRunning = false
    }
    
    func processFrame(_ frame: PanoramicFrame) {
        processedFrames.append(frame)
    }
}

/// 模拟空间音频播放服务
final class MockSpatialAudioPlayer: SpatialAudioPlayerProtocol {
    var isRunning: Bool = false
    var startCalled = false
    var stopCalled = false
    var resetCalled = false
    var lastObstacleTarget: SIMD3<Float>?
    var lastNavigationTarget: SIMD3<Float>?
    var playRewardSoundCalled = false
    
    func start() throws {
        startCalled = true
        isRunning = true
    }
    
    func stop() {
        stopCalled = true
        isRunning = false
    }
    
    func reset() {
        resetCalled = true
        lastObstacleTarget = nil
        lastNavigationTarget = nil
    }
    
    func setObstacleTarget(position: SIMD3<Float>?) {
        lastObstacleTarget = position
    }
    
    func setNavigationTarget(position: SIMD3<Float>?) {
        lastNavigationTarget = position
    }
    
    func playRewardSound() {
        playRewardSoundCalled = true
    }
}

// MARK: - 实测视图模型单元测试套件
final class PilotViewModelTests: XCTestCase {
    
    private var pipeline: MockCameraPipeline!
    private var engine: MockPerceptionEngine!
    private var audioPlayer: MockSpatialAudioPlayer!
    private var viewModel: CameraViewModel!
    
    override func setUp() {
        super.setUp()
        pipeline = MockCameraPipeline()
        engine = MockPerceptionEngine()
        audioPlayer = MockSpatialAudioPlayer()
        viewModel = CameraViewModel(pipeline: pipeline, perceptionEngine: engine, audioPlayer: audioPlayer)
    }
    
    override func tearDown() {
        viewModel = nil
        pipeline = nil
        engine = nil
        audioPlayer = nil
        super.tearDown()
    }
    
    // MARK: - User Story 1: 全屏沉浸与双按钮连接状态机测试 (US1 / T003)
    
    /// 验证初始未连接状态与右下角感知使能状态
    func testInitialStateIsDisconnectedAndPerceptionDisabled() {
        // 初始状态必须为未连接
        XCTAssertEqual(viewModel.connectionState, .noConnection)
        // 未连接相机时，右下角开始感知按钮必须为不可点击禁用状态
        XCTAssertFalse(viewModel.isPerceptionEnabled)
    }
    
    /// 验证点击左下角按钮发起连接并流转状态机
    func testToggleConnectionFromDisconnectedStartsConnecting() {
        // 触发连接指令
        viewModel.toggleConnection()
        
        // 断言已调用 pipeline.connect 且状态转为 connecting
        XCTAssertTrue(pipeline.connectCalled)
        XCTAssertEqual(viewModel.connectionState, .connecting)
        // 正在连接过程中，右下角感知按钮仍保持禁用
        XCTAssertFalse(viewModel.isPerceptionEnabled)
    }
    
    /// 验证相机连接成功推流后激活右下角开始感知按钮
    func testConnectionSuccessEnablesPerceptionButton() {
        // 模拟 Wi-Fi Socket 连接握手完成并推流
        pipeline.simulateConnected()
        
        // 断言相机处于连接状态
        XCTAssertEqual(viewModel.connectionState, .connected)
        // 断言已加载预览图层
        XCTAssertNotNil(viewModel.previewView)
        // 断言右下角感知按钮已激活为可用状态
        XCTAssertTrue(viewModel.isPerceptionEnabled)
    }
    
    /// 验证在已连接状态下再次点击左下角按钮能够安全断开
    func testToggleConnectionWhenConnectedDisconnectsCamera() {
        // 先置为已连接
        pipeline.simulateConnected()
        XCTAssertEqual(viewModel.connectionState, .connected)
        
        // 点击左下角断开连接
        viewModel.toggleConnection()
        
        // 断言已调用 pipeline.disconnect 且状态转为未连接
        XCTAssertTrue(pipeline.disconnectCalled)
        XCTAssertEqual(viewModel.connectionState, .noConnection)
        // 断开后感知按钮恢复禁用
        XCTAssertFalse(viewModel.isPerceptionEnabled)
    }
    
    // MARK: - User Story 2: 感知与音频独立启停状态机及掉线自愈测试 (US2 / T005)
    
    /// 验证点击右下角按钮独立启动与停止大模型感知引擎
    func testTogglePerceptionStartsAndStopsEngine() {
        // 相机必须已连接
        pipeline.simulateConnected()
        XCTAssertFalse(viewModel.isPerceiving)
        XCTAssertFalse(engine.startCalled)
        
        // 第一次点击：启动感知
        viewModel.togglePerception()
        XCTAssertTrue(viewModel.isPerceiving)
        XCTAssertTrue(engine.startCalled)
        
        // 第二次点击：停止感知
        viewModel.togglePerception()
        XCTAssertFalse(viewModel.isPerceiving)
        XCTAssertTrue(engine.stopCalled)
    }
    
    /// 验证相机未连接时无法启动感知
    func testCannotTogglePerceptionWhenCameraDisconnected() {
        XCTAssertEqual(viewModel.connectionState, .noConnection)
        
        // 尝试启动感知
        viewModel.togglePerception()
        
        // 状态必须保持未开启，且不可调用引擎启动
        XCTAssertFalse(viewModel.isPerceiving)
        XCTAssertFalse(engine.startCalled)
    }
    
    /// 验证视频帧投递门禁：仅在 isPerceiving == true 时投递给模型流水线
    func testDidReceiveFrameGateOnlyProcessesWhenPerceiving() {
        pipeline.simulateConnected()
        
        let dummyBuffer = createDummyPixelBuffer()
        let dummyFrame = PanoramicFrame(
            pixelBuffer: dummyBuffer,
            timestampMs: 1000,
            orientation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            acceleration: SIMD3<Float>(0, 0, 0)
        )
        
        // 1. 感知未开启时，接收到视频帧被门禁直接拦截丢弃
        XCTAssertFalse(viewModel.isPerceiving)
        pipeline.delegate?.cameraPipeline(pipeline, didReceiveFrame: dummyFrame)
        XCTAssertEqual(engine.processedFrames.count, 0)
        
        // 2. 启动感知后，接收到视频帧正常投递给深度模型
        viewModel.togglePerception()
        XCTAssertTrue(viewModel.isPerceiving)
        pipeline.delegate?.cameraPipeline(pipeline, didReceiveFrame: dummyFrame)
        XCTAssertEqual(engine.processedFrames.count, 1)
        
        // 3. 停止感知后，后续帧再次被静默拦截
        viewModel.togglePerception()
        XCTAssertFalse(viewModel.isPerceiving)
        pipeline.delegate?.cameraPipeline(pipeline, didReceiveFrame: dummyFrame)
        XCTAssertEqual(engine.processedFrames.count, 1)
    }
    
    /// 验证相机意外掉线时自动重置感知与音频 (掉线自愈)
    func testCameraDisconnectAutomaticallyStopsPerception() {
        pipeline.simulateConnected()
        viewModel.togglePerception()
        XCTAssertTrue(viewModel.isPerceiving)
        
        // 模拟 Wi-Fi 信号丢失掉线
        pipeline.simulateDisconnected()
        
        // 感知状态必须自动重置为 false，且感知引擎被停止
        XCTAssertFalse(viewModel.isPerceiving)
        XCTAssertTrue(engine.stopCalled)
        XCTAssertFalse(viewModel.isPerceptionEnabled)
    }
    
    /// 验证相机连接报错失败时自动重置感知与音频
    func testCameraFailureAutomaticallyStopsPerception() {
        pipeline.simulateConnected()
        viewModel.togglePerception()
        XCTAssertTrue(viewModel.isPerceiving)
        
        // 模拟相机通信链路异常断开
        pipeline.simulateFailed()
        
        // 感知状态必须自动重置为 false，且感知引擎被停止
        XCTAssertFalse(viewModel.isPerceiving)
        XCTAssertTrue(engine.stopCalled)
        XCTAssertFalse(viewModel.isPerceptionEnabled)
    }
    
    /// 验证启停响应时间满足 SC-002 性能指标 (启动响应 < 200ms, 停止响应 < 50ms)
    func testPerceptionStartAndStopLatency() {
        pipeline.simulateConnected()
        
        // 1. 测量启动感知耗时
        let startTimestamp = CACurrentMediaTime()
        viewModel.startPerception()
        let startElapsedMs = (CACurrentMediaTime() - startTimestamp) * 1000.0
        XCTAssertTrue(viewModel.isPerceiving)
        XCTAssertLessThan(startElapsedMs, 200.0, "启动感知响应延迟应小于 200ms (SC-002)")
        
        // 2. 测量停止感知并静音耗时
        let stopTimestamp = CACurrentMediaTime()
        viewModel.stopPerception()
        let stopElapsedMs = (CACurrentMediaTime() - stopTimestamp) * 1000.0
        XCTAssertFalse(viewModel.isPerceiving)
        XCTAssertLessThan(stopElapsedMs, 50.0, "停止感知与静音延迟应小于 50ms (SC-002)")
    }
    
    // MARK: - 辅助私有构造器
    
    private func createDummyPixelBuffer() -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, attrs, &pixelBuffer)
        return pixelBuffer!
    }
    
    // MARK: - User Story 3: 业务层前向扇区避障与首航路点导引测试 (US3 / T007)
    
    /// 验证身侧/身后障碍物及前方 1 米外障碍物完全静默过滤 (FR-008 / SC-003)
    func testObstacleFilteringRearAndFarObstaclesMuted() {
        pipeline.simulateConnected()
        viewModel.startPerception()
        
        let obstacles = [
            // 身后 0.5 米障碍物 (azimuth = 180°, distance = 0.5m)
            makeObstacle(id: 1, position: SIMD3<Float>(0, 0, 0.5), distance: 0.5, azimuth: 180.0),
            // 右身侧 0.8 米障碍物 (azimuth = 80° > 65°, distance = 0.8m)
            makeObstacle(id: 2, position: SIMD3<Float>(0.78, 0, -0.14), distance: 0.8, azimuth: 80.0),
            // 左身侧 0.9 米障碍物 (azimuth = -75° < -65°, distance = 0.9m)
            makeObstacle(id: 3, position: SIMD3<Float>(-0.87, 0, -0.23), distance: 0.9, azimuth: -75.0),
            // 前方 2.0 米障碍物 (azimuth = 0°, distance = 2.0m > 1.0m)
            makeObstacle(id: 4, position: SIMD3<Float>(0, 0, -2.0), distance: 2.0, azimuth: 0.0)
        ]
        
        let obstacleData = ObstacleData(frameId: 1, timestampMs: 1000, obstacles: obstacles)
        viewModel.perceptionEngine(engine, didProduceObstacles: obstacleData)
        
        // 断言业务层静默过滤，音频播放器未传入任何避障目标点 (传入 nil 静音)
        XCTAssertNil(audioPlayer.lastObstacleTarget, "身侧/身后及 1 米外障碍物必须完全过滤静音")
    }
    
    /// 验证在前向 130° 扇区且 1 米范围内检出多个障碍物时，精确提取距离最近的一个送入音频引擎 (FR-008)
    func testObstacleFilteringForwardNearObstacleTriggersNearest() {
        pipeline.simulateConnected()
        viewModel.startPerception()
        
        let nearestTargetPos = SIMD3<Float>(0.2, 0, -0.5) // distance = 0.54m, azimuth ≈ 21.8° <= 65°
        let fartherTargetPos = SIMD3<Float>(0, 0, -0.9)  // distance = 0.9m, azimuth = 0° <= 65°
        let rearTargetPos = SIMD3<Float>(0, 0, 0.3)     // distance = 0.3m, azimuth = 180° (身侧外)
        
        let obstacles = [
            makeObstacle(id: 1, position: fartherTargetPos, distance: 0.9, azimuth: 0.0),
            makeObstacle(id: 2, position: nearestTargetPos, distance: 0.54, azimuth: 21.8),
            makeObstacle(id: 3, position: rearTargetPos, distance: 0.3, azimuth: 180.0)
        ]
        
        let obstacleData = ObstacleData(frameId: 2, timestampMs: 2000, obstacles: obstacles)
        viewModel.perceptionEngine(engine, didProduceObstacles: obstacleData)
        
        // 断言精确提取了前向扇区内距离最近的 nearestTargetPos
        XCTAssertNotNil(audioPlayer.lastObstacleTarget)
        XCTAssertEqual(audioPlayer.lastObstacleTarget, nearestTargetPos, "应精确筛选出前向 130° 扇区且距离最小的障碍物")
    }
    
    /// 验证从路线规划中提取第 1 个航路点三维坐标驱动脚步声 (FR-009)
    func testNavigationWaypointFirstPointExtracted() {
        pipeline.simulateConnected()
        viewModel.startPerception()
        
        let firstWaypointPos = SIMD3<Float>(0.15, 0, -1.2)
        let secondWaypointPos = SIMD3<Float>(0.4, 0, -2.5)
        
        let routeData = PassableRouteData(
            isPathAvailable: true,
            safeDepth: 3.5,
            recommendedHeading: 5.0,
            waypoints: [
                RouteWaypoint(position: firstWaypointPos, clearanceWidth: 1.2),
                RouteWaypoint(position: secondWaypointPos, clearanceWidth: 1.5)
            ]
        )
        
        viewModel.perceptionEngine(engine, didProducePassableRoute: routeData)
        
        // 断言导航目标点严格对齐 waypoints.first
        XCTAssertEqual(audioPlayer.lastNavigationTarget, firstWaypointPos, "应提取路线的第 1 个航路点设置导航声源")
    }
    
    /// 验证路线受阻（无有效航路点）时导航脚步声自动停止静音 (FR-009)
    func testBlockedRouteMutesNavigationAudio() {
        pipeline.simulateConnected()
        viewModel.startPerception()
        
        // 投递受阻路线
        viewModel.perceptionEngine(engine, didProducePassableRoute: .blocked)
        
        // 导航目标应置为 nil
        XCTAssertNil(audioPlayer.lastNavigationTarget, "无可用航路点时导航音频应静音")
    }
    
    /// 验证关键门禁：当感知停止时，迟到的异步委托回调严禁更新音频目标 (U1)
    func testPerceptionCallbacksIgnoredWhenPerceptionStopped() {
        pipeline.simulateConnected()
        // 处于停止状态
        XCTAssertFalse(viewModel.isPerceiving)
        
        // 尝试投递前向极近危险物
        let forwardDanger = makeObstacle(id: 99, position: SIMD3<Float>(0, 0, -0.5), distance: 0.5, azimuth: 0.0)
        let obstacleData = ObstacleData(frameId: 3, timestampMs: 3000, obstacles: [forwardDanger])
        viewModel.perceptionEngine(engine, didProduceObstacles: obstacleData)
        
        // 尝试投递路线
        let routeData = PassableRouteData(
            isPathAvailable: true,
            safeDepth: 2.0,
            recommendedHeading: 0,
            waypoints: [RouteWaypoint(position: SIMD3<Float>(0, 0, -1.0), clearanceWidth: 1.0)]
        )
        viewModel.perceptionEngine(engine, didProducePassableRoute: routeData)
        
        // 由于门禁拦截，音频目标保持 nil
        XCTAssertNil(audioPlayer.lastObstacleTarget, "未开启感知时障碍物回调应被丢弃")
        XCTAssertNil(audioPlayer.lastNavigationTarget, "未开启感知时航路点回调应被丢弃")
    }
    
    private func makeObstacle(
        id: Int,
        position: SIMD3<Float>,
        distance: Float,
        azimuth: Float
    ) -> ObstacleItem {
        ObstacleItem(
            id: id,
            position: position,
            distance: distance,
            azimuth: azimuth,
            elevation: 0,
            size: SIMD3<Float>(0.5, 1.0, 0.5),
            category: .groundObstacle,
            relativeVelocity: .zero,
            approachRate: 0,
            priorityScore: 0.8,
            threatLevel: .danger,
            isRearHazard: abs(azimuth) > 90
        )
    }
}


