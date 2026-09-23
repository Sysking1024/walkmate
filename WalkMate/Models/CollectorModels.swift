//
//  CollectorModels.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-23.
//

import Foundation
import simd

// MARK: - 三维空间几何与姿态 Codable 实体

/// 兼容 Codable 的三维空间向量记录
public struct SIMD3Record: Codable, Sendable, Equatable {
    /// X 轴坐标 (米)
    public let x: Float
    /// Y 轴坐标 (米)
    public let y: Float
    /// Z 轴坐标 (米)
    public let z: Float
    
    /// 初始化三维向量记录
    public init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
    
    /// 从原生 SIMD3<Float> 构造
    public init(_ vector: SIMD3<Float>) {
        self.x = vector.x
        self.y = vector.y
        self.z = vector.z
    }
    
    /// 转换为系统原生 SIMD3<Float>
    public func toSIMD3() -> SIMD3<Float> {
        return SIMD3<Float>(x, y, z)
    }
}

/// 兼容 Codable 的四元数姿态记录 (对齐 simd_quatf)
public struct QuaternionRecord: Codable, Sendable, Equatable {
    /// 虚部分量 X
    public let x: Float
    /// 虚部分量 Y
    public let y: Float
    /// 虚部分量 Z
    public let z: Float
    /// 实部分量 W
    public let w: Float
    
    /// 初始化四元数记录
    public init(x: Float, y: Float, z: Float, w: Float) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }
    
    /// 从原生 simd_quatf 构造
    public init(_ quat: simd_quatf) {
        self.x = quat.vector.x
        self.y = quat.vector.y
        self.z = quat.vector.z
        self.w = quat.vector.w
    }
    
    /// 转换为系统原生 simd_quatf
    public func toQuatf() -> simd_quatf {
        return simd_quatf(ix: x, iy: y, iz: z, r: w)
    }
}

/// 兼容 Codable 的欧拉角记录 (角度制)
public struct EulerAnglesRecord: Codable, Sendable, Equatable {
    /// 横滚角 Roll (度)
    public let roll: Float
    /// 俯仰角 Pitch (度)
    public let pitch: Float
    /// 偏航角 Yaw (度)
    public let yaw: Float
    
    /// 初始化欧拉角记录
    public init(roll: Float, pitch: Float, yaw: Float) {
        self.roll = roll
        self.pitch = pitch
        self.yaw = yaw
    }
}

/// 兼容 Codable 的障碍物空间快照记录
public struct ObstacleRecord: Codable, Sendable, Equatable {
    /// 障碍物时序跟踪 ID
    public let id: Int
    /// 障碍物中心三维坐标 (米)
    public let position: SIMD3Record
    /// 障碍物三维包围盒尺寸 (长宽高, 米)
    public let size: SIMD3Record
    /// 相对相机距离 (米)
    public let distance: Float
    /// 方位角 (度, 负为左, 正为右)
    public let azimuth: Float
    /// 障碍物类型分类名称
    public let category: String
    
    /// 初始化障碍物记录
    public init(
        id: Int,
        position: SIMD3Record,
        size: SIMD3Record,
        distance: Float,
        azimuth: Float,
        category: String
    ) {
        self.id = id
        self.position = position
        self.size = size
        self.distance = distance
        self.azimuth = azimuth
        self.category = category
    }
}

// MARK: - 会话元数据与帧时序遥测实体

/// 采集会话的全局元信息实体
public struct SessionMetadata: Codable, Sendable, Equatable {
    /// 唯一会话标识符 (例如: "session_20260923_183015")
    public let sessionId: String
    /// 会话开始时间戳 (毫秒)
    public let startTimeMs: Int64
    /// 会话结束时间戳 (毫秒, 录制中为 nil)
    public var endTimeMs: Int64?
    /// 录制持续时长 (秒)
    public var durationSeconds: Double
    /// 累计记录的遥测帧总数
    public var totalTelemetryFrames: Int
    /// 累计记录的图像快照总数
    public var totalImageSnapshots: Int
    /// 采集设备信息 (例如: "iPhone 16, iOS 18.1")
    public let deviceInfo: String
    /// 应用版本号
    public let appVersion: String
    /// 算法关键初始参数快照 (供离线对齐基准)
    public let algorithmConfig: [String: String]
    
    /// 初始化会话元信息
    public init(
        sessionId: String,
        startTimeMs: Int64,
        endTimeMs: Int64? = nil,
        durationSeconds: Double = 0,
        totalTelemetryFrames: Int = 0,
        totalImageSnapshots: Int = 0,
        deviceInfo: String = "iPhone",
        appVersion: String = "1.0.0",
        algorithmConfig: [String: String] = [:]
    ) {
        self.sessionId = sessionId
        self.startTimeMs = startTimeMs
        self.endTimeMs = endTimeMs
        self.durationSeconds = durationSeconds
        self.totalTelemetryFrames = totalTelemetryFrames
        self.totalImageSnapshots = totalImageSnapshots
        self.deviceInfo = deviceInfo
        self.appVersion = appVersion
        self.algorithmConfig = algorithmConfig
    }
}

