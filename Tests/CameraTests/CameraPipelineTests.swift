//
//  CameraPipelineTests.swift
//  CameraTests
//
//  Created by Antigravity on 2026-09-22.
//

import CoreVideo
import simd
import XCTest
import INSCameraSDK
@testable import WalkMate

// MARK: - Mock 播放器桥接器
final class MockStreamPlayerBridge: StreamPlayerBridgeProtocol {
    var onFrameDecoded: ((CVPixelBuffer, Int64) -> Void)?
    var onError: ((Error) -> Void)?
    var previewView: UIView? = UIView()
    var isRunning: Bool = false
    
    var startRunningCallCount = 0
    var stopRunningCallCount = 0
    
    func startRunning(videoEncode: INSVideoEncode, resolution: INSVideoResolution, completion: @escaping (Error?) -> Void) {
        startRunningCallCount += 1
        isRunning = true
        completion(nil)
    }
    
    func stopRunning(completion: ((Error?) -> Void)?) {
        stopRunningCallCount += 1
        isRunning = false
        completion?(nil)
    }
    
    // 辅助测试方法：模拟产生一帧视频数据
    func simulateFrame(timestampMs: Int64) {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            512,
            256,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        if status == kCVReturnSuccess, let buffer = pixelBuffer {
            onFrameDecoded?(buffer, timestampMs)
        }
    }
}

// MARK: - Mock 陀螺仪处理器
final class MockGyroHandler: GyroDataHandlerProtocol {
    var onGyroParsed: ((INSGyroRawItem) -> Void)?
    
    var currentOrientation: simd_quatf = simd_quatf(angle: 0.1, axis: SIMD3<Float>(0, 1, 0))
    var currentAcceleration: SIMD3<Float> = SIMD3<Float>(0.2, 9.8, -0.3)
    var currentEulerAngles: (pitch: Float, roll: Float, yaw: Float) = (5.0, -2.0, 0.0)
    
    var attitudeQueryTimestamp: Int64?
    
    func attitude(at timestampMs: Int64) -> (orientation: simd_quatf, acceleration: SIMD3<Float>) {
        attitudeQueryTimestamp = timestampMs
        return (currentOrientation, currentAcceleration)
    }
}

// MARK: - Mock 代理监听者
final class MockPipelineDelegate: CameraPipelineDelegate {
    var statesReceived: [CameraConnectionState] = []
    var framesReceived: [PanoramicFrame] = []
    var telemetryReceived: [SensorTelemetry] = []
    var errorsReceived: [Error] = []
    
    func cameraPipeline(_ pipeline: CameraPipelineProtocol, didUpdateState state: CameraConnectionState) {
        statesReceived.append(state)
    }
    
    func cameraPipeline(_ pipeline: CameraPipelineProtocol, didReceiveFrame frame: PanoramicFrame) {
        framesReceived.append(frame)
    }
    
    func cameraPipeline(_ pipeline: CameraPipelineProtocol, didUpdateTelemetry telemetry: SensorTelemetry) {
        telemetryReceived.append(telemetry)
    }
    
    func cameraPipeline(_ pipeline: CameraPipelineProtocol, didEncounterError error: Error) {
        errorsReceived.append(error)
    }
}

// MARK: - 核心测试用例
final class CameraPipelineTests: XCTestCase {
    
    private var mockBridge: MockStreamPlayerBridge!
    private var mockGyro: MockGyroHandler!
    private var pipeline: CameraPipeline!
    private var mockDelegate: MockPipelineDelegate!
    
    override func setUp() {
        super.setUp()
        mockBridge = MockStreamPlayerBridge()
        mockGyro = MockGyroHandler()
        mockDelegate = MockPipelineDelegate()
        
        // 依赖注入初始化
        pipeline = CameraPipeline(playerBridge: mockBridge, gyroHandler: mockGyro)
        pipeline.delegate = mockDelegate
    }
    
    override func tearDown() {
        pipeline = nil
        mockDelegate = nil
        mockGyro = nil
        mockBridge = nil
        super.tearDown()
    }
    
    /// 测试初始状态与默认断开
    func testInitialState() {
        XCTAssertEqual(pipeline.currentState, .noConnection, "初始状态应为未连接")
        XCTAssertNotNil(pipeline.previewView, "应能获取播放器的预览视图")
    }
    
    /// 测试帧解码回调与 IMU 时间戳匹配
    func testFrameDecodingAndIMUSynchronization() {
        let testTimestamp: Int64 = 1718000000123
        
        // 模拟解码到达一帧
        mockBridge.simulateFrame(timestampMs: testTimestamp)
        
        // 校验代理是否收到对齐帧
        XCTAssertEqual(mockDelegate.framesReceived.count, 1, "应接收到一帧全景数据帧")
        guard let frame = mockDelegate.framesReceived.first else {
            XCTFail("数据帧为空")
            return
        }
        
        // 校验时间戳与陀螺仪查询是否严格一致
        XCTAssertEqual(frame.timestampMs, testTimestamp, "数据帧时间戳应与视频帧时间戳一致")
        XCTAssertEqual(mockGyro.attitudeQueryTimestamp, testTimestamp, "陀螺仪应被请求匹配当前视频帧时间戳")
        XCTAssertEqual(frame.acceleration, mockGyro.currentAcceleration, "加速度向量应与陀螺仪输出一致")
    }
    
    /// 测试播放器异常上报
    func testPlayerErrorPropagation() {
        let expectation = expectation(description: "等待错误在主线程广播")
        
        let testError = NSError(domain: "accera.test", code: -1001, userInfo: [NSLocalizedDescriptionKey: "模拟硬件推流中断"])
        mockBridge.onError?(testError)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertEqual(self.mockDelegate.errorsReceived.count, 1, "应捕获到播放器抛出的异常")
            XCTAssertEqual((self.mockDelegate.errorsReceived.first as NSError?)?.code, -1001)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    /// 测试主动断开操作
    func testDisconnect() {
        pipeline.disconnect()
        XCTAssertEqual(pipeline.currentState, .noConnection, "调用 disconnect 后状态应为 noConnection")
        XCTAssertEqual(mockBridge.stopRunningCallCount, 1, "应调用播放器 stopRunning")
    }
}
