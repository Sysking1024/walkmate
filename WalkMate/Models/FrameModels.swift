//
//  FrameModels.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-22.
//

import CoreVideo
import Foundation
import simd

/// 单次采集的完整全景感知数据输入帧
public struct PanoramicFrame {
    /// 图像像素缓存 (由相机硬件解码输出的 1080P 原生全景帧)
    public let pixelBuffer: CVPixelBuffer
    /// 采集毫秒时间戳
    public let timestampMs: Int64
    /// 相机当前绝对姿态四元数 (用于重力校准)
    public let orientation: simd_quatf
    /// 瞬时线性加速度向量 (单位: m/s²)
    public let acceleration: SIMD3<Float>
    
    /// 初始化全景数据帧
    public init(
        pixelBuffer: CVPixelBuffer,
        timestampMs: Int64,
        orientation: simd_quatf,
        acceleration: SIMD3<Float>
    ) {
        self.pixelBuffer = pixelBuffer
        self.timestampMs = timestampMs
        self.orientation = orientation
        self.acceleration = acceleration
    }
}

/// 全向物理深度矩阵 (256行 x 512列)
public struct DepthMatrix {
    /// 矩阵宽度 (列数)
    public static let width = 512
    /// 矩阵高度 (行数)
    public static let height = 256
    
    /// 连续内存物理深度数组 (单位: 米)
    /// 范围: 0.3m ~ 5.0m; 无效点、超出量程标记为 Float.nan 或 <= 0.0
    public let values: ContiguousArray<Float>
    /// 当前帧测得的最小物理距离 (米)
    public let minDepth: Float
    /// 当前帧测得的最大物理距离 (米)
    public let maxDepth: Float
    /// 采集时间戳 (毫秒)
    public let timestampMs: Int64
    
    /// 初始化物理深度矩阵
    public init(
        values: ContiguousArray<Float>,
        minDepth: Float,
        maxDepth: Float,
        timestampMs: Int64
    ) {
        self.values = values
        self.minDepth = minDepth
        self.maxDepth = maxDepth
        self.timestampMs = timestampMs
    }
}
