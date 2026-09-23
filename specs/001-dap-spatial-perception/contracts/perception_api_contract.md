# 接口契约：空间感知与导航基础数据服务协议 (Perception API Contract)

**特性分支**: `001-dap-spatial-perception`  
**关联模型**: [data-model.md](../data-model.md)  
**创建时间**: 2026-09-22（重大修订于 2026-09-23）

---

## 一、模块职责与架构定位

`SpatialPerceptionEngine` 是 001 特性的核心出口，定位为**纯粹的基础设施 SDK（类似高德地图 SDK）**。
- 它接收来自 `CameraPipeline` 的 `PanoramicFrame`；
- 协调 Accelerate 预处理、DAP ANE 硬件深度推理、重力对齐与纯动态地平面解算；
- 提取全场景 360° 障碍物点云并执行跨帧 MOT 追踪；
- 构建 BEV 栅格并通过 EDT 提取前向可通行路线折线点（Waypoints）；
- 持续向外广播强类型的 `ObstacleData` 与 `PassableRouteData`（支持 JSON 导出）；
- 同时附带提供无状态纯计算工具箱 `SpatialAudioKit`，供上层无障碍交互与声学渲染开箱即用。

---

## 二、公开协议定义 (Swift Protocol)

```swift
import Foundation
import simd

/// 空间感知数据监听代理 (上层业务挂载此代理获取基础数据)
public protocol SpatialPerceptionDelegate: AnyObject {
    /// 全场景 360° 障碍物数据到达回调
    func perceptionEngine(
        _ engine: SpatialPerceptionEngineProtocol,
        didProduceObstacles data: ObstacleData
    )
    
    /// 可通行路线折线数据到达回调
    func perceptionEngine(
        _ engine: SpatialPerceptionEngineProtocol,
        didProducePassableRoute data: PassableRouteData
    )
    
    /// 感知引擎异常报错
    func perceptionEngine(
        _ engine: SpatialPerceptionEngineProtocol,
        didEncounterError error: Error
    )
}

/// 空间感知引擎控制接口
public protocol SpatialPerceptionEngineProtocol: AnyObject {
    /// 代理监听
    var delegate: SpatialPerceptionDelegate? { get set }
    
    /// 引擎是否处于活跃运行中
    var isRunning: Bool { get }
    
    /// 启动感知流水线
    func start()
    
    /// 停止感知流水线
    func stop()
    
    /// 处理单帧全景数据 (由 CameraPipeline 回调驱动)
    func processFrame(_ frame: PanoramicFrame)
    
    // MARK: - Swift Concurrency 现代化异步流支持 (供 SwiftUI / Combine 订阅)
    
    /// 360° 障碍物异步事件流
    var obstacleStream: AsyncStream<ObstacleData> { get }
    
    /// 可通行路线异步事件流
    var routeStream: AsyncStream<PassableRouteData> { get }
    
    // MARK: - 主动快照查询接口
    
    /// 获取当前最新一帧的全量 360° 障碍物快照
    var latestObstacles: ObstacleData? { get }
    
    /// 获取当前最新一帧的可通行路线快照
    var latestRoute: PassableRouteData? { get }
}
```

---

## 三、空间音频与空间几何转换工具箱协议 (`SpatialAudioKit`)

> [!IMPORTANT]
> **绝对纯函数约束**：`SpatialAudioKit` 内所有方法均为静态纯函数，**严格禁止**调用任何底层音频硬件播放器、严禁触碰或配置系统全局 `AVAudioSession`。

