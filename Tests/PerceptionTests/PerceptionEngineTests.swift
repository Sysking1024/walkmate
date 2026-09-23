//
//  PerceptionEngineTests.swift
//  PerceptionTests
//
//  Created by Antigravity on 2026-09-23.
//

import CoreVideo
import simd
import UIKit
import XCTest
@testable import WalkMate

// MARK: - 空间感知引擎全链路集成测试套件
final class PerceptionEngineTests: XCTestCase, SpatialPerceptionDelegate {
    
    private var engine: SpatialPerceptionEngine!
    private var obstacleExpectation: XCTestExpectation?
    private var routeExpectation: XCTestExpectation?
    private var receivedObstacles: ObstacleData?
    private var receivedRoute: PassableRouteData?
    private var receivedError: Error?
    
    override func setUp() {
        super.setUp()
        do {
            engine = try SpatialPerceptionEngine()
            engine.delegate = self
        } catch {
            XCTFail("SpatialPerceptionEngine 初始化失败: \(error.localizedDescription)")
        }
    }
    
    override func tearDown() {
        engine?.stop()
        engine = nil
        obstacleExpectation = nil
        routeExpectation = nil
        receivedObstacles = nil
        receivedRoute = nil
        receivedError = nil
        super.tearDown()
    }
    
    // MARK: - 代理回调实现
    
