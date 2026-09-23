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
}
