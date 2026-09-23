//
//  ObstacleTracker.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-23.
//

import Foundation
import simd

// MARK: - 3D 多目标跨帧追踪器

/// 负责跨帧维持障碍物持久唯一 Tracking ID、解算相对速度矢量与接近速率、动态实体分类升级及 5 帧遮挡状态恢复
public final class ObstacleTracker {
    
    /// 3D 空间欧氏距离关联门限 (米, 默认 0.6m)
    private let maxDistanceThreshold: Float
    /// 最多容许的连续丢失遮挡帧数 (默认 5 帧, 约 500ms)
    private let maxOcclusionFrames: Int
    /// 全局自增持久跟踪 ID 发号器
    private var nextTrackId: Int = 1
    
    // MARK: - 内部追踪航迹实体
    
    private struct Track {
        let id: Int
        var position: SIMD3<Float>
        var lastTimestampMs: Int64
        var velocity: SIMD3<Float>
        var approachRate: Float
        var category: ObstacleCategory
        var size: SIMD3<Float>
        var missedFrames: Int
        var isDynamic: Bool
    }
    
    /// 活跃与缓存中的所有航迹列表
    private var activeTracks: [Track] = []
    
    /// 初始化追踪器
    /// - Parameters:
    ///   - maxDistanceThreshold: 空间关联距离门限
    ///   - maxOcclusionFrames: 遮挡缓存最大帧数
    public init(
        maxDistanceThreshold: Float = 0.6,
        maxOcclusionFrames: Int = 5
    ) {
        self.maxDistanceThreshold = maxDistanceThreshold
        self.maxOcclusionFrames = maxOcclusionFrames
    }
    
    // MARK: - 核心追踪算法
    
