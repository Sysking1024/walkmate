//
//  PerceptionModels.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-22（修订于 2026-09-23）.
//

import Foundation
import simd

// MARK: - 障碍物与空间危险源分类

/// 空间障碍物/危险源类型分类
public enum ObstacleCategory: String, Codable, Sendable {
    /// 地面凸起障碍物（箱子、椅子、立柱等）
    case groundObstacle = "groundObstacle"
    /// 高空悬挂/碰头危险（离地 > 1.4 米的悬空树枝、招牌等）
    case hangingHazard = "hangingHazard"
    /// 地面下沉断层（落差 > 15 厘米的下行阶梯、深坑台阶等）
    case dropOffHazard = "dropOffHazard"
    /// 动态移动行人或物体
    case dynamicEntity = "dynamicEntity"
}

// MARK: - 单个空间障碍物实体

/// 单个空间障碍物在使用者相对坐标系中的空间描述
public struct ObstacleItem: Codable, Equatable, Sendable, Identifiable {
    /// 跨帧唯一跟踪标识符（在目标连续移动期间保持稳定）
    public let id: Int
    /// 三维相对坐标 (x:水平左右, y:垂直高度, z:前后纵深, 单位: 米)
    /// 严格遵循 iOS 空间音频右手坐标系: +X 为右, -X 为左, +Y 为上, -Z 为前向纵深, +Z 为后方
    public let position: SIMD3<Float>
    /// 直线绝对距离 (单位: 米)
    public let distance: Float
    /// 水平偏转方位角 (单位: 度, -180° ~ +180°, 0° 为正前方, 负值为左, 正值为右)
    public let azimuth: Float
    /// 垂直仰角 (单位: 度, 负值为低矮, 正值为悬挂)
    public let elevation: Float
    /// 物理空间三维包围盒尺寸 (宽、高、深，单位: 米)
    public let size: SIMD3<Float>
    /// 障碍物危险源分类
    public let category: ObstacleCategory
    /// 相对运动速度矢量 (vx, vy, vz, 单位: 米/秒)
    public let relativeVelocity: SIMD3<Float>
    /// 标量动态相对接近速率 (米/秒, 正值表示迎面逼近, 负值表示远离)
    public let approachRate: Float
    /// 综合威胁优先级评分
    public let priorityScore: Float
    /// 威胁级别
    public let threatLevel: ThreatLevel
    /// 是否位于使用者后方 (true 表示处于后方视野)
    public let isRearHazard: Bool
    
    /// 初始化障碍物对象
    public init(
        id: Int,
        position: SIMD3<Float>,
        distance: Float,
        azimuth: Float,
        elevation: Float,
        size: SIMD3<Float>,
        category: ObstacleCategory,
        relativeVelocity: SIMD3<Float>,
        approachRate: Float,
        priorityScore: Float,
        threatLevel: ThreatLevel,
        isRearHazard: Bool
    ) {
        self.id = id
        self.position = position
        self.distance = distance
        self.azimuth = azimuth
        self.elevation = elevation
        self.size = size
        self.category = category
        self.relativeVelocity = relativeVelocity
        self.approachRate = approachRate
        self.priorityScore = priorityScore
        self.threatLevel = threatLevel
        self.isRearHazard = isRearHazard
    }
}

// MARK: - 全场景 360° 障碍物集合

/// 单帧输出的全场景 360° 障碍物数据聚合体
public struct ObstacleData: Codable, Equatable, Sendable {
    /// 对应输入视频帧序号
    public let frameId: Int64
    /// 毫秒时间戳
    public let timestampMs: Int64
    /// 全量检出的 360° 障碍物列表
    public let obstacles: [ObstacleItem]
    
    /// 初始化全场景障碍物集合
    public init(
        frameId: Int64,
        timestampMs: Int64,
        obstacles: [ObstacleItem]
    ) {
        self.frameId = frameId
        self.timestampMs = timestampMs
        self.obstacles = obstacles
    }
}

// MARK: - 可通行路线折线实体

/// 可通行路线上的单个三维路标折线点
public struct RouteWaypoint: Codable, Equatable, Sendable {
    /// 相对空间三维坐标 (单位: 米)
    public let position: SIMD3<Float>
    /// 该路标点位置处的物理通行净宽 (单位: 米，如 1.2m)
    public let clearanceWidth: Float
    
    /// 初始化路标点
    public init(position: SIMD3<Float>, clearanceWidth: Float) {
        self.position = position
        self.clearanceWidth = clearanceWidth
    }
}

/// 当前可通行路线与空间走廊几何描述
public struct PassableRouteData: Codable, Equatable, Sendable {
    /// 是否存在安全可通过路线
    public let isPathAvailable: Bool
    /// 最大安全可行进纵深 (米)
    public let safeDepth: Float
    /// 推荐起步偏航方位角 (度, 指向通道中心)
    public let recommendedHeading: Float
    /// 连续路径路标点序列（由近及远排列）
    public let waypoints: [RouteWaypoint]
    
    /// 初始化可通行路线数据
    public init(
        isPathAvailable: Bool,
        safeDepth: Float,
        recommendedHeading: Float,
        waypoints: [RouteWaypoint]
    ) {
        self.isPathAvailable = isPathAvailable
        self.safeDepth = safeDepth
        self.recommendedHeading = recommendedHeading
        self.waypoints = waypoints
    }
    
    /// 默认不可通行状态
    public static var blocked: PassableRouteData {
        PassableRouteData(
            isPathAvailable: false,
            safeDepth: 0.0,
            recommendedHeading: 0.0,
            waypoints: []
        )
    }
}
