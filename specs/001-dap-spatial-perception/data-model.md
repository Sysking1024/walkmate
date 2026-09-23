# 数据模型与实体规范：全景空间感知与导航基础数据 API

**特性分支**: `001-dap-spatial-perception`  
**关联规范**: [spec.md](./spec.md) | [research.md](./research.md)  
**创建时间**: 2026-09-22（重大修订于 2026-09-23）

---

## 一、实体关系总览 (Entity Relationships)

```text
PanoramicFrame (全景视频与姿态输入帧)
  ├── CVPixelBuffer (1080P 或 512x256 等矩形投影画面)
  └── SensorTelemetry (传感器姿态、角速度与加速度)

DepthMatrix (物理深度矩阵 256x512)
  └── 生成自 PanoramicFrame (经过 CoreML ANE 推理)

┌─────────────────────────────────────────────────────────────────┐
│                    SDK 核心对外交付数据模型                      │
├─────────────────────────────────────────────────────────────────┤
│ 1. ObstacleData (全场景 360° 障碍物数据)                         │
│     ├── frameId: Int64                                          │
│     ├── timestampMs: Int64                                      │
│     └── obstacles: [ObstacleItem] (全量检出目标列表)               │
│           ├── id: Int (跨帧持久追踪标识符)                        │
│           ├── position: SIMD3<Float> (右手坐标系三维坐标)          │
│           ├── distance / azimuth / elevation                    │
│           ├── size: SIMD3<Float> (3D 包围盒长宽高)               │
│           ├── category: ObstacleCategory (地面/悬挂/跌落/动态)    │
│           ├── relativeVelocity / approachRate                   │
│           └── threatLevel: ThreatLevel (safe / warning / danger)│
│                                                                 │
│ 2. PassableRouteData (可通行路线折线数据)                        │
│     ├── isPathAvailable: Bool                                   │
│     ├── safeDepth: Float                                        │
│     ├── recommendedHeading: Float                               │
│     └── waypoints: [RouteWaypoint] (连续航路折线点序列)            │
│           ├── position: SIMD3<Float>                            │
│           └── clearanceWidth: Float (该点处物理净宽)              │
│                                                                 │
│ 3. SpatialAudioKit (无状态纯计算工具箱输出数据包)                 │
│     ├── ClockPromptData (逆空间编码文案数据包)                    │
│     ├── SpatialAudioRenderParams (iOS 原生空间音频 3D 锚点)      │
│     ├── StereoFallbackParams (双声道普通耳机降级参数)             │
│     └── ClearanceResult (几何净空碰撞测试结果)                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 二、核心实体详细定义 (Swift 数据模型)

### 1. 相机连接与遥测实体（已交付基石，保持稳定）

#### `CameraConnectionState`（相机连接状态枚举）
```swift
/// 相机生命周期状态
public enum CameraConnectionState: String, Codable, Sendable {
    case noConnection = "未连接"
    case connecting   = "连接中"
    case connected    = "已连接"
    case failed       = "连接失败"
}
```

#### `SensorTelemetry`（传感器遥测数据）
```swift
import simd

/// 相机传感器与推流状态指标
public struct SensorTelemetry: Codable, Equatable, Sendable {
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
    
    public init(
        connectionState: CameraConnectionState,
        fps: Float,
        pitch: Float,
        roll: Float,
        yaw: Float,
        acceleration: SIMD3<Float>,
        timestampMs: Int64
    ) {
        self.connectionState = connectionState
        self.fps = fps
        self.pitch = pitch
        self.roll = roll
        self.yaw = yaw
        self.acceleration = acceleration
        self.timestampMs = timestampMs
    }
}
```

#### `PanoramicFrame`（全景感知输入帧）
```swift
import CoreVideo
import simd

/// 单次采集的完整全景数据帧
public struct PanoramicFrame: Sendable {
    /// 图像像素缓存 (由相机硬件解码输出的 1080P 原生全景帧)
    public let pixelBuffer: CVPixelBuffer
    /// 采集毫秒时间戳
    public let timestampMs: Int64
    /// 相机当前绝对姿态四元数 (用于重力校准)
    public let orientation: simd_quatf
    /// 瞬时线性加速度向量
    public let acceleration: SIMD3<Float>
    
