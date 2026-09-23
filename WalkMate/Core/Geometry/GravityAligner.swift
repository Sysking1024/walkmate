//
//  GravityAligner.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-23.
//

import Foundation
import simd

// MARK: - 重力垂直坐标对齐器

/// 负责利用六轴传感器姿态（四元数或加速度矢量）对空间点云进行重力对齐
/// 保证输出点云的 +Y 轴严格垂直向上反平行于重力，X-Z 轴构成水平地平面
public final class GravityAligner: Sendable {
    
    /// 初始化重力对齐器
    public init() {}
    
    // MARK: - 基于四元数姿态的点云对齐
    
    /// 利用相机姿态四元数旋转点云，消除穿戴晃动与倾斜
    /// - Parameters:
    ///   - points: 原始相机局部相对点云
    ///   - orientation: 相机当前姿态四元数
    /// - Returns: 重力对齐后的空间点云
    public func align(points: [SIMD3<Float>], orientation: simd_quatf) -> [SIMD3<Float>] {
        // 取姿态的逆旋转 (共轭四元数) 消除倾斜
        let correctionQuat = orientation.inverse
        
        var aligned = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: points.count)
        for i in 0..<points.count {
            aligned[i] = correctionQuat.act(points[i])
        }
        return aligned
    }
    
    // MARK: - 基于加速度矢量的动态重力对齐
    
    /// 根据六轴 IMU 的加速度矢量计算重力对齐四元数并校准点云
    /// - Parameters:
    ///   - points: 原始点云
    ///   - acceleration: 三维线性加速度矢量
    /// - Returns: 重力对齐后的空间点云
    public func align(points: [SIMD3<Float>], acceleration: SIMD3<Float>) -> [SIMD3<Float>] {
        let accelNorm = simd_length(acceleration)
        guard accelNorm > 1e-4 else {
            // 加速度过小或失重时保持原点云不变
            return points
        }
        
        // 测得的重力加速度方向 (通常指向地心，即理想水平状态下为 (0, -1, 0))
        let measuredDown = simd_normalize(acceleration)
        let targetDown = SIMD3<Float>(0, -1, 0)
        
        // 计算从 measuredDown 旋转到 targetDown 的四元数
        let rotationQuat = simd_quaternion(measuredDown, targetDown)
        
        var aligned = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: points.count)
        for i in 0..<points.count {
            aligned[i] = rotationQuat.act(points[i])
        }
        return aligned
    }
}
