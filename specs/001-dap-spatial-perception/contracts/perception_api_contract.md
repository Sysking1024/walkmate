# 接口契约：空间感知与避障数据服务协议 (Perception API Contract)

**特性分支**: `001-dap-spatial-perception`  
**关联模型**: [data-model.md](../data-model.md)  
**创建时间**: 2026-09-22  

---

## 一、模块职责

`SpatialPerceptionEngine` 是 001 特性的核心出口。它接收 `PanoramicFrame`，协调 DAP 深度推理、重力对齐、纯动态地面拟合、运动意图解算与安全走廊提取，并持续向外广播 `SpatialPerceptionResult`，直接供上层空间音频（`AVAudio3DMixing`）消费。

---

## 二、公开协议定义 (Swift Protocol)

```swift
import Foundation

/// 空间感知数据监听代理 (上层空间音频挂载此代理)
public protocol SpatialPerceptionDelegate: AnyObject {
    /// 完整空间感知决策帧输出
    func perceptionEngine(
        _ engine: SpatialPerceptionEngineProtocol,
        didProduceResult result: SpatialPerceptionResult
    )
    
    /// 紧急安全告警快速通道 (当发生后退碰撞或前方/后方跌落踩空危险时触发)
    func perceptionEngine(
        _ engine: SpatialPerceptionEngineProtocol,
        didTriggerImmediateHazard hazard: DropOffHazardEvent
    )
}

/// 空间感知引擎控制接口
public protocol SpatialPerceptionEngineProtocol: AnyObject {
    /// 代理监听
    var delegate: SpatialPerceptionDelegate? { get set }
    
    /// 引擎是否处于活跃处理中
    var isRunning: Bool { get }
    
    /// 启动感知流水线
    func start()
    
    /// 停止感知流水线
    func stop()
    
    /// 处理单帧全景数据 (通常由 CameraPipeline 驱动)
    func processFrame(_ frame: PanoramicFrame)
}
```

---

## 三、数据消费指南（供下游空间音频集成）

### 1. 引导音频声源位置绑定
```swift
// 上层空间音频接收到走廊导向锚点后，直接赋值:
let corridor = result.corridor
if corridor.isPassable {
    // targetAnchor.x, targetAnchor.y, targetAnchor.z 直接对应 AVAudio3DMixing.position
    guideAudioNode.position = AVAudio3DPoint(
        x: corridor.targetAnchor.x,
        y: corridor.targetAnchor.y,
        z: corridor.targetAnchor.z
    )
    guideAudioNode.volume = 0.8
} else {
    guideAudioNode.volume = 0.0 // 无通路时静音引导音
}
```

### 2. 障碍物警示声源绑定
```swift
// 遍历 Top 3 障碍物，直接驱动警示音源:
for (index, obstacle) in result.obstacles.enumerated() {
    let audioNode = obstacleAudioNodes[index]
    audioNode.position = AVAudio3DPoint(
        x: obstacle.position.x,
        y: obstacle.position.y,
        z: obstacle.position.z
    )
    // 根据威胁级别调节警示音调或脉冲频率
    audioNode.rate = (obstacle.threatLevel == .danger) ? 2.0 : 1.0
}
```

### 3. 后退倒车雷达与紧急踩空告警
```swift
if result.motionState == .backward {
    // 用户正在后退，检查后方危险
    if let dropOff = result.dropOff, dropOff.isRearHazard {
        // 播放后方紧急双耳急促蜂鸣
        playRearEmergencyAlarm()
    }
}
```