/// 单一感知帧的全量时序遥测快照 (流式写入 JSONL)
public struct FrameTelemetryRecord: Codable, Sendable, Equatable {
    /// 毫秒级对齐时间戳 (自 1970 纪元毫秒数，对齐 PanoramicFrame.timestampMs)
    public let timestampMs: Int64
    /// 视频帧连续序号
    public let frameIndex: Int
    
    // MARK: - 传感器与几何姿态
    /// 相机 IMU 绝对姿态四元数 (用于高保真重力校准与点云反算)
    public let quaternion: QuaternionRecord
    /// 相机 IMU 欧拉角 (度: roll, pitch, yaw)
    public let eulerAngles: EulerAnglesRecord
    /// 相机 IMU 瞬时线性加速度向量 (m/s^2)
    public let acceleration: SIMD3Record
    /// RANSAC 地面拟合平面方程系数 [A, B, C, D] (Ax + By + Cz + D = 0)
    public let groundPlane: [Float]
    /// 估算的相机离地高度 (米)
    public let cameraHeight: Float
    
    // MARK: - 障碍物检测与过滤输出
    /// 原始检出的所有障碍物列表
    public let rawObstacles: [ObstacleRecord]
    /// 经过业务前向扇区 (|azimuth| <= 65° & distance <= 1.0m) 过滤后的危险障碍物列表
    public let hazardObstacles: [ObstacleRecord]
    /// 触发音频告警的最近目标坐标 (若无则为 nil)
    public let activeObstacleTarget: SIMD3Record?
    
    // MARK: - 路径规划与可通行性输出
    /// 通行走廊是否开通
    public let isPassable: Bool
    /// 安全前向纵深 (米)
    public let safeDepth: Float
    /// 推荐起步偏航角 (度)
    public let recommendedHeading: Float
    /// 提取出的航路点序列 (3D 坐标列表)
    public let waypoints: [SIMD3Record]
    /// 驱动前方领路脚步声的首航路点相对坐标 (若前方受阻则为 nil)
    public let activeNavigationTarget: SIMD3Record?
    
    // MARK: - 性能度量
    /// 该帧推理与几何端到端计算耗时 (毫秒)
    public let processingLatencyMs: Double
    /// 是否存在伴随保存的图像快照 (用于回放时快速索引图片)
    public let hasImageSnapshot: Bool
    
    /// 初始化帧遥测快照
    public init(
        timestampMs: Int64,
        frameIndex: Int,
        quaternion: QuaternionRecord,
        eulerAngles: EulerAnglesRecord,
        acceleration: SIMD3Record,
        groundPlane: [Float],
        cameraHeight: Float,
        rawObstacles: [ObstacleRecord],
        hazardObstacles: [ObstacleRecord],
        activeObstacleTarget: SIMD3Record?,
        isPassable: Bool,
        safeDepth: Float,
        recommendedHeading: Float,
        waypoints: [SIMD3Record],
        activeNavigationTarget: SIMD3Record?,
        processingLatencyMs: Double,
        hasImageSnapshot: Bool
    ) {
        self.timestampMs = timestampMs
        self.frameIndex = frameIndex
        self.quaternion = quaternion
        self.eulerAngles = eulerAngles
        self.acceleration = acceleration
        self.groundPlane = groundPlane
        self.cameraHeight = cameraHeight
        self.rawObstacles = rawObstacles
        self.hazardObstacles = hazardObstacles
        self.activeObstacleTarget = activeObstacleTarget
        self.isPassable = isPassable
        self.safeDepth = safeDepth
        self.recommendedHeading = recommendedHeading
        self.waypoints = waypoints
        self.activeNavigationTarget = activeNavigationTarget
        self.processingLatencyMs = processingLatencyMs
        self.hasImageSnapshot = hasImageSnapshot
    }
}

// MARK: - 视图展示模型

/// 历史会话展示项 (供 SwiftUI 会话管理抽屉列表展示)
public struct SessionSummaryItem: Identifiable, Sendable, Equatable {
    /// 唯一标识即会话 ID
    public var id: String { sessionId }
    /// 会话唯一标识符
    public let sessionId: String
    /// 会话文件夹本地沙盒路径
    public let folderURL: URL
    /// 会话创建时间
    public let createdAt: Date
    /// 格式化录制时长 (例如: "01:25")
    public let durationFormatted: String
    /// 格式化磁盘占用 (例如: "12.4 MB")
    public let sizeFormatted: String
    /// 总遥测帧数
    public let totalFrames: Int
    /// 当前是否处于正在录制中状态
    public let isCurrentlyRecording: Bool
    
    /// 初始化展示项
    public init(
        sessionId: String,
        folderURL: URL,
        createdAt: Date,
        durationFormatted: String,
        sizeFormatted: String,
        totalFrames: Int,
        isCurrentlyRecording: Bool
    ) {
        self.sessionId = sessionId
        self.folderURL = folderURL
        self.createdAt = createdAt
        self.durationFormatted = durationFormatted
        self.sizeFormatted = sizeFormatted
        self.totalFrames = totalFrames
        self.isCurrentlyRecording = isCurrentlyRecording
    }
}
