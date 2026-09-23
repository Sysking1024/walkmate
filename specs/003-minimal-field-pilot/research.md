# 技术调研与架构决策：003-minimal-field-pilot 极简真机实测

**特性分支**: `003-minimal-field-pilot`  
**关联规范**: [`specs/003-minimal-field-pilot/spec.md`](./spec.md)  
**状态**: Approved

---

## 现有技术资产与算法复用清单 (零重复造轮子)

经对当前代码库的全面审查，以下核心模块与算法**已经完整实现并通过严格单元测试，本特性 100% 复用，严禁任何侵入式修改**：

| 现有文件路径 | 已实现算法与能力 | 本特性复用方式 | 改动状态 |
| :--- | :--- | :--- | :---: |
| `WalkMate/Core/Inference/AcceleratePreprocessor.swift` | vImage 硬件零拷贝缩放 + vDSP 硬件向量化归一化 ($\le 11.2\text{ms}$) | 直接复用，负责相机帧预处理 | **无需改动** |
| `WalkMate/Core/Inference/DAPEngine.swift` | DAP ANE 原生 CoreML INT8 深度推理 ($\le 98\text{ms}$)，Float16 内存安全绑定 | 直接复用，负责全景深度预测 | **无需改动** |
| `WalkMate/Core/Geometry/SphericalProjector.swift` | 1.57MB LUT 查表 + vDSP 毫秒级 13 万点球面反投影与 EMA 滤波 | 直接复用，负责深度点云重建 | **无需改动** |
| `WalkMate/Core/Geometry/GravityAligner.swift` | 六轴 IMU 四元数旋转，对齐重力铅垂方向使地面水平 | 直接复用，负责点云重力校正 | **无需改动** |
| `WalkMate/Core/Geometry/GroundPlaneEstimator.swift` | 纯动态 RANSAC 地面拟合，剥离路面点云并解算相机离地高度 | 直接复用，负责地面过滤 | **无需改动** |
| `WalkMate/Core/Perception/ObstacleDetector.swift` | 3D AABB 空间聚类、高程分类（地面/悬挂/跌落）及 $< 0.3\text{m}$ 盲区规约 | 直接复用，输出全景障碍物列表 | **无需改动** |
| `WalkMate/Core/Perception/ObstacleTracker.swift` | 3D 欧氏距离门限多目标跨帧追踪 (MOT)，维持稳定 ID 与接近速度 | 直接复用，提供稳定障碍物状态 | **无需改动** |
| `WalkMate/Core/Perception/PassageRoutePlanner.swift` | 300x300 BEV 栅格投影、2D EDT 距离场、A* 路径寻优提取连续路标折线点 | 直接复用，输出 `waypoints` 序列 | **无需改动** |
| `WalkMate/Core/Toolkits/SpatialAudioKit.swift` | 坐标到 `AVAudio3DPoint` 映射、距离衰减、右手系换算纯函数 | 直接复用，提供几何音频映射支持 | **无需改动** |
| `WalkMate/Core/Audio/ProceduralAudioSynthesizer.swift` | 内存 DSP 参数化纯代码物理合成金属撞击音、脚步踏地音、和弦激励音 | 直接复用，提供 44.1kHz PCM 缓存 | **无需改动** |
| `WalkMate/Core/Audio/SpatialAudioPlayer.swift` | `AVAudioEngine` 3D 声学图、HRTF 高精双耳渲染、800ms 金属双响防重入状态机、1.1s 自然步频节拍调度、Ducking 30% 让位机制、音频打断监听 | 直接复用，作为音频播放执行中枢 | **无需改动** |
| `WalkMate/Core/Camera/CameraPipeline.swift` | Insta360 Socket 握手、H.265/H.264 视频流解码、六轴陀螺仪时间戳匹配 | 直接复用，提供视频帧与相机控制 | **无需改动** |
| `WalkMate/Core/Engine/SpatialPerceptionEngine.swift` | 串联预处理、推理、几何、聚类与规划的全链路流水线总成 | 直接复用，驱动单帧算法执行 | **无需改动** |
| `WalkMate/App/Views/PanoramicStreamView.swift` | 全景实时视频流 OpenGL/Metal 原生渲染视图封装 | 直接复用，作为全屏背景渲染载体 | **无需改动** |

---

## 核心技术决策 (Architectural Decisions)

