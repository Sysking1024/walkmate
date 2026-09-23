//
//  ProceduralAudioSynthesizerTests.swift
//  AudioTests
//
//  Created by Antigravity on 2026-09-23.
//

import AVFoundation
import XCTest
@testable import WalkMate

// MARK: - 纯代码参数化音频合成器单元测试套件
final class ProceduralAudioSynthesizerTests: XCTestCase {
    
    // MARK: - 测试 1: 基础格式与点声源尺寸常数校验
    func testAudioFormatConstants() {
        // 验证标准采样率为 44.1 kHz
        XCTAssertEqual(ProceduralAudioSynthesizer.sampleRate, 44100.0, accuracy: 0.001, "采样率必须严格为 44100 Hz")
        
        let format = ProceduralAudioSynthesizer.audioFormat
        // 验证单声道与 32位 浮点标准
        XCTAssertEqual(format.channelCount, 1, "空间音频合成源必须为单声道")
        XCTAssertEqual(format.sampleRate, 44100.0, accuracy: 0.001, "音频格式采样率必须为 44.1kHz")
        XCTAssertEqual(format.commonFormat, .pcmFormatFloat32, "音频格式必须为 Float32 标准单精度浮点")
        
        // 验证默认点声源包围盒尺寸
        let defaultSize = ProceduralAudioSynthesizer.defaultPointSourceBoundingSize
        XCTAssertEqual(defaultSize.x, 0.2, accuracy: 0.001)
        XCTAssertEqual(defaultSize.y, 0.2, accuracy: 0.001)
        XCTAssertEqual(defaultSize.z, 0.2, accuracy: 0.001)
    }
    
    // MARK: - 测试 2: 金属撞击音 PCM Buffer 规格与有效性验证
    func testGenerateMetallicImpactBuffer() {
        let buffer = ProceduralAudioSynthesizer.generateMetallicImpactBuffer()
        
        // 0.1秒对应 4410 个采样帧
        XCTAssertEqual(buffer.frameLength, 4410, "金属撞击音长度必须严格为 4410 采样点 (0.1秒)")
        XCTAssertEqual(buffer.format, ProceduralAudioSynthesizer.audioFormat)
        
        guard let channelData = buffer.floatChannelData?[0] else {
            XCTFail("无法获取金属撞击音声道数据")
            return
        }
        
        var maxAbsAmp: Float = 0.0
        var hasNonZero = false
        for i in 0..<Int(buffer.frameLength) {
            let sample = channelData[i]
            // 验证振幅在 [-1.0, 1.0] 范围内，严禁溢出削波
            XCTAssertTrue(sample >= -1.0 && sample <= 1.0, "采样点超出了 [-1.0, 1.0] 合法范围: \(sample)")
            maxAbsAmp = max(maxAbsAmp, abs(sample))
            if abs(sample) > 0.001 {
                hasNonZero = true
            }
        }
        
        XCTAssertTrue(hasNonZero, "生成的金属撞击音不能全为静音")
        XCTAssertGreaterThan(maxAbsAmp, 0.2, "金属撞击音峰值振幅必须具有足够动态响度")
    }
    
    // MARK: - 测试 3: 轻快脚步声 PCM Buffer 规格与有效性验证
    func testGenerateFootstepBuffer() {
        let buffer = ProceduralAudioSynthesizer.generateFootstepBuffer()
        
        // 0.08秒对应 3528 个采样帧
        XCTAssertEqual(buffer.frameLength, 3528, "轻快脚步声长度必须严格为 3528 采样点 (0.08秒)")
        XCTAssertEqual(buffer.format, ProceduralAudioSynthesizer.audioFormat)
        
        guard let channelData = buffer.floatChannelData?[0] else {
            XCTFail("无法获取轻快脚步音声道数据")
            return
        }
        
        var maxAbsAmp: Float = 0.0
        var hasNonZero = false
        for i in 0..<Int(buffer.frameLength) {
            let sample = channelData[i]
            XCTAssertTrue(sample >= -1.0 && sample <= 1.0, "采样点超出了 [-1.0, 1.0] 合法范围: \(sample)")
            maxAbsAmp = max(maxAbsAmp, abs(sample))
            if abs(sample) > 0.001 {
                hasNonZero = true
            }
        }
        
        XCTAssertTrue(hasNonZero, "生成的轻快脚步声不能全为静音")
        XCTAssertGreaterThan(maxAbsAmp, 0.1, "脚步声峰值振幅必须具有可辨识响度")
    }
    
    // MARK: - 测试 4: 康复达标激励和弦音 PCM Buffer 规格与有效性验证
    func testGenerateRewardChimeBuffer() {
        let buffer = ProceduralAudioSynthesizer.generateRewardChimeBuffer()
        
        // 0.4秒对应 17640 个采样帧
        XCTAssertEqual(buffer.frameLength, 17640, "康复激励和弦音长度必须严格为 17640 采样点 (0.4秒)")
        XCTAssertEqual(buffer.format, ProceduralAudioSynthesizer.audioFormat)
        
        guard let channelData = buffer.floatChannelData?[0] else {
            XCTFail("无法获取康复激励和弦音声道数据")
            return
        }
        
        var maxAbsAmp: Float = 0.0
        var hasNonZero = false
        for i in 0..<Int(buffer.frameLength) {
            let sample = channelData[i]
            XCTAssertTrue(sample >= -1.0 && sample <= 1.0, "采样点超出了 [-1.0, 1.0] 合法范围: \(sample)")
            maxAbsAmp = max(maxAbsAmp, abs(sample))
            if abs(sample) > 0.001 {
                hasNonZero = true
            }
        }
        
        XCTAssertTrue(hasNonZero, "生成的康复激励和弦音不能全为静音")
        XCTAssertGreaterThan(maxAbsAmp, 0.2, "和弦音峰值振幅必须具有清晰明亮响度")
    }
    
    // MARK: - 测试 5: 纯内存实时合成性能与常驻内存开销验证 (SC-002)
    func testSynthesisPerformance() {
        // 单次执行耗时断言：全套三种音效总生成耗时小于 5ms
        let start = CACurrentMediaTime()
        let b1 = ProceduralAudioSynthesizer.generateMetallicImpactBuffer()
        let b2 = ProceduralAudioSynthesizer.generateFootstepBuffer()
        let b3 = ProceduralAudioSynthesizer.generateRewardChimeBuffer()
        let elapsedMs = (CACurrentMediaTime() - start) * 1000.0
        
        XCTAssertLessThan(elapsedMs, 5.0, "全套三种音效单次合成耗时必须严格小于 5ms (SC-002)，实测: \(elapsedMs)ms")
        
        // 验证常驻采样数据总内存 < 150 KB (实际约 102 KB)
        let totalFrames = b1.frameLength + b2.frameLength + b3.frameLength
        let memoryBytes = Int(totalFrames) * MemoryLayout<Float>.size
        let memoryKB = Double(memoryBytes) / 1024.0
        XCTAssertLessThan(memoryKB, 150.0, "常驻原始 PCM 采样点内存占用必须小于 150 KB，实测: \(memoryKB)KB")
    }
}
