//
//  ObstacleDetector.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-23.
//

import Foundation
import simd

// MARK: - 全场景 360° 障碍物检测器

/// 负责从去地面点云中提取空间聚类簇、构建 3D AABB 包围盒、换算极坐标与高程危险源分类
public final class ObstacleDetector: Sendable {
    
    /// 空间网格栅格分辨率 (米，默认 0.2m)
    private let gridCellSize: Float
    /// 聚类有效点数门限 (过滤孤立单点噪波)
    private let minPointsPerCluster: Int
    
    /// 初始化障碍物检测器
    /// - Parameters:
    ///   - gridCellSize: 空间网格聚类分辨率
    ///   - minPointsPerCluster: 单个有效障碍物最小点数门限
    public init(
        gridCellSize: Float = 0.2,
        minPointsPerCluster: Int = 10
    ) {
        self.gridCellSize = gridCellSize
        self.minPointsPerCluster = minPointsPerCluster
    }
    
    // MARK: - 内部聚类中间数据结构
    
    private struct VoxelCell {
        var minBound: SIMD3<Float>
        var maxBound: SIMD3<Float>
        var pointCount: Int
    }
    
    private struct GridKey: Hashable {
        let ix: Int
        let iz: Int
    }
    
    // MARK: - 核心检测方法
    
    /// 从剥离地面后的空间点云与当前相机离地高度中检出 360° 全量障碍物
    /// - Parameters:
    ///   - nonGroundPoints: 剥离地面后的有效点云
    ///   - cameraHeight: 相机当前实际离地高度 (米)
    /// - Returns: 未分配持久跟踪 ID 的障碍物列表
    public func detectObstacles(
        from nonGroundPoints: [SIMD3<Float>],
        cameraHeight: Float
    ) -> [ObstacleItem] {
        guard !nonGroundPoints.isEmpty else { return [] }
        
        // 1. 依据相对高程对非地面点云进行三向分流 (地面凸起、高空悬挂、下沉跌落)
        var groundPoints: [SIMD3<Float>] = []
        var hangingPoints: [SIMD3<Float>] = []
        var dropOffPoints: [SIMD3<Float>] = []
        
        groundPoints.reserveCapacity(nonGroundPoints.count)
        hangingPoints.reserveCapacity(nonGroundPoints.count / 4)
        dropOffPoints.reserveCapacity(nonGroundPoints.count / 4)
        
        for p in nonGroundPoints {
            // 计算相对地面高度: y_rel = p.y - (-cameraHeight) = p.y + cameraHeight
            let yRel = p.y + cameraHeight
            
            if yRel < -0.15 {
                // 地面下沉跌落危险 (台阶、深坑)
                dropOffPoints.append(p)
            } else if yRel > 1.4 {
                // 高空悬挂碰头危险 (悬空树枝、招牌)
                hangingPoints.append(p)
            } else if yRel >= 0.08 {
                // 普通地面凸起障碍物
                groundPoints.append(p)
            }
        }
        
        var detectedObstacles: [ObstacleItem] = []
        
        // 2. 对各类别的点云执行空间网格聚类与 AABB 提取
        detectedObstacles.append(contentsOf: clusterPoints(groundPoints, category: .groundObstacle))
        detectedObstacles.append(contentsOf: clusterPoints(hangingPoints, category: .hangingHazard))
        detectedObstacles.append(contentsOf: clusterPoints(dropOffPoints, category: .dropOffHazard))
        
        // 3. 按综合威胁评分降序排列
        detectedObstacles.sort { $0.priorityScore > $1.priorityScore }
        
        return detectedObstacles
    }
    
    // MARK: - 空间聚类与 AABB 生成算法
    
