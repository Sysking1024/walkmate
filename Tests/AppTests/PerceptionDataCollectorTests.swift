//
//  PerceptionDataCollectorTests.swift
//  AppTests
//
//  Created by Antigravity on 2026-09-23.
//

import XCTest
import CoreVideo
import simd
@testable import WalkMate

/// 模拟数据采集器代理回调接收者
final class MockCollectorDelegate: PerceptionDataCollectorDelegate, @unchecked Sendable {
    var stateChanges: [CollectorState] = []
    var durations: [Double] = []
    var errors: [Error] = []
    
    private let lock = NSLock()
    
    func collector(_ collector: PerceptionDataCollectorProtocol, didChangeState state: CollectorState) {
        lock.lock()
        defer { lock.unlock() }
        stateChanges.append(state)
    }
    
    func collector(_ collector: PerceptionDataCollectorProtocol, didUpdateDuration seconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        durations.append(seconds)
    }
    
    func collector(_ collector: PerceptionDataCollectorProtocol, didEncounterError error: Error) {
        lock.lock()
        defer { lock.unlock() }
        errors.append(error)
    }
}

/// 空间感知数据采集协调器专项测试套件
final class PerceptionDataCollectorTests: XCTestCase {
    
    private var tempDirectoryURL: URL!
    private var storageManager: SessionStorageManager!
    private var collector: PerceptionDataCollector!
    private var delegate: MockCollectorDelegate!
    
