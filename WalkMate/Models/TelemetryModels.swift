//
//  TelemetryModels.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-22.
//

import Foundation
import simd

/// 相机生命周期连接状态枚举
public enum CameraConnectionState: String, Codable, Sendable {
    case noConnection = "未连接"
    case connecting   = "连接中"
    case connected    = "已连接"
    case failed       = "连接失败"
}

/// 相机传感器与实时流遥测数据实体
public struct SensorTelemetry: Codable, Equatable, Sendable {
    /// 当前相机连接状态
    public let connectionState: CameraConnectionState
    /// 实时推流帧率 (FPS)
    public let fps: Float
    /// 俯仰角 (Pitch, 绕X轴, 单位: 度)
    public let pitch: Float
    /// 翻滚角 (Roll, 绕Z轴, 单位: 度)
    public let roll: Float
    /// 偏航角 (Yaw, 绕Y轴, 单位: 度)
    public let yaw: Float
    /// 三维线性加速度向量 (x, y, z, 单位: m/s²)
    public let acceleration: SIMD3<Float>
    /// 采样毫秒时间戳
    public let timestampMs: Int64
    
    /// 初始化遥测指标
    public init(
        connectionState: CameraConnectionState,
        fps: Float,
        pitch: Float,
        roll: Float,
        yaw: Float,
        acceleration: SIMD3<Float>,
        timestampMs: Int64
    ) {
        self.connectionState = connectionState
        self.fps = fps
        self.pitch = pitch
        self.roll = roll
        self.yaw = yaw
        self.acceleration = acceleration
        self.timestampMs = timestampMs
    }
    
    /// 默认离线遥测数据
    public static var offline: SensorTelemetry {
        SensorTelemetry(
            connectionState: .noConnection,
            fps: 0.0,
            pitch: 0.0,
            roll: 0.0,
            yaw: 0.0,
            acceleration: SIMD3<Float>(0, 0, 0),
            timestampMs: 0
        )
    }
}

/// 用户当前运动状态分类枚举
public enum UserMotionState: String, Codable, Sendable {
    /// 前行中
    case forward = "前行"
    /// 静止 / 驻足观察
    case stationary = "静止"
    /// 正在后退 / 有后退起步倾向（激活倒车雷达视角）
    case backward = "后退"
}

/// 障碍物威胁级别枚举
public enum ThreatLevel: String, Codable, Sendable {
    case safe    = "安全"
    case warning = "警告"
    case danger  = "危险"
}