    /// 将指定类别的点云聚类为一组 AABB 障碍物实体
    private func clusterPoints(
        _ points: [SIMD3<Float>],
        category: ObstacleCategory
    ) -> [ObstacleItem] {
        guard points.count >= minPointsPerCluster else { return [] }
        
        // 1. 将三维点离散化映射到水平二维网格
        var grid: [GridKey: VoxelCell] = [:]
        grid.reserveCapacity(points.count / 5)
        
        for p in points {
            let ix = Int(floor(p.x / gridCellSize))
            let iz = Int(floor(p.z / gridCellSize))
            let key = GridKey(ix: ix, iz: iz)
            
            if var cell = grid[key] {
                cell.minBound = simd_min(cell.minBound, p)
                cell.maxBound = simd_max(cell.maxBound, p)
                cell.pointCount += 1
                grid[key] = cell
            } else {
                grid[key] = VoxelCell(minBound: p, maxBound: p, pointCount: 1)
            }
        }
        
        // 2. 使用广度优先搜索 (BFS) 对相邻有效网格进行连通分量聚类 (8-邻域)
        var visited = Set<GridKey>()
        var obstacles: [ObstacleItem] = []
        
        for (key, cell) in grid {
            if visited.contains(key) { continue }
            
            // 启动连通分量探索
            var queue: [GridKey] = [key]
            visited.insert(key)
            
            var compMin = cell.minBound
            var compMax = cell.maxBound
            var compPoints = cell.pointCount
            
            var head = 0
            while head < queue.count {
                let currentKey = queue[head]
                head += 1
                
                // 搜索 8-邻域
                for dx in -1...1 {
                    for dz in -1...1 {
                        if dx == 0 && dz == 0 { continue }
                        let neighborKey = GridKey(ix: currentKey.ix + dx, iz: currentKey.iz + dz)
                        if visited.contains(neighborKey) { continue }
                        
                        if let neighborCell = grid[neighborKey] {
                            // 高度差在合理范围内可聚合为同一物体 (0.8m)
                            let heightDiff = abs(neighborCell.minBound.y - compMin.y)
                            if heightDiff < 0.8 {
                                visited.insert(neighborKey)
                                queue.append(neighborKey)
                                compMin = simd_min(compMin, neighborCell.minBound)
                                compMax = simd_max(compMax, neighborCell.maxBound)
                                compPoints += neighborCell.pointCount
                            }
                        }
                    }
                }
            }
            
            // 过滤噪点微小聚类
            guard compPoints >= minPointsPerCluster else { continue }
            
            // 3. 构建 AABB 包围盒与中心坐标
            let center = (compMin + compMax) / 2.0
            let rawSize = compMax - compMin
            let size = SIMD3<Float>(
                max(0.1, rawSize.x),
                max(0.1, rawSize.y),
                max(0.1, rawSize.z)
            )
            
            // 4. 换算极坐标几何参数与盲区规约
            let rawDistance = simd_length(center)
            let distance: Float
            let position: SIMD3<Float>
            
            // 超近距离盲区兜底 (< 0.3 米)：统一转换为 0.3 米极近距离输出并调整三维坐标 (Edge Cases / FR-009)
            if rawDistance < 0.3 {
                distance = 0.3
                if rawDistance > 0.0001 {
                    position = (center / rawDistance) * 0.3
                } else {
                    position = SIMD3<Float>(0, 0, -0.3)
                }
            } else {
                distance = rawDistance
                position = center
            }
            
            // 方位偏角 (-180° ~ +180°): iOS 空间音频右手系中 +X 为右, -Z 为前向
            // 前向 (0, 0, -z) 对应 0°, 右方 (+x, 0, 0) 对应 +90°, 左方 (-x, 0, 0) 对应 -90°
            let azimuth = atan2(position.x, -position.z) * (180.0 / .pi)
            
            // 垂直仰角
            let horizontalDistance = sqrt(position.x * position.x + position.z * position.z)
            let elevation = atan2(position.y, max(horizontalDistance, 0.001)) * (180.0 / .pi)
            
            // 是否处于使用者身后的视野 (+Z 轴或偏角绝对值 > 90°)
            let isRear = position.z > 0 || abs(azimuth) > 90.0
            
            // 5. 超近距离盲区兜底与威胁评级解算
            let effectiveDistance = max(distance, 0.3)
            let threatLevel: ThreatLevel
            if distance <= 0.35 {
                // 贴身盲区赋予最高 danger 等级
                threatLevel = .danger
            } else if distance <= 1.2 && !isRear {
                threatLevel = .danger
            } else if category == .dropOffHazard && distance <= 2.0 {
                // 跌落深坑即使在 2 米内亦属极度危险
                threatLevel = .danger
            } else if distance <= 2.5 && !isRear {
                threatLevel = .warning
            } else {
                threatLevel = .safe
            }
            
            // 6. 综合威胁优先级评分
            var score = 10.0 / effectiveDistance
            if category == .dropOffHazard { score += 5.0 }
            if threatLevel == .danger { score += 10.0 }
            if threatLevel == .warning { score += 3.0 }
            if isRear { score *= 0.5 }
            
            let item = ObstacleItem(
                id: 0, // 初始未追踪 ID
                position: position,
                distance: distance,
                azimuth: azimuth,
                elevation: elevation,
                size: size,
                category: category,
                relativeVelocity: SIMD3<Float>(0, 0, 0),
                approachRate: 0.0,
                priorityScore: score,
                threatLevel: threatLevel,
                isRearHazard: isRear
            )
            obstacles.append(item)
        }
        
        return obstacles
    }
}