    func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didProduceObstacles data: ObstacleData) {
        receivedObstacles = data
        obstacleExpectation?.fulfill()
    }
    
    func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didProducePassableRoute data: PassableRouteData) {
        receivedRoute = data
        routeExpectation?.fulfill()
    }
    
    func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didEncounterError error: Error) {
        receivedError = error
    }
    
    // MARK: - 辅助方法：读取真实 pano_indoor.jpg 或生成合成全景帧
    private func createTestPanoramicFrame(timestampMs: Int64 = 1000) -> PanoramicFrame {
        let panoPath = "/Users/wuyiming/Code/walkmate/tmp/pano_indoor.jpg"
        if let image = UIImage(contentsOfFile: panoPath), let pixelBuffer = pixelBuffer(from: image) {
            return PanoramicFrame(
                pixelBuffer: pixelBuffer,
                timestampMs: timestampMs,
                orientation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
                acceleration: SIMD3<Float>(0, -9.8, 0)
            )
        }
        
        // 兜底合成全景帧
        let fallbackBuffer = createFallbackPixelBuffer(width: 1920, height: 960)
        return PanoramicFrame(
            pixelBuffer: fallbackBuffer,
            timestampMs: timestampMs,
            orientation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
            acceleration: SIMD3<Float>(0, -9.8, 0)
        )
    }
    
    private func pixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer, let cgImage = image.cgImage else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
            let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: rgbColorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
            context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
    
    private func createFallbackPixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        _ = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        let buffer = pixelBuffer!
        CVPixelBufferLockBaseAddress(buffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * bytesPerRow + x * 4
                    ptr[offset + 0] = 120
                    ptr[offset + 1] = 130
                    ptr[offset + 2] = 140
                    ptr[offset + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
    
    // MARK: - 测试 1: 脱机运行完整感知流水线 (预处理 -> DAP -> 反投影 -> 地面剥离 -> 障碍物 & 路线)
    func testFullPerceptionPipelineOfflineExecution() {
        guard let engine = engine else {
            XCTFail("引擎未初始化")
            return
        }
        
        engine.start()
        XCTAssertTrue(engine.isRunning, "引擎 start() 后应处于运行状态")
        
        obstacleExpectation = expectation(description: "接收到全场景障碍物数据")
        routeExpectation = expectation(description: "接收到可通行路线数据")
        
        let frame = createTestPanoramicFrame(timestampMs: 1000)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        engine.processFrame(frame)
        
        waitForExpectations(timeout: 5.0)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        
        XCTAssertNil(receivedError, "流水线执行不应抛出错误: \(receivedError?.localizedDescription ?? "")")
        
        // 1. 验证障碍物数据合法性
        guard let obstaclesData = receivedObstacles else {
            XCTFail("未接收到 ObstacleData")
            return
        }
        XCTAssertEqual(obstaclesData.timestampMs, 1000)
        XCTAssertGreaterThanOrEqual(obstaclesData.frameId, 1)
        
        // 2. 验证路线数据合法性
        guard let routeData = receivedRoute else {
            XCTFail("未接收到 PassableRouteData")
            return
        }
        XCTAssertGreaterThanOrEqual(routeData.safeDepth, 0.0)
        
        // 3. 验证主动快照属性
        XCTAssertNotNil(engine.latestObstacles)
        XCTAssertNotNil(engine.latestRoute)
        XCTAssertEqual(engine.latestObstacles?.timestampMs, 1000)
        
        Log.info("脱机全链路单帧处理耗时: \(elapsedMs) ms", category: .perception)
    }
    
    // MARK: - 测试 2: ObstacleData 与 PassableRouteData JSON 序列化合法性
    func testJSONSerializationRoundTrip() throws {
        // 1. 构造代表性障碍物数据
        let obs = ObstacleItem(
            id: 1,
            position: SIMD3<Float>(0.2, -1.0, -2.5),
            distance: 2.7,
            azimuth: 4.5,
            elevation: -20.0,
            size: SIMD3<Float>(0.5, 0.4, 0.5),
            category: .groundObstacle,
            relativeVelocity: SIMD3<Float>(0, 0, 0),
            approachRate: 0.0,
            priorityScore: 8.5,
            threatLevel: .warning,
            isRearHazard: false
        )
        let obstacleData = ObstacleData(frameId: 42, timestampMs: 123456, obstacles: [obs])
        
        // JSON 编解码测试
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let obsJsonData = try encoder.encode(obstacleData)
        XCTAssertFalse(obsJsonData.isEmpty)
        
        let decoder = JSONDecoder()
        let decodedObsData = try decoder.decode(ObstacleData.self, from: obsJsonData)
        XCTAssertEqual(decodedObsData.frameId, 42)
        XCTAssertEqual(decodedObsData.timestampMs, 123456)
        XCTAssertEqual(decodedObsData.obstacles.count, 1)
        XCTAssertEqual(decodedObsData.obstacles.first?.id, 1)
        
        // 2. 构造代表性可通行路线数据
        let wp = RouteWaypoint(position: SIMD3<Float>(0.1, -1.4, -1.5), clearanceWidth: 1.2)
        let routeData = PassableRouteData(
            isPathAvailable: true,
            safeDepth: 4.5,
            recommendedHeading: 3.5,
            waypoints: [wp]
        )
        
        let routeJsonData = try encoder.encode(routeData)
        XCTAssertFalse(routeJsonData.isEmpty)
        
        let decodedRouteData = try decoder.decode(PassableRouteData.self, from: routeJsonData)
        XCTAssertEqual(decodedRouteData.isPathAvailable, true)
        XCTAssertEqual(decodedRouteData.safeDepth, 4.5, accuracy: 0.001)
        XCTAssertEqual(decodedRouteData.recommendedHeading, 3.5, accuracy: 0.001)
        XCTAssertEqual(decodedRouteData.waypoints.count, 1)
    }
    
    // MARK: - 测试 3: 全链路单帧端到端耗时与算法吞吐基准测试 (Benchmark)
    func testEndToEndPipelineBenchmark() {
        guard let engine = engine else {
            XCTFail("引擎未初始化")
            return
        }
        engine.start()
        let frame = createTestPanoramicFrame(timestampMs: 1000)
        
        // 预热一帧
        let warmupExp = expectation(description: "预热完成")
        obstacleExpectation = warmupExp
        engine.processFrame(frame)
        wait(for: [warmupExp], timeout: 5.0)
        
        // 运行 5 帧并记录全链路耗时
        let testIterations = 5
        var totalElapsed: Double = 0
        for i in 0..<testIterations {
            let exp = expectation(description: "第 \(i) 帧计算完成")
            obstacleExpectation = exp
            let tStart = CFAbsoluteTimeGetCurrent()
            engine.processFrame(createTestPanoramicFrame(timestampMs: Int64(1000 + i * 100)))
            wait(for: [exp], timeout: 5.0)
            let tElapsed = (CFAbsoluteTimeGetCurrent() - tStart) * 1000.0
            totalElapsed += tElapsed
        }
        let avgLatencyMs = totalElapsed / Double(testIterations)
        XCTAssertGreaterThan(avgLatencyMs, 0.0)
        Log.info("全链路端到端平均处理耗时: \(String(format: "%.2f", avgLatencyMs)) ms", category: .perception)
    }
}
