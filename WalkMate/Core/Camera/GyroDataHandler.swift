//
//  GyroDataHandler.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-22.
//

import Foundation
import INSCameraSDK
import simd

/// 六轴传感器数据处理器协议
public protocol GyroDataHandlerProtocol: AnyObject {
    /// 最新的传感器姿态与加速度数据到达回调
    var onGyroParsed: ((INSGyroRawItem) -> Void)? { get set }
    
    /// 获取当前最新的相机姿态四元数（用于重力对齐）
    var currentOrientation: simd_quatf { get }
    
    /// 获取当前最新的线性加速度向量
    var currentAcceleration: SIMD3<Float> { get }
    
    /// 获取当前最新的姿态欧拉角（俯仰角、翻滚角、偏航角，单位：度）
    var currentEulerAngles: (pitch: Float, roll: Float, yaw: Float) { get }
    
    /// 获取与指定毫秒时间戳最接近的姿态与加速度
    func attitude(at timestampMs: Int64) -> (orientation: simd_quatf, acceleration: SIMD3<Float>)
}

/// 基于 Insta360 官方 INSCameraSessionGyroDelegate 的六轴数据同步器
/// 负责实时解析 INSGyroRawItem，计算相机倾角姿态与重力对齐四元数
public final class GyroDataHandler: NSObject, GyroDataHandlerProtocol {
    
    // 线程安全锁
    private let lock = NSLock()
    
    // 最新接收的陀螺仪条目
    private var latestItem: INSGyroRawItem?
    
    // 环形缓冲队列（保存最近 100 个采样点，用于时间戳匹配，零磁盘开销）
    private var ringBuffer: [(timestampMs: Int64, orientation: simd_quatf, acceleration: SIMD3<Float>)] = []
    private let maxBufferSize = 100
    
    // 当前姿态四元数
    public var currentOrientation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    
    // 当前加速度向量
    public var currentAcceleration: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    
    // 当前欧拉角 (度)
    public var currentEulerAngles: (pitch: Float, roll: Float, yaw: Float) = (0.0, 0.0, 0.0)
    
    // 数据到达回调
    public var onGyroParsed: ((INSGyroRawItem) -> Void)?
    
    public override init() {
        super.init()
    }
    
    /// 根据时间戳查询最贴近的姿态四元数与加速度
    public func attitude(at timestampMs: Int64) -> (orientation: simd_quatf, acceleration: SIMD3<Float>) {
        lock.lock()
        defer { lock.unlock() }
        
        guard !ringBuffer.isEmpty else {
            return (currentOrientation, currentAcceleration)
        }
        
        // 查找时间戳差值最小的条目
        var closest = ringBuffer[0]
        var minDiff = abs(closest.timestampMs - timestampMs)
        
        for entry in ringBuffer {
            let diff = abs(entry.timestampMs - timestampMs)
            if diff < minDiff {
                minDiff = diff
                closest = entry
            }
        }
        
        return (closest.orientation, closest.acceleration)
    }
    
    /// 处理单条陀螺仪与加速度项并更新内部姿态
    public func processGyroItem(_ item: INSGyroRawItem) {
        lock.lock()
        defer { lock.unlock() }
        
        self.latestItem = item
        
        // 提取三轴加速度 (米/秒²)
        let ax = Float(item.accelX)
        let ay = Float(item.accelY)
        let az = Float(item.accelZ)
        let accel = SIMD3<Float>(ax, ay, az)
        self.currentAcceleration = accel
        
        // 利用重力加速度向量计算俯仰角 (Pitch) 与翻滚角 (Roll)
        // 设相机静止或匀速运动时，加速度主要由地球重力产生 (约 9.8 m/s²)
        let pitchRad = atan2(-ax, sqrt(ay * ay + az * az))
        let rollRad = atan2(ay, az)
        
        let pitchDeg = pitchRad * 180.0 / .pi
        let rollDeg = rollRad * 180.0 / .pi
        // 偏航角基于角速度积分或默认以初始朝向为 0 度
        let yawDeg: Float = 0.0
        
        self.currentEulerAngles = (pitchDeg, rollDeg, yawDeg)
        
        // 计算重力对齐四元数：将相机的倾斜旋转对齐到标准世界系（使 Y 轴反向平行于重力方向垂直向上）
        let pitchQuat = simd_quatf(angle: pitchRad, axis: SIMD3<Float>(1, 0, 0))
        let rollQuat = simd_quatf(angle: rollRad, axis: SIMD3<Float>(0, 0, 1))
        let orientation = rollQuat * pitchQuat
        self.currentOrientation = orientation
        
        // 存入环形缓冲区
        ringBuffer.append((timestampMs: item.timestamp, orientation: orientation, acceleration: accel))
        if ringBuffer.count > maxBufferSize {
            ringBuffer.removeFirst()
        }
        
        onGyroParsed?(item)
    }
}

// MARK: - INSCameraSessionGyroDelegate 官方 SDK 回调
extension GyroDataHandler: INSCameraSessionGyroDelegate {
    
    /// 官方 SDK 回调解析后的陀螺仪与加速度列表
    public func onParsedGyroData(_ gyroItems: NSMutableArray, timestampMs: Int64) {
        for element in gyroItems {
            if let gyroItem = element as? INSGyroRawItem, gyroItem.isValid() {
                processGyroItem(gyroItem)
            }
        }
    }
    
    /// 原始陀螺仪数据包备用回调
    public func onRawGyroData(_ rawData: Data, timestampMs: Int64) {
        // 可选保留供底层未解析数据包追踪
    }
}
