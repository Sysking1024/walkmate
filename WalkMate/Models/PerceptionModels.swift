//
//  PerceptionModels.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-22.
//

import Foundation
import simd

/// 单个空间障碍物在使用者相对坐标系中的空间描述
public struct SpatialObstacleItem: Codable, Equatable, Sendable {
    /// 三维相对坐标 (x:水平左右, y:垂直高度, z:前后纵深, 单位: 米)
    /// 严格遵循 iOS 空间音频右手坐标系: +X 为右, -X 为左, +Y 为上, -Z 为前 (纵深前向为负), +Z 为后
    public let position: SIMD3<Float>
    /// 空间直线绝对距离 (单位: 米)
    public let distance: Float
    /// 水平偏转方位角 (单位: 度, 负值为左, 正值为右)
    public let azimuth: Float
    /// 垂直仰角 (单位: 度, 负值为低矮, 正值为悬挂)
    public let elevation: Float
    /// 动态相对接近速率 (米/秒, 计算公式 v_approach = (d_{t-1} - d_t) / Δt, 正值表示迎面逼近, 负值表示远离)
    public let approachRate: Float
    /// 综合威胁优先级评分
    public let priorityScore: Float
    /// 威胁级别
    public let threatLevel: ThreatLevel
    /// 是否为身后危险 (true 表示在用户后方，触发后方空间音频)
    public let isRearHazard: Bool
    
    public init(
        position: SIMD3<Float>,
        distance: Float,
        azimuth: Float,
        elevation: Float,
        approachRate: Float,
        priorityScore: Float,
        threatLevel: ThreatLevel,
        isRearHazard: Bool
    ) {
        self.position = position
        self.distance = distance
        self.azimuth = azimuth
        self.elevation = elevation
        self.approachRate = approachRate
        self.priorityScore = priorityScore
        self.threatLevel = threatLevel
        self.isRearHazard = isRearHazard
    }
}

/// 当前最佳安全通行走廊几何描述
public struct PassageCorridorGeometry: Codable, Equatable, Sendable {
    /// 是否存在可通过走廊 (人体宽度 0.6m 约束)
    public let isPassable: Bool
    /// 建议行进方位角 (度, 指向通道中心)
    public let recommendedSteeringAngle: Float
    /// 通道最窄处的物理净宽 (米, 如 0.9m 门宽)
    public let clearanceWidth: Float
    /// 安全可行进纵深距离 (米)
    public let passableDepth: Float
    /// 通道中心的三维空间导向锚点坐标 (严格遵循 iOS 空间音频坐标系: targetAnchor.z = -min(passableDepth, 2.0) <= 0; 当 isPassable == false 时统一为 SIMD3<Float>.zero)
    public let targetAnchor: SIMD3<Float>
    
    public init(
        isPassable: Bool,
        recommendedSteeringAngle: Float,
        clearanceWidth: Float,
        passableDepth: Float,
        targetAnchor: SIMD3<Float>
    ) {
        self.isPassable = isPassable
        self.recommendedSteeringAngle = recommendedSteeringAngle
        self.clearanceWidth = clearanceWidth
        self.passableDepth = passableDepth
        self.targetAnchor = targetAnchor
    }
    
    /// 默认不可通行走廊
    public static var blocked: PassageCorridorGeometry {
        PassageCorridorGeometry(
            isPassable: false,
            recommendedSteeringAngle: 0.0,
            clearanceWidth: 0.0,
            passableDepth: 0.0,
            targetAnchor: SIMD3<Float>(0, 0, 0)
        )
    }
}

/// 前方或后方地面踏空下沉事件
public struct DropOffHazardEvent: Codable, Equatable, Sendable {
    /// 距离使用者的水平距离 (米)
    public let distance: Float
    /// 危险边缘所在方位角 (度)
    public let azimuth: Float
    /// 预估向下落差深度 (米, 通常 > 0.15m 触发)
    public let dropDepth: Float
    /// 是否发生在身后 (true 表示后退踩空危险)
    public let isRearHazard: Bool
    
    public init(
        distance: Float,
        azimuth: Float,
        dropDepth: Float,
        isRearHazard: Bool
    ) {
        self.distance = distance
        self.azimuth = azimuth
        self.dropDepth = dropDepth
        self.isRearHazard = isRearHazard
    }
}

/// 每帧对外输出的完整空间感知聚合结果 (供上层空间音频消费)
public struct SpatialPerceptionResult: Codable, Sendable {
    /// 帧序号
    public let frameId: Int64
    /// 毫秒时间戳
    public let timestampMs: Int64
    /// 用户当前运动状态
    public let motionState: UserMotionState
    /// 障碍物列表 (按优先级排序，最多 3 项)
    public let obstacles: [SpatialObstacleItem]
    /// 安全通行走廊
    public let corridor: PassageCorridorGeometry
    /// 跌落风险 (若无则为 nil)
    public let dropOff: DropOffHazardEvent?
    /// 传感器遥测指标
    public let telemetry: SensorTelemetry
    
    public init(
        frameId: Int64,
        timestampMs: Int64,
        motionState: UserMotionState,
        obstacles: [SpatialObstacleItem],
        corridor: PassageCorridorGeometry,
        dropOff: DropOffHazardEvent?,
        telemetry: SensorTelemetry
    ) {
        self.frameId = frameId
        self.timestampMs = timestampMs
        self.motionState = motionState
        self.obstacles = obstacles
        self.corridor = corridor
        self.dropOff = dropOff
        self.telemetry = telemetry
    }
}