### 决策 1：机制与策略解耦——前向 130° 与 1 米近身过滤收敛在业务应用层 (ViewModel)
- **背景**：基建 API（`SpatialPerceptionEngine`）负责输出全景 360° 客观物理事实。如果底层强行截断视角，将丧失全向感知的扩展能力；而用户行走时只需要前方行进安全锥。
- **决策**：在 `WalkMate/App/ContentView.swift`（`CameraViewModel`）中接收到 `ObstacleData` 时执行业务策略初筛：
  ```swift
  // 仅筛选处于前向 130° 扇区（|azimuth| <= 65°）且物理距离 <= 1.0 米的最近障碍物
  let forwardNearHazard = data.obstacles
      .filter { $0.distance <= 1.0 && abs($0.azimuth) <= 65.0 }
      .min(by: { $0.distance < $1.distance })
  
  // 注入空间音频；若无满足条件的障碍物，传入 nil 自动保持静音
  SpatialAudioPlayer.shared.setObstacleTarget(position: forwardNearHazard?.position)
  ```
- **选型考量**：
  - 避免侵入 001 基建 API 与既有单元测试；
  - 彻底杜绝视障用户后方（如刚站起的椅子或墙体）产生惊吓性报警；
  - 极简优雅，仅需数行代码即可建立坚固的业务防扰护栏。

### 决策 2：首航路点直接导引策略 (First Waypoint Navigation)
- **背景**：`PassageRoutePlanner` 规划出沿通道中轴的一整组航路折线点（间距 0.4m），而真机实测中最核心的是指引用户踏出第一步的方向。
- **决策**：在 `CameraViewModel` 接收到 `PassableRouteData` 时：
  ```swift
  // 仅提取第 1 个航路点位置，驱动领路脚步声
  let firstWaypoint = data.waypoints.first?.position
  SpatialAudioPlayer.shared.setNavigationTarget(position: firstWaypoint)
  ```
- **选型考量**：
  - 零额外计算开销；
  - 自动平滑追踪前方通道起步朝向。

### 决策 3：全屏沉浸式 UI 架构与启停状态机解耦
- **背景**：原 UI 使用 `ScrollView` 并堆叠了传感器卡片与感知卡片，操作不便且遮挡视线。测试者需要全屏监控画面，且希望将“相机推流”与“大模型深度推理”解耦，避免持续发热。
- **决策**：
  1. **布局结构**：使用 `ZStack` 替换 `ScrollView`。底层为 `PanoramicStreamView` 铺满整屏（`.ignoresSafeArea()`），上层浮层仅在底部保留操作栏；
  2. **状态解耦**：引入 `@Published public var isPerceiving: Bool = false`：
     - 当未开启感知时，相机推流持续工作供测试者观察画面，`CameraPipeline.didReceiveFrame` **不向**感知引擎投递帧，节省算力与电池；
     - 点击“开始感知”时，`isPerceiving = true`，启动 `SpatialAudioPlayer.shared.start()` 与 `perceptionEngine.start()`，帧流开始灌入深度模型与路线解算；
     - 点击“停止感知”时，`isPerceiving = false`，立即调用 `SpatialAudioPlayer.shared.reset()` 恢复静音，视频预览依然通畅。

### 决策 4：系统级后台音频与 Xcode 工程配置补全
- **背景**：真机行走时用户经常会息屏或将手机放入口袋，若无后台音频权限，iOS 会在息屏瞬间挂起 App 导致音频中断；此外 `project.yml` 遗漏了 `AudioTests`。
- **决策**：
  1. 在 `WalkMate/Info.plist` 中添加 `UIBackgroundModes` 键包含 `audio`；
  2. 在 `WalkMate/project.yml` 中补齐 `AudioTests` target 与 scheme，使全工程测试套件齐备。

---

## 替代方案对比 (Alternatives Evaluated)

| 场景 | 备选方案 | 选用方案 | 为什么选择选用方案 |
| :--- | :--- | :--- | :--- |
| **避障过滤位置** | 在 `ObstacleDetector` 内部硬编码裁剪点云 | 在 `CameraViewModel` 中对输出障碍物做方位过滤 | 保证 001 基础 API 的通用性与已有测试的零破坏，同时以最小成本满足业务需求。 |
| **界面布局** | 保留小型浮窗展示 FPS 与时延 | 彻底清空所有非必要文字，仅保留全屏画面与左右双按钮 | 严格遵照用户指令：“删除遥测数据展示，将视频预览界面填充到整个界面”，消除一切干扰。 |
| **感知与相机联动** | 相机连上后自动无脑常开推理 | 独立“开始/停止感知”按钮控制 | 保护 iPhone 15 发热与功耗，让测试人员拥有完全受控的启停时机。 |