```swift
import Foundation
import simd

/// 空间音频与空间几何纯计算工具箱
public struct SpatialAudioKit: Sendable {
    
    // MARK: - 1. 钟表方位逆空间编码 (视障国际标准语言)
    
    /*!
     * 将极坐标方位换算为适合 VoiceOver 或 TTS 朗读的标准钟表点位文案
     *
     * @param azimuth 偏航角 (-180° ~ +180°, 0° 为正前方)
     * @param distance 绝对直线距离 (米)
     * @param elevation 俯仰仰角 (度, 负值为低矮, 正值为悬挂)
     * @return 包含钟点 (1~12)、距离及中文字符串的结构化数据包
     */
    public static func toClockDirection(
        azimuth: Float,
        distance: Float,
        elevation: Float
    ) -> ClockPromptData {
        // 1. 换算钟点：以正前方 0° 为中心，±15° 为 12 点钟，顺时针每 30° 递增 1 点钟
        var normalizedAngle = azimuth
        if normalizedAngle < 0 { normalizedAngle += 360.0 }
        let rawHour = Int((normalizedAngle + 15.0) / 30.0) % 12
        let clockHour = (rawHour == 0) ? 12 : rawHour
        
        // 2. 换算高矮层级
        let levelText: String
        if elevation < -15.0 {
            levelText = "低矮地面"
        } else if elevation > 15.0 {
            levelText = "悬空碰头"
        } else {
            levelText = "平齐视线"
        }
        
        // 3. 格式化距离 (保留1位小数)
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
    
    /*!
     * 将三维相对坐标直接映射为 iOS 空间音频所需的声源参数
     *
     * @param position 相对坐标 (x, y, z, 单位: 米)
     * @param boundingSize 物体 3D 包围盒长宽高 (单位: 米)
     * @return 原生 3D 空间音频渲染参数
     */
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
    
    /*!
     * 针对非空间音频耳机的双声道声相与脉冲参数换算
     *
     * @param azimuth 偏航角 (-180° ~ +180°)
     * @param distance 直线距离 (米)
     * @return 双声道 Pan 平衡值、音调与脉冲周期
     */
    public static func toStereoFallbackParams(
        azimuth: Float,
        distance: Float
    ) -> StereoFallbackParams {
        // pan 声相: -1.0 (纯左耳) ~ +1.0 (纯右耳)
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
    
    /*!
     * 探测指定人体宽度沿指定偏角行进指定深度是否存在障碍物冲突
     *
     * @param heading 探测偏航角 (度)
     * @param userWidth 人体安全宽度 (米, 默认 0.6m)
     * @param depth 探测纵深 (米, 默认 2.0m)
     * @param obstacles 当前帧所有障碍物列表
     * @return 净空结果
     */
    public static func checkClearance(
        heading: Float,
        userWidth: Float = 0.6,
        depth: Float = 2.0,
        against obstacles: [ObstacleItem]
    ) -> ClearanceResult {
        let halfWidth = userWidth / 2.0
        let headingRad = heading * (.pi / 180.0)
        let dirX = sin(headingRad)
        let dirZ = -cos(headingRad)
        
        var minDistance = depth
        var isClear = true
        var conflictId: Int? = nil
        
        for obs in obstacles {
            // 计算障碍物在行进方向上的投影纵深与横向侧向偏离
            let dx = obs.position.x
            let dz = obs.position.z
            let longitudinal = dx * dirX + dz * dirZ
            let lateral = abs(-dx * dirZ + dz * dirX)
            
            if longitudinal > 0 && longitudinal <= depth {
                // 考虑障碍物本身的包围盒半宽
                let obsHalfWidth = obs.size.x / 2.0
                if lateral < (halfWidth + obsHalfWidth) {
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
```

---

## 四、上层消费最佳实践（调用示范）

### 1. 订阅障碍物与可通行路线
```swift
class NavigationManager: SpatialPerceptionDelegate {
    func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didProduceObstacles data: ObstacleData) {
        // 1. 遍历当前 360° 检出目标 (已按威胁降序排列)
        for obstacle in data.obstacles {
            print("检出障碍物 ID: \(obstacle.id), 距离: \(obstacle.distance)m, 类型: \(obstacle.category.rawValue)")
            
            // 2. 调用工具箱生成语音播报文案
            let prompt = SpatialAudioKit.toClockDirection(
                azimuth: obstacle.azimuth,
                distance: obstacle.distance,
                elevation: obstacle.elevation
            )
            print("读屏播报: \(prompt.readableSummary)")
        }
    }
    
    func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didProducePassableRoute data: PassableRouteData) {
        if data.isPathAvailable {
            print("安全通道起步推荐朝向: \(data.recommendedHeading)度, 纵深: \(data.safeDepth)米")
            print("折线点数量: \(data.waypoints.count)")
        } else {
            print("前方无安全通路！")
        }
    }
    
    func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didEncounterError error: Error) {
        print("空间感知错误: \(error.localizedDescription)")
    }
}
```

### 2. 导出 JSON 数据（给跨平台业务或日志服务消费）
```swift
if let obstacles = engine.latestObstacles {
    let jsonData = try JSONEncoder().encode(obstacles)
    let jsonString = String(data: jsonData, encoding: .utf8)
    // 向上层或远端输出标准 JSON 字符串
}
```