    /// 对当前帧新检测到的障碍物集合执行数据关联、运动学滤波与 ID 分配
    /// - Parameters:
    ///   - detected: 当前帧检测出的未分配 ID 的障碍物列表
    ///   - timestampMs: 当前帧采样毫秒时间戳
    /// - Returns: 赋予稳定 ID、计算速度矢量并排好序的障碍物列表
    public func track(
        obstacles detected: [ObstacleItem],
        timestampMs: Int64
    ) -> [ObstacleItem] {
        var matchedDetectionIndices = Set<Int>()
        var matchedTrackIndices = Set<Int>()
        var trackedObstacles: [ObstacleItem] = []
        
        // 1. 构建候选匹配对并计算 3D 欧氏距离
        struct MatchCandidate {
            let trackIndex: Int
            let detectionIndex: Int
            let distance: Float
        }
        
        var candidates: [MatchCandidate] = []
        for (tIdx, track) in activeTracks.enumerated() {
            // 基于前序速度推算当前预测位置
            let dt = max(0.001, Float(timestampMs - track.lastTimestampMs) / 1000.0)
            let predictedPos = track.position + track.velocity * dt
            // 自适应关联门限：基础 0.6m，当时间间隔较大且航迹尚无初速度时，允许随时间自适应放宽以匹配高速目标
            let dynamicThreshold = (track.velocity == SIMD3<Float>(0, 0, 0))
                ? max(maxDistanceThreshold, min(1.2, maxDistanceThreshold + 1.2 * dt))
                : maxDistanceThreshold
            
            for (dIdx, obs) in detected.enumerated() {
                let dist = simd_distance(predictedPos, obs.position)
                if dist <= dynamicThreshold {
                    candidates.append(MatchCandidate(trackIndex: tIdx, detectionIndex: dIdx, distance: dist))
                }
            }
        }
        
        // 2. 贪心最近邻数据关联 (按欧氏距离升序匹配)
        candidates.sort { $0.distance < $1.distance }
        for match in candidates {
            if matchedTrackIndices.contains(match.trackIndex) || matchedDetectionIndices.contains(match.detectionIndex) {
                continue
            }
            matchedTrackIndices.insert(match.trackIndex)
            matchedDetectionIndices.insert(match.detectionIndex)
            
            // 更新该航迹
            var track = activeTracks[match.trackIndex]
            let obs = detected[match.detectionIndex]
            let dt = max(0.001, Float(timestampMs - track.lastTimestampMs) / 1000.0)
            
            // 计算瞬时速度矢量
            let instantaneousVelocity = (obs.position - track.position) / dt
            let smoothedVelocity = (track.velocity == SIMD3<Float>(0, 0, 0))
                ? instantaneousVelocity
                : (track.velocity * 0.4 + instantaneousVelocity * 0.6)
            
            // 计算标量相对接近速率 (迎面逼近为正, 远离为负)
            let prevDist = simd_length(track.position)
            let currDist = simd_length(obs.position)
            let instantaneousApproachRate = (prevDist - currDist) / dt
            
            // 判定是否具备显著动态实体特征 (|v_approach| > 0.4m/s 或合速度 > 0.4m/s)
            let isSpeedExceeded = abs(instantaneousApproachRate) > 0.4 || simd_length(smoothedVelocity) > 0.4
            let updatedDynamic = track.isDynamic || isSpeedExceeded
            let finalCategory: ObstacleCategory = updatedDynamic ? .dynamicEntity : obs.category
            
            // 若为高速逼近目标，动态提升其威胁等级至 danger
            var finalThreat = obs.threatLevel
            var finalScore = obs.priorityScore
            if updatedDynamic && instantaneousApproachRate > 0.4 {
                finalThreat = .danger
                finalScore += 15.0
            }
            
            track.position = obs.position
            track.lastTimestampMs = timestampMs
            track.velocity = smoothedVelocity
            track.approachRate = instantaneousApproachRate
            track.category = finalCategory
            track.size = obs.size
            track.missedFrames = 0
            track.isDynamic = updatedDynamic
            activeTracks[match.trackIndex] = track
            
            let trackedItem = ObstacleItem(
                id: track.id,
                position: obs.position,
                distance: obs.distance,
                azimuth: obs.azimuth,
                elevation: obs.elevation,
                size: obs.size,
                category: finalCategory,
                relativeVelocity: smoothedVelocity,
                approachRate: instantaneousApproachRate,
                priorityScore: finalScore,
                threatLevel: finalThreat,
                isRearHazard: obs.isRearHazard
            )
            trackedObstacles.append(trackedItem)
        }
        
        // 3. 处理未匹配上的新检出障碍物 (分配全新持久 ID)
        for (dIdx, obs) in detected.enumerated() {
            if matchedDetectionIndices.contains(dIdx) { continue }
            
            let newId = nextTrackId
            nextTrackId += 1
            
            let newTrack = Track(
                id: newId,
                position: obs.position,
                lastTimestampMs: timestampMs,
                velocity: SIMD3<Float>(0, 0, 0),
                approachRate: 0.0,
                category: obs.category,
                size: obs.size,
                missedFrames: 0,
                isDynamic: false
            )
            activeTracks.append(newTrack)
            
            let trackedItem = ObstacleItem(
                id: newId,
                position: obs.position,
                distance: obs.distance,
                azimuth: obs.azimuth,
                elevation: obs.elevation,
                size: obs.size,
                category: obs.category,
                relativeVelocity: SIMD3<Float>(0, 0, 0),
                approachRate: 0.0,
                priorityScore: obs.priorityScore,
                threatLevel: obs.threatLevel,
                isRearHazard: obs.isRearHazard
            )
            trackedObstacles.append(trackedItem)
        }
        
        // 4. 处理未匹配上的老航迹 (进入遮挡容差缓存，连续丢失超过 5 帧则彻底清除)
        var survivingTracks: [Track] = []
        for (tIdx, var track) in activeTracks.enumerated() {
            if !matchedTrackIndices.contains(tIdx) {
                track.missedFrames += 1
                if track.missedFrames <= maxOcclusionFrames {
                    // 在容差期内维持预测推算位移
                    let dt = max(0.001, Float(timestampMs - track.lastTimestampMs) / 1000.0)
                    track.position += track.velocity * dt
                    track.lastTimestampMs = timestampMs
                    survivingTracks.append(track)
                }
            } else {
                survivingTracks.append(track)
            }
        }
        activeTracks = survivingTracks
        
        // 5. 按威胁评分降序输出最终全景障碍物列表
        trackedObstacles.sort { $0.priorityScore > $1.priorityScore }
        return trackedObstacles
    }
    
    /// 重置跟踪器内部状态
    public func reset() {
        activeTracks.removeAll()
        nextTrackId = 1
    }
}