    override func setUp() {
        super.setUp()
        let uniqueName = "TestCollector_\(UUID().uuidString)"
        tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueName, isDirectory: true)
        storageManager = SessionStorageManager(baseDirectoryURL: tempDirectoryURL)
        collector = PerceptionDataCollector(storageManager: storageManager)
        delegate = MockCollectorDelegate()
        collector.delegate = delegate
    }
    
    override func tearDown() {
        if collector.state == .recording {
            let exp = expectation(description: "停止测试采集")
            collector.stopRecording { _ in exp.fulfill() }
            wait(for: [exp], timeout: 2.0)
        }
        collector = nil
        delegate = nil
        if let dir = tempDirectoryURL, FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }
    
    // MARK: - 辅助测试构建方法
    
    private func createDummyPixelBuffer() -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            16,
            16,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        assert(status == kCVReturnSuccess && pixelBuffer != nil)
        return pixelBuffer!
    }
    
    private func createDummyDepthMatrix(timestampMs: Int64) -> DepthMatrix {
        let count = DepthMatrix.width * DepthMatrix.height
        let values = ContiguousArray<Float>(repeating: 2.5, count: count)
        return DepthMatrix(values: values, minDepth: 0.5, maxDepth: 4.5, timestampMs: timestampMs)
    }
    
    // MARK: - 状态机流转与会话生命周期测试
    
    /// 验证状态机流转: 待命 -> 录制中 -> 正在停止 -> 待命
    func testCollectorStateMachineTransition() throws {
        XCTAssertEqual(collector.state, .idle)
        XCTAssertNil(collector.currentSessionId)
        
        try collector.startRecording()
        XCTAssertEqual(collector.state, .recording)
        XCTAssertNotNil(collector.currentSessionId)
        XCTAssertTrue(delegate.stateChanges.contains(.recording))
        
        let stopExpectation = expectation(description: "等待写盘停止完成")
        collector.stopRecording { result in
            switch result {
            case .success(let metadata):
                XCTAssertGreaterThanOrEqual(metadata.durationSeconds, 0)
                stopExpectation.fulfill()
            case .failure(let error):
                XCTFail("停止录制失败: \(error)")
            }
        }
        
        wait(for: [stopExpectation], timeout: 3.0)
        XCTAssertEqual(collector.state, .idle)
        XCTAssertNil(collector.currentSessionId)
        XCTAssertTrue(delegate.stateChanges.contains(.idle))
    }
    
    // MARK: - 遥测数据流与分级采样写盘测试
    
    /// 验证 10~30Hz 遥测数据全量流式写入 JSONL，以及 2Hz 图像快照抽样
    func testTelemetryStreamingAndVisualSubsampling() throws {
        try collector.startRecording()
        let sessionId = collector.currentSessionId!
        let sessionFolder = storageManager.sessionFolderURL(for: sessionId)
        
        let pixelBuffer = createDummyPixelBuffer()
        let quat = simd_quatf(angle: 0.1, axis: SIMD3<Float>(0, 1, 0))
        
        // 模拟 10 帧数据，时间戳每帧递增 100ms (即 10Hz，总历时 1000ms = 1秒)
        // 按照 500ms 抽样间隔 (2Hz)，应产生 2 次图像/深度快照
        for i in 0..<10 {
            let timestamp = 1727092800000 + Int64(i * 100)
            let frame = PanoramicFrame(
                pixelBuffer: pixelBuffer,
                timestampMs: timestamp,
                orientation: quat,
                acceleration: SIMD3<Float>(0, -9.8, 0)
            )
            let depth = createDummyDepthMatrix(timestampMs: timestamp)
            
            let obstacle = ObstacleItem(
                id: i,
                position: SIMD3<Float>(0.2, 0.0, -1.0),
                distance: 1.0,
                azimuth: 5.0,
                elevation: 0.0,
                size: SIMD3<Float>(0.3, 0.5, 0.3),
                category: .groundObstacle,
                relativeVelocity: SIMD3<Float>(0, 0, 0),
                approachRate: 0.0,
                priorityScore: 0.8,
                threatLevel: .warning,
                isRearHazard: false
            )
            
            let route = PassableRouteData(
                isPathAvailable: true,
                safeDepth: 3.0,
                recommendedHeading: 0.0,
                waypoints: [RouteWaypoint(position: SIMD3<Float>(0, 0, -1), clearanceWidth: 1.2)]
            )
            
            collector.recordFrame(
                frame: frame,
                depthMatrix: depth,
                groundPlane: [0, 1, 0, -1.4],
                cameraHeight: 1.4,
                rawObstacles: [obstacle],
                hazardObstacles: [obstacle],
                routeData: route,
                activeObstacleTarget: SIMD3<Float>(0.2, 0.0, -1.0),
                activeNavigationTarget: SIMD3<Float>(0, 0, -1),
                latencyMs: 12.5
            )
        }
        
        let stopExpectation = expectation(description: "等待停止并落盘")
        collector.stopRecording { result in
            switch result {
            case .success(let metadata):
                XCTAssertEqual(metadata.totalTelemetryFrames, 10, "10 帧遥测必须全部落盘")
                XCTAssertGreaterThanOrEqual(metadata.totalImageSnapshots, 2, "1 秒内按 500ms 抽样至少产生 2 帧快照")
                stopExpectation.fulfill()
            case .failure(let error):
                XCTFail("停止会话失败: \(error)")
            }
        }
        wait(for: [stopExpectation], timeout: 5.0)
        
        // 校验 telemetry.jsonl 内容合法性
        let jsonlURL = sessionFolder.appendingPathComponent("telemetry.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonlURL.path), "telemetry.jsonl 必须存在")
        
        let content = try String(contentsOf: jsonlURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertEqual(lines.count, 10, "每帧必须落盘为 JSONL 中的独立一行")
        
        // 验证第一行反序列化结果与四元数高保真
        let firstLineData = lines[0].data(using: .utf8)!
        let firstRecord = try JSONDecoder().decode(FrameTelemetryRecord.self, from: firstLineData)
        XCTAssertEqual(firstRecord.timestampMs, 1727092800000)
        XCTAssertEqual(firstRecord.frameIndex, 0)
        XCTAssertEqual(firstRecord.groundPlane, [0, 1, 0, -1.4])
        XCTAssertEqual(firstRecord.cameraHeight, 1.4)
        XCTAssertEqual(firstRecord.hazardObstacles.count, 1)
        XCTAssertEqual(firstRecord.isPassable, true)
        XCTAssertEqual(firstRecord.quaternion.x, quat.vector.x, accuracy: 1e-4)
    }
    
    // MARK: - 性能度量基准测试 (极致低延迟与零主线程卡顿)
    
    /// 验证主调用线程调用 recordFrame 的纳秒/微秒级极低耗时 (零 I/O 阻塞)
    func testRecordFrameLatencyOnCallerThread() throws {
        try collector.startRecording()
        
        let pixelBuffer = createDummyPixelBuffer()
        let frame = PanoramicFrame(
            pixelBuffer: pixelBuffer,
            timestampMs: 1000,
            orientation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            acceleration: SIMD3<Float>(0, -9.8, 0)
        )
        
        // 预热一次
        collector.recordFrame(
            frame: frame,
            depthMatrix: nil,
            groundPlane: [0, 1, 0, -1.4],
            cameraHeight: 1.4,
            rawObstacles: [],
            hazardObstacles: [],
            routeData: nil,
            activeObstacleTarget: nil,
            activeNavigationTarget: nil,
            latencyMs: 10.0
        )
        
        // 测试连续投递 100 帧的总调用耗时，平均单次必须远小于 1ms
        let start = DispatchTime.now().uptimeNanoseconds
        let testCount = 100
        for i in 0..<testCount {
            collector.recordFrame(
                frame: frame,
                depthMatrix: nil,
                groundPlane: [0, 1, 0, -1.4],
                cameraHeight: 1.4,
                rawObstacles: [],
                hazardObstacles: [],
                routeData: nil,
                activeObstacleTarget: nil,
                activeNavigationTarget: nil,
                latencyMs: 10.0
            )
        }
        let totalElapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
        let avgPerCallMs = totalElapsedMs / Double(testCount)
        
        XCTAssertLessThan(
            avgPerCallMs,
            1.0,
            "内存入队操作平均耗时必须 < 1.0ms，当前: \(avgPerCallMs)ms"
        )
        
        let exp = expectation(description: "清理停止")
        collector.stopRecording { _ in exp.fulfill() }
        wait(for: [exp], timeout: 3.0)
    }
}
