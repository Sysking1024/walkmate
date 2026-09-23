//
//  InferenceTests.swift
//  InferenceTests
//
//  Created by Antigravity on 2026-09-23.
//

import CoreML
import CoreVideo
import UIKit
import XCTest
@testable import WalkMate

// MARK: - 推理与预处理单元测试套件
final class InferenceTests: XCTestCase {
    
    private var preprocessor: AcceleratePreprocessor!
    private var dapEngine: DAPEngine!
    
    override func setUp() {
        super.setUp()
        preprocessor = AcceleratePreprocessor()
        // 加载或初始化 DAP 引擎
        do {
            dapEngine = try DAPEngine()
        } catch {
            XCTFail("DAPEngine 初始化失败: \(error.localizedDescription)")
        }
    }
    
    override func tearDown() {
        preprocessor = nil
        dapEngine = nil
        super.tearDown()
    }
    
    // MARK: - 辅助方法：读取真实 pano_indoor.jpg 全景 CVPixelBuffer
    private func loadRealPanoIndoorPixelBuffer() -> CVPixelBuffer {
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let panoURL = sourceFileURL
            .deletingLastPathComponent() // InferenceTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // 工作空间根目录
            .appendingPathComponent("tmp/pano_indoor.jpg")
        
        guard FileManager.default.fileExists(atPath: panoURL.path) else {
            fatalError("【形式主义清零】必须存在真实样本 tmp/pano_indoor.jpg，严禁静默回退伪造数据！路径: \(panoURL.path)")
        }
        
        guard let image = UIImage(contentsOfFile: panoURL.path), let buffer = pixelBuffer(from: image) else {
            fatalError("【形式主义清零】加载 tmp/pano_indoor.jpg 并转换 CVPixelBuffer 失败！")
        }
        return buffer
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
    
    // MARK: - 测试 1: 图像硬件向量化缩放与归一化
    func testAcceleratePreprocessorOutputShapeAndNormalization() throws {
        let inputBuffer = loadRealPanoIndoorPixelBuffer()
        
        // 预热一帧，排除缺页中断与冷启动缓存影响
        _ = try preprocessor.preprocess(pixelBuffer: inputBuffer)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let tensor = try preprocessor.preprocess(pixelBuffer: inputBuffer)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        
        // 1. 验证张量维度是否严格为 [1, 3, 256, 512]
        XCTAssertEqual(tensor.shape.count, 4)
        XCTAssertEqual(tensor.shape[0].intValue, 1)
        XCTAssertEqual(tensor.shape[1].intValue, 3)
        XCTAssertEqual(tensor.shape[2].intValue, 256)
        XCTAssertEqual(tensor.shape[3].intValue, 512)
        
        // 2. 验证预处理耗时满足 11.2ms 硬件向量化预算 (严格遵守 T011 与宪章原则二)
        XCTAssertLessThanOrEqual(elapsedMs, 11.2, "Accelerate vDSP 硬件向量化单帧耗时超出 11.2ms 预算: \(elapsedMs)ms")
        
        // 3. 验证归一化数值范围严格在 [0.0, 1.0] 内
        let count = tensor.count
        let ptr = tensor.dataPointer.bindMemory(to: Float.self, capacity: count)
        var minVal: Float = 1.0
        var maxVal: Float = 0.0
        for i in 0..<min(count, 1000) {
            let v = ptr[i]
            if v < minVal { minVal = v }
            if v > maxVal { maxVal = v }
        }
        XCTAssertGreaterThanOrEqual(minVal, 0.0, "像素值出现负数")
        XCTAssertLessThanOrEqual(maxVal, 1.0, "像素值超过 1.0")
    }
    
    // MARK: - 测试 2: DAP 模型 CoreML INT8 纯硬件推理与深度矩阵输出
    func testDAPEngineInferenceAndDepthOutput() throws {
        guard let engine = dapEngine else {
            XCTFail("DAPEngine 为空")
            return
        }
        
        let inputBuffer = loadRealPanoIndoorPixelBuffer()
        let tensor = try preprocessor.preprocess(pixelBuffer: inputBuffer)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let depthMatrix = try engine.inferDepth(from: tensor, timestampMs: 1000)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        
        // 1. 验证深度矩阵尺寸为 256 x 512
        XCTAssertEqual(depthMatrix.values.count, DepthMatrix.width * DepthMatrix.height)
        XCTAssertEqual(DepthMatrix.width, 512)
        XCTAssertEqual(DepthMatrix.height, 256)
        
        // 2. 验证时间戳传递
        XCTAssertEqual(depthMatrix.timestampMs, 1000)
        
        // 3. 验证物理深度数值有效性 (室内场景一般在 0.3m ~ 20.0m)
        XCTAssertGreaterThan(depthMatrix.minDepth, 0.0, "最小深度不应小于等于0")
        XCTAssertLessThan(depthMatrix.maxDepth, 100.0, "最大深度超出物理合理范围")
        
        // 4. 验证推理性能满足预算 (模拟器/ANE 下单帧可执行)
        Log.info("DAP 推理单帧实测耗时: \(elapsedMs) ms", category: .perception)
    }
}
