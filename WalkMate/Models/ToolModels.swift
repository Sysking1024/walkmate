//
//  ToolModels.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-23.
//

import Foundation
import simd

// MARK: - 钟表方位逆空间编码数据

/// 适合 VoiceOver 或 TTS 朗读的标准钟表方位数据包
public struct ClockPromptData: Codable, Equatable, Sendable {
    /// 钟表点位 (1 ~ 12，正前方为 12 点钟)
    public let clockHour: Int
    /// 直线距离 (单位: 米)
    public let distanceMeters: Float
    /// 高矮层级修饰词 ("低矮地面" / "平齐视线" / "悬空碰头")
    public let elevationLevel: String
    /// 组装好的标准朗读文案（例如："11点钟方向，前方1.8米，低矮地面"）
    public let readableSummary: String
    
    /// 初始化钟表文案数据
    public init(
        clockHour: Int,
        distanceMeters: Float,
        elevationLevel: String,
        readableSummary: String
    ) {
        self.clockHour = clockHour
        self.distanceMeters = distanceMeters
        self.elevationLevel = elevationLevel
        self.readableSummary = readableSummary
    }
}

// MARK: - 原生 3D 空间音频声源参数

/// 对应 iOS CoreAudio / AVAudio3DMixing 所需的原生 3D 声学与几何参数
public struct SpatialAudioRenderParams: Codable, Equatable, Sendable {
    /// 转换为苹果右手坐标系的 3D 声源锚点坐标 (直接映射至 AVAudio3DMixing.position)
    public let sourcePosition: SIMD3<Float>
    /// 推荐距离音量衰减系数 (0.0 ~ 1.0)
    public let attenuation: Float
    /// 建议的声源扩展角 (Spread Angle，度)
    public let spreadAngle: Float
    
    /// 初始化 3D 空间音频参数
    public init(
        sourcePosition: SIMD3<Float>,
        attenuation: Float,
        spreadAngle: Float
    ) {
        self.sourcePosition = sourcePosition
        self.attenuation = attenuation
        self.spreadAngle = spreadAngle
    }
}

// MARK: - 普通双声道立体声降级参数

/// 针对非空间音频耳机的双声道声相与脉冲参数
public struct StereoFallbackParams: Codable, Equatable, Sendable {
    /// 声道平衡 Pan: -1.0 (纯左耳) ~ +1.0 (纯右耳)，直接赋值给 AVAudioPlayer.pan
    public let stereoPan: Float
    /// 建议音调调节倍率 (0.5x ~ 2.0x，距离越近音调越高)
    public let pitchMultiplier: Float
    /// 建议蜂鸣脉冲间隔时间 (毫秒，例如 100ms ~ 800ms)
    public let recommendedPulseIntervalMs: Int
    
    /// 初始化双声道降级参数
    public init(
        stereoPan: Float,
        pitchMultiplier: Float,
        recommendedPulseIntervalMs: Int
    ) {
        self.stereoPan = stereoPan
        self.pitchMultiplier = pitchMultiplier
        self.recommendedPulseIntervalMs = recommendedPulseIntervalMs
    }
}

// MARK: - 几何净空检测结果

/// 指定行进方向的净空碰撞检测结果
public struct ClearanceResult: Codable, Equatable, Sendable {
    /// 该行进通道是否畅通
    public let isClear: Bool
    /// 最近阻挡物体的直线距离 (若畅通则为探测最大深度)
    public let nearestObstacleDistance: Float
    /// 冲突障碍物的跟踪 ID (若有)
    public let conflictingObstacleId: Int?
    
    /// 初始化几何净空结果
    public init(
        isClear: Bool,
        nearestObstacleDistance: Float,
        conflictingObstacleId: Int? = nil
    ) {
        self.isClear = isClear
        self.nearestObstacleDistance = nearestObstacleDistance
        self.conflictingObstacleId = conflictingObstacleId
    }
}
