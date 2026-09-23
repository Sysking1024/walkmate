# 接口契约：SpatialAudioPlayer API

**模块定位**：`WalkMate/Core/Audio/SpatialAudioPlayer.swift`  
**访问级别**：`public`  
**线程安全**：`@unchecked Sendable` / 线程安全单例

---

## 一、核心接口协议定义

```swift
import AVFoundation
import Foundation
import simd

/// 空间音频播放器接口协议
public protocol SpatialAudioPlayerProtocol: AnyObject, Sendable {
    
    // MARK: - 生命周期管理
    
    /// 启动音频硬件引擎与环境混音器
    /// - Throws: 当音频会话激活失败或 AVAudioEngine 启动受阻时抛出错误
    func start() throws
    
    /// 停止音频引擎并释放播放通道
    func stop()
    
    /// 当前音频引擎是否正在运行
    var isRunning: Bool { get }
    
    // MARK: - 语义通道目标设置（状态驱动，机制与策略分离）
    
    /// 设置危险障碍物目标坐标（触发金属撞击声双音确认警示）
    /// - Parameter position: 障碍物相对三维坐标 (x, y, z)，单位米；传入 nil 则立即停止当前警示
    /// - Note: 每次接收有效目标，固定间隔 800ms 播放 2 次即自动静音；
    ///         发声期间自动平滑压低背景领路脚步声至 30%（双响播完后恢复 100%）；
    ///         双响进行中重复调用采用平滑插值滤波更新空间位置，不发生重叠爆音。
    func setObstacleTarget(position: SIMD3<Float>?)
    
    /// 设置安全可通行航路点目标坐标（持续以人体自然步频播放领路脚步声）
    /// - Parameter position: 前方安全通道航路点相对三维坐标 (x, y, z)，单位米；传入 nil 则停止脚步导引
    /// - Note: 保持约 1.0s ~ 1.2s 稳定步速在目标方位持续播放轻快脚步踏地声。
    func setNavigationTarget(position: SIMD3<Float>?)
    
    // MARK: - 康复达标瞬态激励（事件驱动，单次触发）
    
    /// 单次触发播放康复达标激励音（温润上行八音盒和弦）
    /// - Note: 播放时长约 0.4 秒，播放期间自动让位/平滑压低背景脚步声至 30%（淡入淡出 50ms）以突出表扬听感，播完后自然恢复 100%。
    func playRewardSound()
    
    // MARK: - 声学配置与重置
    
    /// 重置所有激活声源与内部状态（场景切换或重新连接相机时调用）
    func reset()
}
```

---

## 二、纯代码声音合成器接口契约

```swift
/// 纯代码物理建模音频合成器
public enum ProceduralAudioSynthesizer {
    
    /// 音频标准采样率 (44.1 kHz)
    public static let sampleRate: Double = 44100.0
    
    /// 标准单声道 Float32 PCM 音频格式
    public static let audioFormat: AVAudioFormat = ...
    
    /// 默认点声源包围盒尺寸 (0.2m x 0.2m x 0.2m，用于 SpatialAudioKit 坐标转换)
    public static let defaultPointSourceBoundingSize = SIMD3<Float>(0.2, 0.2, 0.2)
    
    /// 合成金属撞击音 PCM 缓存 (0.1秒, 800Hz 冲击共鸣)
    public static func generateMetallicImpactBuffer() -> AVAudioPCMBuffer
    
    /// 合成轻快脚步声 PCM 缓存 (0.08秒, 阻尼冲击加带通摩擦)
    public static func generateFootstepBuffer() -> AVAudioPCMBuffer
    
    /// 合成康复激励上行大三和弦 PCM 缓存 (0.4秒, C5-E5-G5-C6 琶音)
    public static func generateRewardChimeBuffer() -> AVAudioPCMBuffer
}
```

---

## 三、调用示例与时序说明

### 1. 业务层常规联动示例
```swift
let audioPlayer = SpatialAudioPlayer.shared
try audioPlayer.start()

// 在感知引擎回调中联动：
func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didProduceObstacles data: ObstacleData) {
    // 业务策略层：仅在存在危险障碍物时通知音频播放器
    if let primaryObstacle = data.obstacles.first(where: { $0.threatLevel == .danger }) {
        audioPlayer.setObstacleTarget(position: primaryObstacle.position)
    } else {
        audioPlayer.setObstacleTarget(position: nil)
    }
}

func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didProducePassableRoute data: PassableRouteData) {
    // 业务策略层：提取前方首个航路点进行领路
    if data.isPathAvailable, let targetWaypoint = data.waypoints.first {
        audioPlayer.setNavigationTarget(position: targetWaypoint.position)
    } else {
        audioPlayer.setNavigationTarget(position: nil)
    }
}

// 达成避障或连续平稳行走里程碑时：
func onUserAccomplishedMilestone() {
    audioPlayer.playRewardSound()
}
```
