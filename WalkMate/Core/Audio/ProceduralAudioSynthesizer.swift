//
//  ProceduralAudioSynthesizer.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-23.
//

import AVFoundation
import Foundation

// MARK: - 纯代码物理建模音频合成器
/// 负责基于 DSP 物理建模在内存中实时合成单声道 PCM 声音缓存，严禁外部音频素材依赖
public enum ProceduralAudioSynthesizer {
    
    /// 音频标准采样率 (44.1 kHz)
    public static let sampleRate: Double = 44100.0
    
    /// 标准单声道 Float32 PCM 音频格式
    public static let audioFormat: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!
    
    /// 默认点声源包围盒尺寸 (0.2m x 0.2m x 0.2m，用于 SpatialAudioKit 坐标转换)
    public static let defaultPointSourceBoundingSize = SIMD3<Float>(0.2, 0.2, 0.2)
    
    // MARK: - 1. 合成金属撞击音 PCM 缓存 (0.1秒, 800Hz 冲击共鸣)
    /// 用于危险障碍物双音确认避障警示
    public static func generateMetallicImpactBuffer() -> AVAudioPCMBuffer {
        // 采样时长 0.1 秒，对应 4410 个采样点
        let frameCount: AVAudioFrameCount = 4410
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            fatalError("无法初始化金属撞击音 AVAudioPCMBuffer")
        }
        buffer.frameLength = frameCount
        let channelData = buffer.floatChannelData![0]
        
        let sampleRateFloat = Float(sampleRate)
        let twoPi: Float = 2.0 * .pi
        
        // 增量相位步进参数 (800Hz 基频, 1130Hz, 1720Hz, 2800Hz)
        let inc0 = twoPi * 800.0 / sampleRateFloat
        let inc1 = twoPi * 1130.0 / sampleRateFloat
        let inc2 = twoPi * 1720.0 / sampleRateFloat
        let inc3 = twoPi * 2800.0 / sampleRateFloat
        
        var phase0: Float = 0.0
        var phase1: Float = 0.0
        var phase2: Float = 0.0
        var phase3: Float = 0.0
        
        // 衰减常数 45ms 转换为每采样点乘性衰减因子
        let decayPerSample = exp(-1.0 / (0.045 * sampleRateFloat))
        var envelope: Float = 0.85
        
        // 伪随机数种子保证每次合成确定性与零环境差异
        var seed: UInt32 = 123456789
        func pseudoRandom() -> Float {
            seed = seed &* 1664525 &+ 1013904223
            return (Float(seed & 0x00FFFFFF) / Float(0x00FFFFFF)) * 2.0 - 1.0
        }
        
        let noiseFrames = Int(0.003 * sampleRateFloat) // 前 3ms
        let noiseWindowStep = twoPi / Float(max(1, noiseFrames))
        var noiseAngle: Float = 0.0
        
        for i in 0..<Int(frameCount) {
            // 4 组非谐波金属共鸣正弦波叠加
            let s0 = 0.45 * sin(phase0)
            let s1 = 0.25 * sin(phase1)
            let s2 = 0.18 * sin(phase2)
            let s3 = 0.12 * sin(phase3)
            let resonance = s0 + s1 + s2 + s3
            
            // 前 3 毫秒汉宁窗白噪声冲击
            var noiseBurst: Float = 0.0
            if i < noiseFrames {
                let window = 0.5 * (1.0 - cos(noiseAngle))
                noiseBurst = pseudoRandom() * window * 0.35
                noiseAngle += noiseWindowStep
            }
            
            let rawSample = (resonance + noiseBurst) * envelope
            channelData[i] = max(-1.0, min(1.0, rawSample))
            
            // 相位累加与包络乘性平滑衰减
            phase0 += inc0
            phase1 += inc1
            phase2 += inc2
            phase3 += inc3
            envelope *= decayPerSample
        }
        
