# 任务清单：全景空间感知与导航基础数据 API (Tasks)

**输入**: 来自 `specs/001-dap-spatial-perception/` 的全部设计产物（[plan.md](./plan.md), [spec.md](./spec.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [research.md](./research.md), [quickstart.md](./quickstart.md)）

**组织与开发原则**: 
1. **测试先行 (TDD / Test-First)**：除已完成的相机连接基石外，每个阶段与用户故事的**单元测试任务必须提前到该阶段最前面**，在编写实现代码前先写好单元测试；
2. **已完成基石保留**：已完成并打勾的相机连接基石任务完整保留；
3. **独立可测性**：每个用户故事包含独立的测试套件与验收标准，支持分段独立交付与验证。

---

## 格式说明：`- [ ] [TaskID] [P?] [Story?] 任务描述与文件路径`

- **[P]**: 标记可并行执行的任务（不同文件、无未完成依赖）
- **[Story]**: 用户故事编号（[US1], [US2], [US3], [US4]），仅在用户故事阶段使用
- 所有任务均包含明确具体的文件路径

---

## Phase 1: Setup (项目基础设施初始化)

**目标**: 建立符合 xcodegen 规范的原生工程架构与通用基础库配置（已全部完成）

- [x] T001 创建工程声明式配置文件 `WalkMate/project.yml`（定义 Bundle ID `accera.world.walkmate`、iOS 17.0+、框架依赖与签名配置）并执行 `xcodegen generate` 生成初始 `WalkMate.xcodeproj`，确保后续开发具备原生工程与编译环境
- [x] T002 [P] 创建应用程序主入口 `WalkMate/App/WalkMateApp.swift`
- [x] T003 [P] 创建符合宪章原则八/九的统一日志工具 `WalkMate/Core/Utils/Log.swift`，封装结构化全中文日志与标准英文级别

---

## Phase 2: Foundational (核心数据模型、深度推理与几何基础设施)

**目标**: 奠定基础数据模型、DAP ANE 硬件推理与空间点云几何解算底层，**测试先行，阻塞后续 US2、US3、US4 的执行**

### 1. 基础数据模型与模型资产
- [x] T004 实现数据模型实体 `WalkMate/Models/FrameModels.swift`（包含 `PanoramicFrame` 与 `DepthMatrix`）
- [x] T005 [P] 实现传感器与连接状态模型 `WalkMate/Models/TelemetryModels.swift`（包含 `SensorTelemetry`, `CameraConnectionState`, `ThreatLevel`）
- [x] T006 [P] 更新空间感知核心数据模型 `WalkMate/Models/PerceptionModels.swift`（按最新契约实现 `ObstacleData`, `ObstacleItem`, `ObstacleCategory`, `PassableRouteData`, `RouteWaypoint`，支持 `Codable, Sendable`）
- [x] T007 [P] 创建工具箱输出模型 `WalkMate/Models/ToolModels.swift`（实现 `ClockPromptData`, `SpatialAudioRenderParams`, `StereoFallbackParams`, `ClearanceResult`，支持 `Codable, Sendable`）
- [x] T008 [P] 导入 ANE 原生 CoreML INT8 模型至 `WalkMate/Resources/Models/dap_256x512_int8.mlpackage`（从 `tmp/dap_256x512_int8.mlpackage` 规范放置至资源目录）
- [x] T008b 在 `WalkMate/project.yml` 中配置 `InferenceTests`、`GeometryTests`、`PerceptionTests` 与 `ToolkitTests` 单元测试目标，并执行 `xcodegen generate`，确保 TDD 测试套件具备 Xcode 工程与 Scheme 支撑

### 2. 测试先行 (TDD) ⚠️ 在实现前编写测试用例
- [x] T009 [P] 编写推理预处理与张量绑定单元测试 `Tests/InferenceTests/InferenceTests.swift`（先行定义测试用例：直接从 `tmp/pano_indoor.jpg` 读取真实全景图像，验证 vImage 缩放目标尺寸 256x512、vDSP 归一化至 $[0, 1]$ 范围、以及 CoreML Float16 输出深度张量内存安全绑定与数值范围）
- [x] T010 [P] 编写几何反投影与地面拟合单元测试 `Tests/GeometryTests/GeometryTests.swift`（先行定义测试用例：基于 `tmp/pano_indoor.jpg` 生成的真实深度矩阵，验证 1.57MB LUT 查表反投影精度、simd 四元数重力姿态对齐、以及动态 RANSAC 真实室内地面拟合误差 $\le 5\text{cm}$）

### 3. 底层算法组件实现
- [x] T011 [P] 实现 Accelerate 硬件向量化预处理器 `WalkMate/Core/Inference/AcceleratePreprocessor.swift`（利用 `vImageScale_ARGB8888` 零拷贝缩放至 256x512，配合 `vDSP` 批量归一化至 $[0, 1]$，单帧耗时 $\le 11.2\text{ms}$，满足 T009 测试）
- [x] T012 实现 ANE 纯硬件深度推理引擎 `WalkMate/Core/Inference/DAPEngine.swift`（CoreML INT8 模型加载、Float16 内存安全绑定与执行，单帧耗时 $\le 98\text{ms}$，满足 T009 测试）
- [x] T013 [P] 实现球面反投影器 `WalkMate/Core/Geometry/SphericalProjector.swift`（应用 `../DAP/depth2point.py` 球面投影公式，预计算 1.57MB 单位向量表 LUT，利用 `vDSP_vmul` 在 1ms 内实现 13 万个 3D 点反投影，集成 EMA 平滑滤波，满足 T010 测试）
- [x] T014 [P] 实现重力对齐器 `WalkMate/Core/Geometry/GravityAligner.swift`（提取六轴 IMU 姿态加速度矢量，构建四元数旋转点云，使 Y 轴严格反平行于重力，X-Z 轴构成水平地平面，满足 T010 测试）
- [x] T015 实现纯动态地面估计器 `WalkMate/Core/Geometry/GroundPlaneEstimator.swift`（对下半球点云执行 RANSAC 快速平面拟合，距离容差 $\epsilon \le 0.05\text{m}$，动态解算相机离地高度并剥离 $|d| \le 0.08\text{m}$ 的平整路面，满足 T010 测试）

**检查点 (Checkpoint)**: 基础模型就绪，T009 与 T010 单元测试驱动底层推理与几何组件全部开发完毕并通过测试。

---

## Phase 3: User Story 1 - Insta360 全景相机连接、控制 UI 与实时流预览 (Priority: P1) 🎯 【已完成基石 (Completed Baseline)】

**目标**: 打通物理相机 Wi-Fi 连接、实时 1080P 全景视频流解码、六轴 IMU 姿态同步以及无障碍控制预览界面（已全部完成并真机验证通畅）

**独立测试验证**: 启动应用，点击“连接设备”，2 秒内连上相机，界面流畅渲染全景实时画面（>= 15 FPS），传感器面板实时刷新三轴姿态与加速度；点击“断开设备”安全退出。

- [x] T016 [P] [US1] 基于官方 SDK 与 `docs/insta_x.md` 实现视频流解码桥接器 `WalkMate/Core/Camera/StreamPlayerBridge.swift`（实现 `INSCameraSessionPlayerDelegate` 与 `INSCameraSessionPlayerDataSource`，动态同步 X5 H.265/H.264 编码与分辨率、挂载 `settings.mediaOffsetV6` 标定参数，并在 `playerPrepared` 中通过 `sampleGroup.getPlayerImage().pixelBuffer` 提取全景帧与毫秒时间戳）
- [x] T017 [P] [US1] 基于官方 SDK 与 `docs/insta_x.md` 实现六轴传感器同步器 `WalkMate/Core/Camera/GyroDataHandler.swift`（实现 `INSCameraSessionGyroDelegate`，通过 `onParsedGyroData` 实时解析 `INSGyroRawItem` 的 `timestamp`、`accelX/Y/Z` 与 `rotX/Y/Z` 数据并派发）
- [x] T018 [US1] 实现相机连接与生命周期管理管道 `WalkMate/Core/Camera/CameraPipeline.swift`（实现 `CameraPipelineProtocol`，基于 `INSCameraManager.socket()` 管理 Wi-Fi Socket 连接、握手、KVO 与断线自动重连，推流帧率基于 1 秒滑动窗口平滑计算）
- [x] T019 [P] [US1] 实现全景视频流实时渲染视图 `WalkMate/App/Views/PanoramicStreamView.swift`
- [x] T020 [P] [US1] 实现六轴传感器遥测数据 HUD 视图 `WalkMate/App/Views/SensorTelemetryCard.swift`（严格遵循宪章原则四 4.c 合并与阻断规则，将整张卡片封装为独立语义容器 `.accessibilityElement(children: .combine)`，利用中文逗号平铺拼接连接状态、FPS、三轴角度与加速度，防止读屏焦点碎片化与高频噪点；确保文本与卡片背景对比度 >= 4.5:1；仅供被动读屏查询，严禁向 VoiceOver 发送实时主动高频播报通知）
- [x] T021 [US1] 实现主控制界面 `WalkMate/App/ContentView.swift`（整合连接/断开控制按钮、全景画面与传感器卡片，确保触控尺寸 >= 48x48pt，按钮与文本对比度 >= 4.5:1，并在连接断开/异常时触发 VoiceOver 语音播报）
- [x] T021b [US1] 编写相机管道脱机逻辑测试 `Tests/CameraTests/CameraPipelineTests.swift`（基于 Mock 数据测试连接生命周期状态机流转、断线重连退避与时间戳匹配封装，无需连接物理相机）

**检查点 (Checkpoint)**: 用户故事 1 作为系统物理数据源基石持续保持健康可用。

---

## Phase 4: User Story 2 - 全场景 360° 障碍物数据与目标跨帧跟踪 (Priority: P1)

**目标**: 统合地面凸起、高空悬挂、下沉台阶断层与动态实体，输出全景 360° 障碍物列表，并基于 3D 欧氏距离门限 MOT 维持跨帧持久 Tracking ID

**独立测试验证**: 在测试环境中设置地面箱子、离地 1.6 米悬挂标牌、向下 20 厘米台阶断层，使用者向前移动，API 稳定输出全量三类障碍物，各目标分配唯一持久 `id`，移动过程中 `id` 保持不变，并准确计算相对接近速度。

### 1. 测试先行 (TDD) ⚠️ 在实现前编写测试用例
- [x] T022 [P] [US2] 编写障碍物检测与跨帧跟踪单元测试 `Tests/PerceptionTests/ObstacleTrackingTests.swift`（先行编写断言用例：基于 `tmp/pano_indoor.jpg` 提取的真实室内点云，断言室内物体/立柱/地面的多类型分类判定规则、包围盒提取精度、连续 10 帧移动下的 Tracking ID 稳定性保持率 $\ge 90\%$、短时 5 帧遮挡下的 ID 保持、以及逼近速度测算精度）

### 2. 核心功能实现
- [x] T023 [P] [US2] 实现全场景 360° 障碍物检测器 `WalkMate/Core/Perception/ObstacleDetector.swift`（接收剥离地面后的空间点云与地面高度参数；执行点云空间聚类与 AABB 三维包围盒提取；换算极坐标距离、方位角与仰角；依据高程进行初始类别判别：$0.08\text{m} \le y_{\text{rel}} \le 1.4\text{m}$ 为 `groundObstacle`、$y_{\text{rel}} > 1.4\text{m}$ 为 `hangingHazard`、$y_{\text{rel}} < -0.15\text{m}$ 为 `dropOffHazard`；计算综合威胁评分与 `threatLevel`，对 $< 0.3\text{m}$ 盲区赋予极近 `danger` 兜底，满足 T022 测试）
- [x] T024 [US2] 实现 3D 多目标跨帧追踪器 `WalkMate/Core/Perception/ObstacleTracker.swift`（构建轻量级 3D 欧氏距离门限匹配矩阵，匹配阈值 $\Delta d \le 0.6\text{m}$；计算连续速度矢量 $\vec{v} = (\vec{P}_t - \vec{P}_{t-1}) / \Delta t$ 与标量接近速率 $v_{\text{approach}}$；若连续接近速率 $|v_{\text{approach}}| > 0.4\text{m/s}$（或连续位移显著），将目标分类更新为 `dynamicEntity` 并动态提升威胁级别；保持目标持久唯一 `id`；维持至多 5 帧约 500ms 的短时遮挡预测状态缓存，满足 T022 测试）

**检查点 (Checkpoint)**: 用户故事 2 可独立运行验证！T022 测试全部转绿，能够输入全景深度点云，持续输出带稳定 ID 的全场景障碍物列表。

---

## Phase 5: User Story 3 - 连续可通行路线与路径折线点解算 (Priority: P1)

**目标**: 基于 300x300 鸟瞰（BEV）自由空间栅格与欧氏距离变换（EDT），输出满足人体宽度约束（0.6m）的连续航路路标点序列（`[RouteWaypoint]`）、通道瓶颈物理净宽与安全纵深

**独立测试验证**: 在设有障碍物的开门走廊场景中，API 规划出避开阻挡物、通往开门处的一组平滑折线点（间距约 0.3m~0.5m），每个路标点标注准确的净宽（门框处净宽误差 < 0.05m），首个推荐偏角指向通道中心。

### 1. 测试先行 (TDD) ⚠️ 在实现前编写测试用例
- [x] T025 [P] [US3] 编写可通行路线规划单元测试 `Tests/PerceptionTests/PassableRouteTests.swift`（先行编写断言用例：基于 `tmp/pano_indoor.jpg` 提取的真实室内点云与 BEV 栅格，测试开门直行通道提取、门洞瓶颈通行净宽计算误差 $\le 5\text{cm}$、以及合成阻挡物下的绕行避障折线点提取）

### 2. 核心功能实现
- [x] T026 [US3] 实现 BEV 栅格与可通行路线规划器 `WalkMate/Core/Perception/PassageRoutePlanner.swift`（将去地面后的障碍物映射至 $300 \times 300$ BEV 栅格，分辨率 $0.02\text{m/cell}$，覆盖 $\pm 3\text{m}$ 宽、$0 \sim 6\text{m}$ 纵深；对自由空间应用 EDT 计算障碍物距离场；施加人体宽度 0.6m 约束并在临界宽度 $[0.55\text{m}, 0.65\text{m}]$ 设置滞后区间防止抖动；沿中轴提取连续路标点序列 `waypoints: [RouteWaypoint]`，标注物理净宽 $W_{\text{clear}} = 2 \times R_{\text{clear}}$、安全纵深 `safeDepth` 与推荐起步偏角 `recommendedHeading`，满足 T025 测试）

**检查点 (Checkpoint)**: 用户故事 3 可独立运行验证！T025 测试全部转绿，成功从俯瞰地图中提取出连续安全航路点与通行净宽。

---

## Phase 6: User Story 4 - 空间音频与空间几何转换工具箱 (Priority: P1)

**目标**: 实现 `SpatialAudioKit` 无状态纯计算工具箱，提供钟表逆空间编码、iOS 原生 3D 音频声源锚点、双声道声相降级与几何碰撞检测纯函数（严格零音频播放）

**独立测试验证**: 调用 `SpatialAudioKit` 静态方法传入三维坐标，微秒级（$< 0.05\text{ms}$）返回钟表点位文案、`AVAudio3DPoint`、双声道 `pan` 与碰撞检测结果，过程中无任何硬件驱动或系统 `AVAudioSession` 配置。

### 1. 测试先行 (TDD) ⚠️ 在实现前编写测试用例
- [x] T027 [P] [US4] 编写工具箱纯函数单元测试 `Tests/ToolkitTests/SpatialAudioKitTests.swift`（先行编写断言用例：方位角到 1~12 点钟换算 100% 准确率、正前方 $\pm 15^\circ$ 严格对应 12 点钟、3D 坐标映射右手坐标系、双声道 pan 限制在 $[-1.0, 1.0]$ 区间、几何净空检测碰撞断言、以及单次运算耗时 $\le 0.05\text{ms}$）

### 2. 核心功能实现
- [x] T028 [P] [US4] 实现空间音频与几何转换工具箱 `WalkMate/Core/Toolkits/SpatialAudioKit.swift`（实现 `toClockDirection` 钟点与高矮层次换算、`toSpatialAudioRenderParams` 映射 `AVAudio3DPoint` 与距离音量衰减、`toStereoFallbackParams` 换算声道平衡与脉冲间隔、`checkClearance(heading:userWidth:depth:against:)` 针对传入的障碍物列表沿行进方向执行包围盒碰撞检测；确保所有方法均为静态纯函数，无任何音频播放与状态副作用，满足 T027 测试）

**检查点 (Checkpoint)**: 用户故事 4 独立完备！T027 测试全部转绿，纯函数工具箱在零音频冲突的前提下，为上层提供了开箱即用的无障碍与声学参数换算能力。

---

## Phase 7: Pipeline Integration & Service Delivery (空间感知引擎总成与全链路串联)

**目标**: 将 Accelerate 预处理、DAP ANE 推理、几何点云、360° 障碍物检测追踪、路线规划器串联成完整的 `SpatialPerceptionEngine`，挂载至相机实时流管道并分发数据

### 1. 测试先行 (TDD) ⚠️ 在实现前编写测试用例
- [x] T029 [P] 编写空间感知引擎全链路集成测试 `Tests/PerceptionTests/PerceptionEngineTests.swift`（先行定义断言用例：直接从 `tmp/pano_indoor.jpg` 读取全景帧构建 `PanoramicFrame` 注入引擎，验证在开发机上脱机跑通完整感知流水线：图像预处理 $\rightarrow$ DAP 推理 $\rightarrow$ 反投影 $\rightarrow$ 地面剥离 $\rightarrow$ 360° 障碍物与路线解算；验证 `ObstacleData` 与 `PassableRouteData` 的 JSON 序列化合法性及单帧耗时）

### 2. 服务总成与装配实现
- [x] T030 实现空间感知对外服务中枢 `WalkMate/Core/Engine/SpatialPerceptionEngine.swift`（遵循 `perception_api_contract.md` 契约，实现 `SpatialPerceptionEngineProtocol`；接收 `PanoramicFrame`，在后台并发队列串联执行预处理、DAP 推理、反投影、地面剥离、障碍物检测追踪与路线规划；通过 `SpatialPerceptionDelegate`、`AsyncStream` 与快照属性分发 `ObstacleData` 和 `PassableRouteData`，满足 T029 测试）
- [x] T031 将 `SpatialPerceptionEngine` 挂载至 `CameraPipeline` 回调并在 `WalkMate/App/ContentView.swift`（或 ViewModel）中完成基础装配，验证实时视频帧驱动感知流水线平稳运转

**检查点 (Checkpoint)**: 全链路数据管道通畅！实时全景视频帧输入后，引擎平稳输出 360° 障碍物列表与可通行路线数据。

---

## Phase 8: Polish & Cross-Cutting Concerns (工程润色与真机全链路验证)

**目标**: 工程自动构建、无障碍合规审查与全链路延迟基准压测

- [x] T032 执行 `xcodegen generate` 重新同步工程配置，并执行 `xcodebuild` 验证全项目静态分析与零警告编译 (Zero Warnings)
- [x] T033 [P] 审查并验证全工程代码注释符合宪章原则五（全中文注释先于核心逻辑），日志采用 Swift `Log` 工具且无裸 `print()`
- [x] T034 [P] 审查全界面 VoiceOver 读屏、触控尺寸与视觉对比度无障碍合规性（所有按钮触控目标 >= 48x48pt，所有前景色/背景色对比度严格 >= 4.5:1）
- [x] T035 执行 `specs/001-dap-spatial-perception/quickstart.md` 场景 5 进行 60 秒持续推流压测，验证全链路单帧端到端延迟严格控制在 130 毫秒以内（目标 $\approx 121\text{ms} / 8.2\text{ FPS}$），内存占用 $\le 150\text{MB}$

---

## 依赖关系与执行拓扑 (Dependencies & Execution Order)

```text
Phase 1: Setup (T001 ~ T003) [已完成]
  ↓
Phase 3: User Story 1 (T016 ~ T021b) [已完成基石：相机通信与实时流]
  ↓
Phase 2: Foundational (T004 ~ T008 数据模型与资源)
  ↓
  [测试先行] T009 (推理测试) & T010 (几何测试)
  ↓
  [底层实现] T011 ~ T015 (预处理、DAP、LUT反投影、重力对齐、RANSAC地面拟合)
  ↓
┌───────────────────────────────────────┬───────────────────────────────────────┐
│ Phase 4: User Story 2                 │ Phase 5: User Story 3                 │
│ [测试先行] T022 (障碍物与追踪测试)       │ [测试先行] T025 (路线规划测试)          │
│   ↓                                   │   ↓                                   │
│ [实现] T023 & T024 (障碍物与MOT追踪)   │ [实现] T026 (BEV/EDT 路线路标点解算)   │
└───────────────────────────────────────┴───────────────────────────────────────┘
  │                                       │
  └───────────────────┬───────────────────┘
                      ↓
  Phase 6: User Story 4
  [测试先行] T027 (工具箱测试) → [实现] T028 (SpatialAudioKit 纯计算工具箱)
                      ↓
  Phase 7: Pipeline Integration
  [测试先行] T029 (引擎全链路测试) → [实现] T030 & T031 (服务中枢总成与挂载)
                      ↓
  Phase 8: Polish & Benchmark (T032 ~ T035) [零警告构建与 121ms 时延压测]
```

---

## 并行执行机会 (Parallel Execution Opportunities)

- **Phase 2 内部并行**：
  - T006 与 T007 模型定义可并行编写；
  - T009（推理测试）与 T010（几何测试）可并行编写；
  - T011（Accelerate预处理）与 T013（LUT反投影）可并行实现。
- **Phase 4 与 Phase 5 跨故事并行**：
  - 在 Phase 2 底层算法就绪后，US2（障碍物检测追踪）与 US3（路线规划）完全解耦，T022/T023/T024 与 T025/T026 可由不同开发者**100% 并行执行**。
- **Phase 6 纯计算工具箱独立并行**：
  - T027 与 T028 为纯数学计算，无任何硬件依赖，可随时提前并行开发与测试。
