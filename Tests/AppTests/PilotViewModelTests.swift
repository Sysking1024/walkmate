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

// MARK: - 实测视图模型单元测试套件
final class PilotViewModelTests: XCTestCase {
    
    private var pipeline: MockCameraPipeline!
    private var engine: MockPerceptionEngine!
    private var viewModel: CameraViewModel!
    
    override func setUp() {
        super.setUp()
        pipeline = MockCameraPipeline()
        engine = MockPerceptionEngine()
        viewModel = CameraViewModel(pipeline: pipeline, perceptionEngine: engine)
    }
    
    override func tearDown() {
        viewModel = nil
        pipeline = nil
        engine = nil
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
}

