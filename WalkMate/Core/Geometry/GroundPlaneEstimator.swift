//
//  GroundPlaneEstimator.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-23.
//

import Foundation
import simd

// MARK: - 地面拟合结果实体

/// 纯动态地平面拟合解算结果
public struct GroundPlaneResult: Sendable {
    /// 地平面方程系数 (A, B, C, D)，满足 Ax + By + Cz + D = 0，法向量 (A, B, C) 归一化且指向垂直上方
    public let groundPlane: SIMD4<Float>
    /// 解算出的相机当前实际离地高度 (米)
    public let cameraHeight: Float
    /// 剥离平整路面后的有效障碍物点云
    public let nonGroundPoints: [SIMD3<Float>]
    /// 识别为平整地面的点数量
    public let groundPointsCount: Int
    
    /// 初始化地面拟合结果
    public init(
        groundPlane: SIMD4<Float>,
        cameraHeight: Float,
        nonGroundPoints: [SIMD3<Float>],
        groundPointsCount: Int
    ) {
        self.groundPlane = groundPlane
        self.cameraHeight = cameraHeight
        self.nonGroundPoints = nonGroundPoints
        self.groundPointsCount = groundPointsCount
    }
}

// MARK: - 纯动态地面估计器

/// 负责对重力对齐后的空间点云执行快速 RANSAC 平面拟合
/// 动态解算相机离地高度并剥离平整路面 (|d| <= 0.08m)，无需固定高度先验
public final class GroundPlaneEstimator: Sendable {
    
    /// RANSAC 采样迭代次数 (默认 30 次，耗时约 2ms)
    private let iterations: Int
    /// 判定为地面的距离容差 (米, 默认 0.05m)
    private let inlierDistanceThreshold: Float
    /// 最终剥离地面的垂直容差 (米, 默认 0.08m)
    private let groundStripMargin: Float
    
    /// 初始化地面估计器
    /// - Parameters:
    ///   - iterations: RANSAC 迭代次数
    ///   - inlierDistanceThreshold: 内点阈值
    ///   - groundStripMargin: 地面滤除边界阈值
    public init(
        iterations: Int = 30,
        inlierDistanceThreshold: Float = 0.05,
        groundStripMargin: Float = 0.08
    ) {
        self.iterations = iterations
        self.inlierDistanceThreshold = inlierDistanceThreshold
        self.groundStripMargin = groundStripMargin
    }
    
    // MARK: - 核心拟合与地面剥离流程
    
    /// 从重力对齐点云中拟合地平面并提取障碍物点
    /// - Parameter points: 经重力垂直校准后的全量点云
    /// - Returns: 地面拟合参数与剥离后的非地面点云
    public func estimateGround(from points: [SIMD3<Float>]) -> GroundPlaneResult {
        // 1. 过滤下半球候选地面点 (y < 0 且有效距离在 0.3m ~ 6.0m 内)
        var groundCandidates: [SIMD3<Float>] = []
        groundCandidates.reserveCapacity(points.count / 2)
        
        for p in points {
            if p.y < 0 && p.z != 0 {
                let dist = simd_length(p)
                if dist >= 0.3 && dist <= 6.0 {
                    groundCandidates.append(p)
                }
            }
        }
        
        // 若下半球候选点过少，采用默认先验兜底 (高度 1.4 米, y = -1.4)
        guard groundCandidates.count >= 20 else {
            Log.warning("下半球候选点不足 (\(groundCandidates.count))，启用默认 1.4m 高度先验", category: .perception)
            return fallbackResult(for: points, defaultHeight: 1.4)
        }
        
        // 2. 执行 RANSAC 拟合寻找最大支撑平面
        var bestPlane = SIMD4<Float>(0, 1, 0, 1.4)
        var maxInliers = 0
        let candidateCount = groundCandidates.count
        
        for _ in 0..<iterations {
            let i1 = Int.random(in: 0..<candidateCount)
            let i2 = Int.random(in: 0..<candidateCount)
            let i3 = Int.random(in: 0..<candidateCount)
            if i1 == i2 || i2 == i3 || i1 == i3 { continue }
            
            let p1 = groundCandidates[i1]
            let p2 = groundCandidates[i2]
            let p3 = groundCandidates[i3]
            
            // 计算法向量
            let v1 = p2 - p1
            let v2 = p3 - p1
            var normal = simd_cross(v1, v2)
            let nLen = simd_length(normal)
            if nLen < 1e-4 { continue }
            normal /= nLen
            
            // 地面法向量必须主要朝上 (+Y 轴方向，容差 |ny| >= 0.75)
            if normal.y < 0 {
                normal = -normal
            }
            if normal.y < 0.75 { continue }
            
            // 平面常数 D = -(normal · p1)
            let d = -simd_dot(normal, p1)
            
            // 统计该平面的内点数
            var currentInliers = 0
            for p in groundCandidates {
                let distToPlane = abs(simd_dot(normal, p) + d)
                if distToPlane <= inlierDistanceThreshold {
                    currentInliers += 1
                }
            }
            
            if currentInliers > maxInliers {
                maxInliers = currentInliers
                bestPlane = SIMD4<Float>(normal.x, normal.y, normal.z, d)
            }
        }
        
        // 3. 计算实际离地高度 (相机原点 (0,0,0) 到平面的垂距)
        let normal = SIMD3<Float>(bestPlane.x, bestPlane.y, bestPlane.z)
        let cameraHeight = abs(bestPlane.w) / simd_length(normal)
        
        // 4. 剥离平整路面：点到地面距离 |d| <= groundStripMargin 的过滤掉
        var nonGround: [SIMD3<Float>] = []
        var groundCount = 0
        nonGround.reserveCapacity(points.count)
        
        for p in points {
            // 跳过无效原点
            if p.x == 0 && p.y == 0 && p.z == 0 { continue }
            
            let distToPlane = simd_dot(normal, p) + bestPlane.w
            if abs(distToPlane) <= groundStripMargin {
                groundCount += 1
            } else {
                nonGround.append(p)
            }
        }
        
        return GroundPlaneResult(
            groundPlane: bestPlane,
            cameraHeight: cameraHeight,
            nonGroundPoints: nonGround,
            groundPointsCount: groundCount
        )
    }
    
    // MARK: - 兜底方案
    
    private func fallbackResult(for points: [SIMD3<Float>], defaultHeight: Float) -> GroundPlaneResult {
        let normal = SIMD3<Float>(0, 1, 0)
        let d = defaultHeight
        let plane = SIMD4<Float>(normal.x, normal.y, normal.z, d)
        
        var nonGround: [SIMD3<Float>] = []
        var groundCount = 0
        for p in points {
            if p.x == 0 && p.y == 0 && p.z == 0 { continue }
            let dist = p.y + defaultHeight
            if abs(dist) <= groundStripMargin {
                groundCount += 1
            } else {
                nonGround.append(p)
            }
        }
        return GroundPlaneResult(
            groundPlane: plane,
            cameraHeight: defaultHeight,
            nonGroundPoints: nonGround,
            groundPointsCount: groundCount
        )
    }
}
