//
//  PerceptionAudioIntegrationTests.swift
//  PerceptionTests
//
//  Created by Antigravity on 2026-09-23.
//

import CoreVideo
import simd
import UIKit
import XCTest
@testable import WalkMate

// MARK: - 全景图驱动空间音频端到端集成测试套件 (T012)
final class PerceptionAudioIntegrationTests: XCTestCase, SpatialPerceptionDelegate {
    
    private var perceptionEngine: SpatialPerceptionEngine!
    private var audioPlayer: SpatialAudioPlayer!
    
    private var obstacleExpectation: XCTestExpectation?
    private var routeExpectation: XCTestExpectation?
    
    private var receivedObstacles: ObstacleData?
    private var receivedRoute: PassableRouteData?
    private var receivedError: Error?
    
    override func setUp() {
        super.setUp()
        do {
            perceptionEngine = try SpatialPerceptionEngine()
            perceptionEngine.delegate = self
            perceptionEngine.start()
            audioPlayer = SpatialAudioPlayer()
            try audioPlayer.start()
        } catch {
            XCTFail("初始化端到端组件失败: \(error.localizedDescription)")
        }
    }
    
    override func tearDown() {
        perceptionEngine?.stop()
        perceptionEngine = nil
        audioPlayer?.stop()
        audioPlayer = nil
        obstacleExpectation = nil
        routeExpectation = nil
        receivedObstacles = nil
        receivedRoute = nil
        receivedError = nil
        super.tearDown()
    }
    
    // MARK: - 感知代理回调驱动空间音频
    
    func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didProduceObstacles data: ObstacleData) {
        receivedObstacles = data
        
        // 避障驱动：若存在 3.0 米以内的危险障碍物，提取最邻近障碍物三维坐标注入空间音频
        let nearestHazard = data.obstacles
            .filter { $0.distance < 3.0 }
            .min(by: { $0.distance < $1.distance })
        
        audioPlayer.setObstacleTarget(position: nearestHazard?.position)
        obstacleExpectation?.fulfill()
    }
    
    func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didProducePassableRoute data: PassableRouteData) {
        receivedRoute = data
        
        // 领路驱动：提取前方首个安全导航航路点坐标注入空间音频领路脚步声
        let targetWaypoint = data.waypoints.first?.position
        audioPlayer.setNavigationTarget(position: targetWaypoint)
        routeExpectation?.fulfill()
    }
    
    func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didEncounterError error: Error) {
        receivedError = error
    }
    
    // MARK: - 辅助方法：读取真实全景图样本 tmp/pano_indoor.jpg
    
    private func createTestPanoramicFrame(timestampMs: Int64 = 1000) -> PanoramicFrame {
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let panoURL = sourceFileURL
            .deletingLastPathComponent() // PerceptionTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("tmp/pano_indoor.jpg")
        
        guard FileManager.default.fileExists(atPath: panoURL.path) else {
            fatalError("【形式主义清零】必须存在真实样本 tmp/pano_indoor.jpg，严禁静默回退伪造数据！路径: \(panoURL.path)")
        }
        
        guard let image = UIImage(contentsOfFile: panoURL.path), let pixelBuffer = pixelBuffer(from: image) else {
            fatalError("【形式主义清零】加载 tmp/pano_indoor.jpg 并转换 CVPixelBuffer 失败！")
        }
        
        return PanoramicFrame(
            pixelBuffer: pixelBuffer,
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
    
    // MARK: - 测试用例: 全景图驱动空间音频端到端全链路闭环验证 (T012)
    func testEndToEndPanoramicPerceptionDrivingSpatialAudio() throws {
        XCTAssertTrue(perceptionEngine.isRunning, "感知引擎应就绪运行")
        XCTAssertTrue(audioPlayer.isRunning, "空间音频引擎应就绪运行")
        
        obstacleExpectation = expectation(description: "感知引擎输出障碍物并驱动空间音频")
        routeExpectation = expectation(description: "感知引擎输出可行走路线并驱动领路脚步声")
        
        // 注入真实全景室内图样本
        let frame = createTestPanoramicFrame(timestampMs: 1000)
        let startTime = CFAbsoluteTimeGetCurrent()
        perceptionEngine.processFrame(frame)
        
        wait(for: [obstacleExpectation!, routeExpectation!], timeout: 5.0)
        let pipelineTimeMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        Log.info("真实样本端到端感知+音频全链路调度耗时: \(pipelineTimeMs) ms", category: .audio)
        
        XCTAssertNil(receivedError, "感知流水线不应产生异常错误")
        
        // 1. 验证障碍物声源驱动与方位绑定
        guard let obstacles = receivedObstacles else {
            XCTFail("未接收到真实全景图生成的障碍物数据")
            return
        }
        if let nearest = obstacles.obstacles.filter({ $0.distance < 3.0 }).min(by: { $0.distance < $1.distance }) {
            // 等待音频主队列处理
            let expAudio = expectation(description: "障碍物声源映射生效")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let renderParams = SpatialAudioKit.toSpatialAudioRenderParams(
                    position: nearest.position,
                    boundingSize: ProceduralAudioSynthesizer.defaultPointSourceBoundingSize
                )
                XCTAssertEqual(self.audioPlayer.obstaclePlayerNode.position.x, renderParams.sourcePosition.x, accuracy: 0.05)
                XCTAssertEqual(self.audioPlayer.obstaclePlayerNode.position.z, renderParams.sourcePosition.z, accuracy: 0.05)
                expAudio.fulfill()
            }
            wait(for: [expAudio], timeout: 0.2)
        }
        
        // 2. 验证路线导航声源驱动与方位绑定
        guard let route = receivedRoute else {
            XCTFail("未接收到真实全景图生成的可通行路线数据")
            return
        }
        if let waypoint = route.waypoints.first {
            let expNav = expectation(description: "导航声源映射生效")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                XCTAssertTrue(self.audioPlayer.isNavigationActive, "接收到航路点后领路脚步声必须激活")
                let renderParams = SpatialAudioKit.toSpatialAudioRenderParams(
                    position: waypoint.position,
                    boundingSize: ProceduralAudioSynthesizer.defaultPointSourceBoundingSize
                )
                XCTAssertEqual(self.audioPlayer.navigationPlayerNode.position.x, renderParams.sourcePosition.x, accuracy: 0.05)
                XCTAssertEqual(self.audioPlayer.navigationPlayerNode.position.z, renderParams.sourcePosition.z, accuracy: 0.05)
                expNav.fulfill()
            }
            wait(for: [expNav], timeout: 0.2)
        }
        
        // 3. 验证触发康复激励音与压音闭环
        audioPlayer.playRewardSound()
        let expReward = expectation(description: "康复激励音播放并在脚步声激活时执行让位")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertTrue(self.audioPlayer.isRewardActive)
            if self.audioPlayer.isNavigationActive {
                XCTAssertEqual(self.audioPlayer.navigationPlayerNode.volume, 0.3, accuracy: 0.01)
            }
            expReward.fulfill()
        }
        wait(for: [expReward], timeout: 0.2)
        
        // 4. 重置并安全释放
        audioPlayer.reset()
        XCTAssertFalse(audioPlayer.isNavigationActive)
        XCTAssertFalse(audioPlayer.isRewardActive)
    }
}
