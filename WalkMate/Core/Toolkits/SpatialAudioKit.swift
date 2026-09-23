//
//  SpatialAudioKit.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-23.
//

import Foundation
import simd

// MARK: - 空间音频与空间几何转换工具箱

/// 纯计算无状态工具箱，提供钟表逆空间编码、iOS 原生 3D 音频声源锚点、双声道声相降级与几何净空碰撞检测纯函数
/// 严格遵守纯函数约束：零音频硬件播放、零 AVAudioSession 状态配置与抢占
public struct SpatialAudioKit: Sendable {
    
    // MARK: - 1. 钟表方位逆空间编码 (视障国际标准语言)
    
    /// 将极坐标方位换算为适合 VoiceOver 或 TTS 朗读的标准钟表点位文案
    /// - Parameters:
    ///   - azimuth: 水平偏航角 (-180° ~ +180°, 0° 为正前方)
    ///   - distance: 直线距离 (米)
    ///   - elevation: 垂直仰角 (度, 负值为低矮, 正值为悬挂)
    /// - Returns: 包含钟点 (1~12)、距离及中文描述的结构化数据包
    public static func toClockDirection(
        azimuth: Float,
        distance: Float,
        elevation: Float
    ) -> ClockPromptData {
        // 1. 换算钟点：以正前方 0° 为中心，±15° 严格映射为 12 点钟，顺时针每 30° 递增 1 点钟
        var normalizedAngle = azimuth
        if normalizedAngle < 0 {
            normalizedAngle += 360.0
        }
        let rawHour = Int((normalizedAngle + 15.0) / 30.0) % 12
        let clockHour = (rawHour == 0) ? 12 : rawHour
        
        // 2. 换算高矮层级修饰词 (<-15° 低矮地面, >15° 悬空碰头)
        let levelText: String
        if elevation < -15.0 {
            levelText = "低矮地面"
        } else if elevation > 15.0 {
            levelText = "悬空碰头"
        } else {
            levelText = "平齐视线"
        }
        
        // 3. 格式化距离文本 (保留 1 位小数)
        let distanceText = String(format: "%.1f", distance)
        let summary = "\(clockHour)点钟方向，前方\(distanceText)米，\(levelText)"
        
        return ClockPromptData(
            clockHour: clockHour,
            distanceMeters: distance,
            elevationLevel: levelText,
            readableSummary: summary
        )
    }
    
    // MARK: - 2. 原生 3D 空间音频声源锚点转换 (iOS CoreAudio 适配)
    
    /// 将三维相对坐标直接映射为 iOS 空间音频所需的声源参数
    /// - Parameters:
    ///   - position: 相对坐标 (x, y, z, 严格遵循 iOS 空间音频右手坐标系: +X 右, -X 左, +Y 上, -Z 前, +Z 后)
    ///   - boundingSize: 物体 3D 包围盒长宽高 (米)
    /// - Returns: 原生 3D 空间音频渲染参数 (直接赋值给 AVAudio3DMixing)
    public static func toSpatialAudioRenderParams(
        position: SIMD3<Float>,
        boundingSize: SIMD3<Float>
    ) -> SpatialAudioRenderParams {
        let distance = simd_length(position)
        // 距离衰减计算：基于距离倒数衰减 (0.5m 处为 1.0, 5.0m 处衰减至 0.1)
        let attenuation = max(0.0, min(1.0, 1.0 / max(distance, 0.5)))
        // 声源扩展角：根据物体宽度换算扩散角度 (度)
        let spreadAngle = min(180.0, (boundingSize.x / max(distance, 0.5)) * (180.0 / .pi))
        
        return SpatialAudioRenderParams(
            sourcePosition: position,
            attenuation: attenuation,
            spreadAngle: spreadAngle
        )
    }
    
    // MARK: - 3. 双声道立体声降级参数计算 (普通耳机兜底)
    
    /// 针对非空间音频耳机的双声道声相与脉冲参数换算
    /// - Parameters:
    ///   - azimuth: 水平偏航角 (-180° ~ +180°)
    ///   - distance: 直线距离 (米)
    /// - Returns: 双声道 Pan 平衡值、音调与脉冲周期
    public static func toStereoFallbackParams(
        azimuth: Float,
        distance: Float
    ) -> StereoFallbackParams {
        // 声道平衡 pan: -1.0 (纯左耳) ~ +1.0 (纯右耳)
        let radians = azimuth * (.pi / 180.0)
        let pan = max(-1.0, min(1.0, sin(radians)))
        // 音调升降: 距离越近音调越高 (0.5m 处 2.0x, 5.0m 处 0.8x)
        let pitch = max(0.5, min(2.0, 2.0 - (distance / 5.0) * 1.2))
        // 脉冲周期: 距离越近蜂鸣越急促 (100ms ~ 800ms)
        let interval = max(100, min(800, Int(distance * 200.0)))
        
        return StereoFallbackParams(
            stereoPan: pan,
            pitchMultiplier: pitch,
            recommendedPulseIntervalMs: interval
        )
    }
    
    // MARK: - 4. 几何净空快速碰撞校验
    
    /// 探测指定人体宽度沿指定偏角行进指定深度是否存在障碍物冲突
    /// - Parameters:
    ///   - heading: 探测偏航角 (度, 0° 为正前方, 正值为右, 负值为左)
    ///   - userWidth: 人体安全宽度 (米, 默认 0.6m)
    ///   - depth: 探测前向纵深 (米, 默认 2.0m)
    ///   - obstacles: 当前帧所有已检出障碍物列表
    /// - Returns: 净空检测结果
    public static func checkClearance(
        heading: Float,
        userWidth: Float = 0.6,
        depth: Float = 2.0,
        against obstacles: [ObstacleItem]
    ) -> ClearanceResult {
        let halfWidth = userWidth / 2.0
        let headingRad = heading * (.pi / 180.0)
        // iOS 空间音频右手系中，行进方向纵向单位向量 (dirX, dirZ)
        let dirX = sin(headingRad)
        let dirZ = -cos(headingRad)
        
        var minDistance = depth
        var isClear = true
        var conflictId: Int? = nil
        
        for obs in obstacles {
            // 计算障碍物在行进方向上的纵深投影与横向侧偏
            let dx = obs.position.x
            let dz = obs.position.z
            let longitudinal = dx * dirX + dz * dirZ
            let lateral = abs(-dx * dirZ + dz * dirX)
            
            // 位于行进方向前方且在探测纵深内
            if longitudinal > 0 && longitudinal <= depth {
                // 考虑障碍物本身的包围盒半宽
                let obsHalfWidth = obs.size.x / 2.0
                if lateral <= (halfWidth + obsHalfWidth) {
                    if longitudinal < minDistance {
                        minDistance = longitudinal
                        isClear = false
                        conflictId = obs.id
                    }
                }
            }
        }
        
        return ClearanceResult(
            isClear: isClear,
            nearestObstacleDistance: minDistance,
            conflictingObstacleId: conflictId
        )
    }
}
