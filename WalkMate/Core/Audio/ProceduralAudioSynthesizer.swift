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
}
