# 数据模型与实体规范：基于 DAP 的全景空间感知与避障系统

**特性分支**: `001-dap-spatial-perception`  
**关联规范**: [spec.md](./spec.md) | [research.md](./research.md)  
**创建时间**: 2026-09-22  

---

## 一、实体关系总览 (Entity Relationships)

```text
PanoramicFrame (全景视频与姿态帧)
  ├── CVPixelBuffer (全景像素缓存 512x256)
  └── SensorTelemetry (传感器姿态与度量)

DepthMatrix (物理深度矩阵 256x512)
  └── 生成自 PanoramicFrame (经过 CoreML ANE 推理)

SpatialPerceptionResult (每帧最终输出的空间感知聚合对象)
  ├── UserMotionState (用户当前运动状态: 前行/静止/后退)
  ├── [SpatialObstacleItem] (最多 3 个高危障碍物对象)
  ├── PassageCorridorGeometry (前方安全通行走廊几何)
  ├── DropOffHazardEvent? (跌落/台阶踩空隐患事件，可选)
  └── SensorTelemetry (当前帧传感器遥测指标)
```

---

## 二、核心实体详细定义 (Swift 数据模型)

### 1. 相机连接与遥测实体

#### `CameraConnectionState`（相机连接状态枚举）
```swift
/// 相机生命周期状态
public enum CameraConnectionState: String, Codable {
    case noConnection = "未连接"
    case connecting   = "连接中"
    case connected    = "已连接"
    case failed       = "连接失败"
}
```

#### `SensorTelemetry`（传感器遥测数据）
```swift
import simd

/// 相机传感器与流状态指标
public struct SensorTelemetry: Codable {
    /// 当前相机连接状态
    public let connectionState: CameraConnectionState
    /// 实时推流帧率 (FPS)
    public let fps: Float
    /// 俯仰角 (Pitch, 绕X轴, 度)
    public let pitch: Float
    /// 翻滚角 (Roll, 绕Z轴, 度)
    public let roll: Float
    /// 偏航角 (Yaw, 绕Y轴, 度)
    public let yaw: Float
    /// 三维线性加速度向量 (x, y, z, 单位: m/s²)
    public let acceleration: SIMD3<Float>
    /// 采样时间戳 (毫秒)
    public let timestampMs: Int64
}
```

#### `PanoramicFrame`（全景感知输入帧）
```swift
import CoreVideo
import simd

/// 单次采集的完整全景数据帧
public struct PanoramicFrame {
    /// 图像像素缓存 (512x256 原生全景格式)
    public let pixelBuffer: CVPixelBuffer
    /// 采集毫秒时间戳
    public let timestampMs: Int64
    /// 相机当前绝对姿态四元数 (用于重力校准)
    public let orientation: simd_quatf
    /// 瞬时线性加速度向量
    public let acceleration: SIMD3<Float>
}
```

---

### 2. 深度矩阵与空间点云实体

#### `DepthMatrix`（物理深度矩阵）
```swift
/// 全向物理深度矩阵 (256x512)
public struct DepthMatrix {
    public static let width = 512
    public static let height = 256
    
    /// 连续内存深度数组 (单位: 米, 范围 0.3m ~ 10.0m; 无效点、盲区或超出量程标记为 Float.nan 或 <= 0.0)
    public let values: ContiguousArray<Float>
    /// 当前帧测得的最小物理距离 (米)
    public let minDepth: Float
    /// 当前帧测得的最大物理距离 (米)
    public let maxDepth: Float
    /// 采集时间戳
    public let timestampMs: Int64
}
```

---

### 3. 空间感知与避障决策实体

#### `UserMotionState`（用户运动状态枚举）
```swift
/// 用户运动状态分类
public enum UserMotionState: String, Codable {
    /// 前行中
    case forward = "前行"
    /// 静止 / 驻足观察
    case stationary = "静止"
    /// 正在后退 / 有后退起步倾向 (触发倒车雷达模式)
    case backward = "后退"
}
```

#### `ThreatLevel`（威胁级别枚举）
```swift
/// 障碍物威胁级别
public enum ThreatLevel: String, Codable {
    case safe    = "安全"
    case warning = "警告"
    case danger  = "危险"
}
```

#### `SpatialObstacleItem`（三维空间障碍物项）
```swift
import simd

/// 单个障碍物在使用者相对坐标系中的空间位置
public struct SpatialObstacleItem: Codable {
    /// 三维相对坐标 (x:水平左右, y:垂直高度, z:前后纵深, 单位: 米)
    /// 严格遵循 iOS 空间音频右手坐标系: +X 为右, -X 为左, +Y 为上 (垂直高度, 反向重力), -Z 为正前 (前向为负), +Z 为正后 (后向为正)
    public let position: SIMD3<Float>
    /// 空间直线距离 (米)
    public let distance: Float
    /// 水平偏转方位角 (度, 负值为左, 正值为右)
    public let azimuth: Float
    /// 垂直仰角 (度, 负值为低矮, 正值为悬挂)
    public let elevation: Float
    /// 动态相对接近速率 (米/秒, 正值表示正在靠近)
    public let approachRate: Float
    /// 综合威胁优先级评分 (综合距离与接近速度计算得出)
    public let priorityScore: Float
    /// 威胁级别
    public let threatLevel: ThreatLevel
    /// 是否为身后危险 (true 表示在用户后方，触发后方空间音频)
    public let isRearHazard: Bool
}
```

#### `PassageCorridorGeometry`（安全通行走廊几何）
```swift
import simd

/// 当前最佳安全通行走廊
public struct PassageCorridorGeometry: Codable {
    /// 是否存在可通过走廊 (人体宽度 0.6m 约束)
    public let isPassable: Bool
    /// 建议行进方位角 (度, 指向通道中心)
    public let recommendedSteeringAngle: Float
    /// 通道最窄处的物理净宽 (米, 如 0.9m 门宽)
    public let clearanceWidth: Float
    /// 安全可行进纵深距离 (米)
    public let passableDepth: Float
    /// 通道中心的三维空间导向锚点坐标 (严格遵循 iOS 空间音频坐标系: targetAnchor.z <= 0, 直接供空间音频绑定引导声源)
    public let targetAnchor: SIMD3<Float>
}
```

#### `DropOffHazardEvent`（跌落/台阶踩空隐患事件）
```swift
/// 前方或后方地面踏空下沉事件
public struct DropOffHazardEvent: Codable {
    /// 距离使用者的水平距离 (米)
    public let distance: Float
    /// 危险边缘所在方位角 (度)
    public let azimuth: Float
    /// 预估向下落差深度 (米, 通常 > 0.15m 触发)
    public let dropDepth: Float
    /// 是否发生在身后 (true 表示后退踩空危险)
    public let isRearHazard: Bool
}
```

#### `SpatialPerceptionResult`（空间感知聚合输出帧）
```swift
/// 每帧对外输出的完整空间感知结果 (供上层空间音频消费)
public struct SpatialPerceptionResult: Codable {
    /// 帧序号
    public let frameId: Int64
    /// 毫秒时间戳
    public let timestampMs: Int64
    /// 用户当前运动状态
    public let motionState: UserMotionState
    /// 障碍物列表 (按优先级排序，最多 3 项)
    public let obstacles: [SpatialObstacleItem]
    /// 安全通行走廊
    public let corridor: PassageCorridorGeometry
    /// 跌落风险 (若无则为 nil)
    public let dropOff: DropOffHazardEvent?
    /// 传感器遥测指标
    public let telemetry: SensorTelemetry
}
```