    public init(
        pixelBuffer: CVPixelBuffer,
        timestampMs: Int64,
        orientation: simd_quatf,
        acceleration: SIMD3<Float>
    ) {
        self.pixelBuffer = pixelBuffer
        self.timestampMs = timestampMs
        self.orientation = orientation
        self.acceleration = acceleration
    }
}
```

---

### 2. 全场景 360° 障碍物数据实体

#### `ObstacleCategory`（障碍物分类枚举）
```swift
/// 空间障碍物/危险源类型分类
public enum ObstacleCategory: String, Codable, Sendable {
    /// 地面凸起障碍物（箱子、椅子、立柱等）
    case groundObstacle = "groundObstacle"
    /// 高空悬挂/碰头危险（离地 > 1.4 米的悬空树枝、招牌等）
    case hangingHazard = "hangingHazard"
    /// 地面下沉断层（落差 > 15 厘米的下行阶梯、深坑台阶等）
    case dropOffHazard = "dropOffHazard"
    /// 动态移动行人或物体
    case dynamicEntity = "dynamicEntity"
}
```

#### `ThreatLevel`（威胁等级枚举）
```swift
/// 综合威胁等级评估
public enum ThreatLevel: String, Codable, Sendable {
    /// 处于核心警戒区内或相对逼近速度极快
    case danger  = "danger"
    /// 距离适中或有接近趋势
    case warning = "warning"
    /// 处于安全距离外且无明显接近威胁
    case safe    = "safe"
}
```

#### `ObstacleItem`（单个障碍物实体）
```swift
import simd

/// 单个空间障碍物在使用者相对坐标系中的空间描述
public struct ObstacleItem: Codable, Equatable, Sendable, Identifiable {
    /// 跨帧唯一跟踪标识符（在目标连续移动期间保持稳定）
    public let id: Int
    /// 三维相对坐标 (x:水平左右, y:垂直高度, z:前后纵深, 单位: 米)
    /// 严格遵循 iOS 空间音频右手坐标系: +X 为右, -X 为左, +Y 为上, -Z 为前向纵深, +Z 为后方
    public let position: SIMD3<Float>
    /// 直线绝对距离 (单位: 米)
    public let distance: Float
    /// 水平偏转方位角 (单位: 度, -180° ~ +180°, 0° 为正前方, 负值为左, 正值为右)
    public let azimuth: Float
    /// 垂直仰角 (单位: 度, 负值为低矮, 正值为悬挂)
    public let elevation: Float
    /// 物理空间三维包围盒尺寸 (宽、高、深，单位: 米)
    public let size: SIMD3<Float>
    /// 障碍物危险源分类
    public let category: ObstacleCategory
    /// 相对运动速度矢量 (vx, vy, vz, 单位: 米/秒)
    public let relativeVelocity: SIMD3<Float>
    /// 标量动态相对接近速率 (米/秒, 正值表示迎面逼近, 负值表示远离)
    public let approachRate: Float
    /// 综合威胁优先级评分
    public let priorityScore: Float
    /// 威胁级别
    public let threatLevel: ThreatLevel
    /// 是否位于使用者后方 (true 表示处于后方视野)
    public let isRearHazard: Bool
    
    public init(
        id: Int,
        position: SIMD3<Float>,
        distance: Float,
        azimuth: Float,
        elevation: Float,
        size: SIMD3<Float>,
        category: ObstacleCategory,
        relativeVelocity: SIMD3<Float>,
        approachRate: Float,
        priorityScore: Float,
        threatLevel: ThreatLevel,
        isRearHazard: Bool
    ) {
        self.id = id
        self.position = position
        self.distance = distance
        self.azimuth = azimuth
        self.elevation = elevation
        self.size = size
        self.category = category
        self.relativeVelocity = relativeVelocity
        self.approachRate = approachRate
        self.priorityScore = priorityScore
        self.threatLevel = threatLevel
        self.isRearHazard = isRearHazard
    }
}
```

#### `ObstacleData`（全场景障碍物集合）
```swift
/// 单帧输出的全场景 360° 障碍物数据聚合体
public struct ObstacleData: Codable, Equatable, Sendable {
    /// 对应输入视频帧序号
    public let frameId: Int64
    /// 毫秒时间戳
    public let timestampMs: Int64
    /// 全量检出的 360° 障碍物列表（数组首项为当前最高威胁目标）
    public let obstacles: [ObstacleItem]
    
    public init(
        frameId: Int64,
        timestampMs: Int64,
        obstacles: [ObstacleItem]
    ) {
        self.frameId = frameId
        self.timestampMs = timestampMs
        self.obstacles = obstacles
    }
}
```

---

### 3. 可通行路线折线实体

#### `RouteWaypoint`（路径路标点）
```swift
import simd

/// 可通行路线上的单个三维路标折线点
public struct RouteWaypoint: Codable, Equatable, Sendable {
    /// 相对空间三维坐标 (单位: 米)
    public let position: SIMD3<Float>
    /// 该路标点位置处的物理通行净宽 (单位: 米，如 1.2m)
    public let clearanceWidth: Float
    