        return buffer
    }
    
    // MARK: - 2. 合成轻快脚步声 PCM 缓存 (0.08秒, 阻尼冲击加带通摩擦)
    /// 用于安全可行路径的前方领路脚步声
    public static func generateFootstepBuffer() -> AVAudioPCMBuffer {
        // 采样时长 0.08 秒，对应 3528 个采样点
        let frameCount: AVAudioFrameCount = 3528
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            fatalError("无法初始化轻快脚步声 AVAudioPCMBuffer")
        }
        buffer.frameLength = frameCount
        let channelData = buffer.floatChannelData![0]
        
        let sampleRateFloat = Float(sampleRate)
        let twoPi: Float = 2.0 * .pi
        
        var seed: UInt32 = 987654321
        func pseudoRandom() -> Float {
            seed = seed &* 1664525 &+ 1013904223
            return (Float(seed & 0x00FFFFFF) / Float(0x00FFFFFF)) * 2.0 - 1.0
        }
        
        var previousNoise: Float = 0.0
        var phase: Float = 0.0
        let totalDuration: Float = Float(frameCount) / sampleRateFloat
        
        let heelDecayPerSample = exp(-1.0 / (0.02 * sampleRateFloat))
        var heelEnvelope: Float = 0.65
        
        let frictionDecayPerSample = exp(-1.0 / (0.025 * sampleRateFloat))
        var frictionEnvelope: Float = 0.25
        
        // 为 iPhone 自带扬声器外放增加 750Hz 触地瞬态冲击，兼顾微型喇叭频响 (避免纯低频外放静音)
        var clickPhase: Float = 0.0
        let clickInc = twoPi * 750.0 / sampleRateFloat
        let clickDecayPerSample = exp(-1.0 / (0.008 * sampleRateFloat))
        var clickEnvelope: Float = 0.35
        
        for i in 0..<Int(frameCount) {
            let progress = Float(i) / Float(frameCount)
            // 频率从 120Hz 滑落至 70Hz
            let currentFreq = 120.0 - 50.0 * progress
            let phaseInc = twoPi * currentFreq / sampleRateFloat
            
            let heelImpact = sin(phase) * heelEnvelope
            
            // 一阶差分高通白噪声模拟碎擦
            let rawNoise = pseudoRandom()
            let diffNoise = (rawNoise - previousNoise) * 0.5
            previousNoise = rawNoise
            let friction = diffNoise * frictionEnvelope
            
            // 触地瞬态冲击音（前 12ms 快速衰减）
            let click = sin(clickPhase) * clickEnvelope
            
            let rawSample = heelImpact + friction + click
            channelData[i] = max(-1.0, min(1.0, rawSample))
            
            phase += phaseInc
            clickPhase += clickInc
            heelEnvelope *= heelDecayPerSample
            frictionEnvelope *= frictionDecayPerSample
            clickEnvelope *= clickDecayPerSample
        }
        
        return buffer
    }
    
    // MARK: - 3. 合成康复激励上行大三和弦 PCM 缓存 (0.4秒, C5-E5-G5-C6 琶音)
    /// 用于行走康复达标激励
    public static func generateRewardChimeBuffer() -> AVAudioPCMBuffer {
        // 采样时长 0.4 秒，对应 17640 个采样点
        let frameCount: AVAudioFrameCount = 17640
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            fatalError("无法初始化康复激励和弦音 AVAudioPCMBuffer")
        }
        buffer.frameLength = frameCount
        let channelData = buffer.floatChannelData![0]
        
        // 清零缓冲区
        memset(channelData, 0, Int(frameCount) * MemoryLayout<Float>.size)
        
        let sampleRateFloat = Float(sampleRate)
        let twoPi: Float = 2.0 * .pi
        
        // C5 (523.25Hz), E5 (659.25Hz), G5 (783.99Hz), C6 (1046.50Hz) 错开 30ms 琶音
        let notes: [(freq: Float, startFrame: Int)] = [
            (523.25, 0),
            (659.25, Int(0.030 * sampleRateFloat)),
            (783.99, Int(0.060 * sampleRateFloat)),
            (1046.50, Int(0.090 * sampleRateFloat))
        ]
        
        let decayMultiplier = exp(-1.0 / (0.12 * sampleRateFloat))
        let totalCount = Int(frameCount)
        
        // 使用高效相位累加器与外层循环分离，原地累加到目标缓冲区
        for note in notes {
            let phaseInc = twoPi * note.freq / sampleRateFloat
            let harmonicInc = phaseInc * 2.0
            var phase: Float = 0.0
            var harmonicPhase: Float = 0.0
            var envelope: Float = 0.26
            
            var i = note.startFrame
            while i < totalCount {
                let fundamental = sin(phase)
                let harmonic = 0.22 * sin(harmonicPhase)
                channelData[i] += (fundamental + harmonic) * envelope
                
                phase += phaseInc
                harmonicPhase += harmonicInc
                envelope *= decayMultiplier
                i += 1
            }
        }
        
        // 限制在 [-1.0, 1.0] 范围内防止溢出削波
        for i in 0..<totalCount {
            if channelData[i] > 1.0 {
                channelData[i] = 1.0
            } else if channelData[i] < -1.0 {
                channelData[i] = -1.0
            }
        }
        
        return buffer
    }
}