    public init(position: SIMD3<Float>, clearanceWidth: Float) {
        self.position = position
        self.clearanceWidth = clearanceWidth
    }
}
```

#### `PassableRouteData`（可通行路线数据）
```swift
/// 当前可通行路线与空间走廊几何描述
public struct PassableRouteData: Codable, Equatable, Sendable {
    /// 是否存在安全可通过路线
    public let isPathAvailable: Bool
    /// 最大安全可行进纵深 (米)
    public let safeDepth: Float
    /// 推荐起步偏航方位角 (度, 指向通道中心)
    public let recommendedHeading: Float
    /// 连续路径路标点序列（由近及远排列）
    public let waypoints: [RouteWaypoint]
    
    public init(
        isPathAvailable: Bool,
        safeDepth: Float,
        recommendedHeading: Float,
        waypoints: [RouteWaypoint]
    ) {
        self.isPathAvailable = isPathAvailable
        self.safeDepth = safeDepth
        self.recommendedHeading = recommendedHeading
        self.waypoints = waypoints
    }
    
    /// 默认不可通行状态
    public static var blocked: PassableRouteData {
        PassableRouteData(
            isPathAvailable: false,
            safeDepth: 0.0,
            recommendedHeading: 0.0,
            waypoints: []
        )
    }
}
```

---

### 4. 空间音频与空间几何转换工具箱输出实体

#### `ClockPromptData`（钟表方位逆空间编码数据）
```swift
/// 适合 VoiceOver 或 TTS 朗读的钟表方位描述
public struct ClockPromptData: Codable, Equatable, Sendable {
    /// 钟表点位 (1 ~ 12，正前方为 12 点钟)
    public let clockHour: Int
    /// 距离 (单位: 米)
    public let distanceMeters: Float
    /// 高矮层级修饰词 ("低矮地面" / "平齐视线" / "悬空碰头")
    public let elevationLevel: String
    /// 组装好的标准朗读文案（例如："11点钟方向，前方1.8米，低矮地面"）
    public let readableSummary: String
    
    public init(
        clockHour: Int,
        distanceMeters: Float,
        elevationLevel: String,
        readableSummary: String
    ) {
        self.clockHour = clockHour
        self.distanceMeters = distanceMeters
        self.elevationLevel = elevationLevel
        self.readableSummary = readableSummary
    }
}
```

#### `SpatialAudioRenderParams`（原生 3D 空间音频参数）
```swift
import simd

/// 对应 iOS CoreAudio / AVAudio3DMixing 所需的几何与声学参数
public struct SpatialAudioRenderParams: Codable, Equatable, Sendable {
    /// 转换为苹果右手坐标系的 3D 声源锚点坐标 (直接赋值给 AVAudio3DMixing.position)
    public let sourcePosition: SIMD3<Float>
    /// 推荐距离音量衰减系数 (0.0 ~ 1.0)
    public let attenuation: Float
    /// 建议的声源扩展角 (Spread Angle，度)
    public let spreadAngle: Float
    
    public init(
        sourcePosition: SIMD3<Float>,
        attenuation: Float,
        spreadAngle: Float
    ) {
        self.sourcePosition = sourcePosition
        self.attenuation = attenuation
        self.spreadAngle = spreadAngle
    }
}
```

#### `StereoFallbackParams`（普通双声道耳机降级参数）
```swift
/// 针对非空间音频耳机的双声道声相与脉冲参数
public struct StereoFallbackParams: Codable, Equatable, Sendable {
    /// 声道平衡 Pan: -1.0 (纯左耳) ~ +1.0 (纯右耳)，直接赋值给 AVAudioPlayer.pan
    public let stereoPan: Float
    /// 建议音调调节倍率 (0.5x ~ 2.0x，距离越近音调越高)
    public let pitchMultiplier: Float
    /// 建议蜂鸣脉冲间隔时间 (毫秒，例如 100ms ~ 800ms)
    public let recommendedPulseIntervalMs: Int
    
    public init(
        stereoPan: Float,
        pitchMultiplier: Float,
        recommendedPulseIntervalMs: Int
    ) {
        self.stereoPan = stereoPan
        self.pitchMultiplier = pitchMultiplier
        self.recommendedPulseIntervalMs = recommendedPulseIntervalMs
    }
}
```

#### `ClearanceResult`（几何净空检测结果）
```swift
/// 指定行进方向的净空碰撞检测结果
public struct ClearanceResult: Codable, Equatable, Sendable {
    /// 该行进通道是否畅通
    public let isClear: Bool
    /// 最近阻挡物体的直线距离 (若畅通则为探测最大深度)
    public let nearestObstacleDistance: Float
    /// 冲突障碍物的跟踪 ID (若有)
    public let conflictingObstacleId: Int?
    
    public init(
        isClear: Bool,
        nearestObstacleDistance: Float,
        conflictingObstacleId: Int? = nil
    ) {
        self.isClear = isClear
        self.nearestObstacleDistance = nearestObstacleDistance
        self.conflictingObstacleId = conflictingObstacleId
    }
}
```
