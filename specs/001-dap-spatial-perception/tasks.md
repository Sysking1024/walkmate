# 任务清单：基于 DAP 的全景空间感知与避障系统 (Tasks)

**输入**: 来自 `specs/001-dap-spatial-perception/` 的全部设计产物（[plan.md](./plan.md), [spec.md](./spec.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [research.md](./research.md), [quickstart.md](./quickstart.md)）

**组织原则**: 任务严格按用户故事（User Story）与依赖拓扑划分阶段，确保每个用户故事均可独立开发、独立测试与增量交付。

---

## 格式说明：`- [ ] [TaskID] [P?] [Story?] 任务描述与文件路径`

- **[P]**: 标记可并行执行的任务（不同文件、无未完成依赖）
- **[Story]**: 用户故事编号（[US1], [US2], [US3], [US4], [US5]），仅在用户故事阶段使用
- 所有任务均包含明确具体的文件路径

---

## Phase 1: Setup (项目基础设施初始化)

**目标**: 建立符合 xcodegen 规范的原生工程架构与通用基础库配置

- [ ] T001 创建工程声明式配置文件 `WalkMate/project.yml`（定义 Bundle ID `accera.insta.dap`、iOS 17.0+、框架依赖与签名配置）并执行 `xcodegen generate` 生成初始 `WalkMate.xcodeproj`，确保后续开发具备原生工程与编译环境
- [ ] T002 [P] 创建应用程序主入口 `WalkMate/App/WalkMateApp.swift`
- [ ] T003 [P] 创建符合宪章原则八/九的统一日志工具 `WalkMate/Core/Utils/Log.swift`，封装结构化全中文日志与标准英文级别

---

## Phase 2: Foundational (阻塞性基础数据与模型准备)

**目标**: 实现核心数据模型与深度推理基础组件，**阻塞所有后续用户故事的执行**

- [ ] T004 实现数据模型实体 `WalkMate/Models/FrameModels.swift`（包含 `PanoramicFrame` 与 `DepthMatrix`）
- [ ] T005 [P] 实现数据模型实体 `WalkMate/Models/PerceptionModels.swift`（包含 `SpatialObstacleItem`, `PassageCorridorGeometry`, `DropOffHazardEvent`, `SpatialPerceptionResult`）
- [ ] T006 [P] 实现数据模型实体 `WalkMate/Models/TelemetryModels.swift`（包含 `SensorTelemetry`, `CameraConnectionState`, `UserMotionState`, `ThreatLevel`）
- [ ] T007 导入 ANE 原生 CoreML INT8 模型至 `WalkMate/Resources/Models/dap_256x512_int8.mlpackage`
- [ ] T008 [P] 实现 Accelerate 硬件向量化预处理器 `WalkMate/Core/Inference/AcceleratePreprocessor.swift`（vImage 缩放 + vDSP 归一化）
- [ ] T009 实现 ANE 纯硬件深度推理引擎 `WalkMate/Core/Inference/DAPEngine.swift`（CoreML INT8 模型加载、Float16 内存安全绑定与执行）
- [ ] T010 实现空间感知对外服务中枢骨架 `WalkMate/Core/Engine/SpatialPerceptionEngine.swift`（实现 `SpatialPerceptionEngineProtocol`）

**检查点 (Checkpoint)**: 核心数据模型与 DAP ANE 推理引擎就绪，用户故事阶段可基于此并行推进

---

## Phase 3: User Story 1 - Insta360 全景相机连接、控制 UI 与实时流预览 (Priority: P1) 🎯 MVP

**目标**: 打通物理相机 Wi-Fi 连接、实时 1080P 全景视频流解码、六轴 IMU 姿态同步以及无障碍控制预览界面

**独立测试验证**: 启动应用，点击“连接设备”，2 秒内连上相机，界面流畅渲染全景实时画面（>= 15 FPS），传感器面板实时刷新三轴姿态与加速度；点击“断开设备”安全退出。

- [ ] T011 [P] [US1] 基于 `docs/insta_x.md` 实现视频流解码桥接器 `WalkMate/Core/Camera/StreamPlayerBridge.swift`（封装 `INSCameraSessionPlayer` 硬件解码与 `CVPixelBuffer` 回调）
- [ ] T012 [P] [US1] 基于 `docs/insta_x.md` 实现六轴传感器同步器 `WalkMate/Core/Camera/GyroDataHandler.swift`（挂载 `INSCameraSessionGyroDelegate` 实时解析 `INSGyroRawItem`）
- [ ] T013 [US1] 实现相机连接与生命周期管理管道 `WalkMate/Core/Camera/CameraPipeline.swift`（实现 `CameraPipelineProtocol`，管理握手、推流与断线重连）
- [ ] T014 [P] [US1] 实现全景视频流实时渲染视图 `WalkMate/App/Views/PanoramicStreamView.swift`
- [ ] T015 [P] [US1] 实现六轴传感器遥测数据 HUD 视图 `WalkMate/App/Views/SensorTelemetryCard.swift`（采用原生 Text 元素展示状态、FPS、姿态与加速度）
- [ ] T016 [US1] 实现主控制界面 `WalkMate/App/ContentView.swift`（整合连接/断开控制按钮、全景画面与传感器卡片，确保触控尺寸 >= 48x48pt，并在连接断开/异常时触发 VoiceOver 语音播报）
- [ ] T016b [US1] 编写相机管道脱机逻辑测试 `Tests/CameraTests/CameraPipelineTests.swift`（基于 Mock 数据测试连接生命周期状态机流转、断线重连退避与时间戳匹配封装，无需连接物理相机）

**检查点 (Checkpoint)**: 用户故事 1 独立可运行验证！真机连上相机，屏幕展示实时全景流与姿态，完成首个核心增量。

---

## Phase 4: User Story 2 - 安全通行走廊几何解算 (Priority: P1)

**目标**: 实现全景深度球面反投影、重力对齐、纯动态地面拟合，以及 300x300 BEV 栅格地图上的安全通行走廊计算

**独立测试验证**: 相机正对 2 米外开启的 0.9 米房门，系统正确输出 `corridor.isPassable == true`，偏转角误差 < 5°，净宽测量误差 < 0.05 米，中心导向锚点指向门洞。

- [ ] T017 [P] [US2] 实现球面反投影器 `WalkMate/Core/Geometry/SphericalProjector.swift`（预计算 1.57MB 单位向量表 LUT，利用 `vDSP_vmul` 实现毫秒级 13 万点反投影）
- [ ] T018 [P] [US2] 实现重力对齐器 `WalkMate/Core/Geometry/GravityAligner.swift`（根据 IMU 姿态四元数旋转点云，使 Y 轴平行于重力反向向上，X-Z 轴构成水平地平面）
- [ ] T019 [US2] 实现纯动态地面估计器 `WalkMate/Core/Geometry/GroundPlaneEstimator.swift`（下半球点云 RANSAC 快速平面拟合，动态计算离地高度与地面剥离）
- [ ] T020 [US2] 实现 BEV 栅格与通行走廊规划器 `WalkMate/Core/Analysis/PassageCorridorPlanner.swift`（300x300 鸟瞰栅格构建 + EDT 欧氏距离变换，按 0.6 米人体宽度提取中心中轴线与 `targetAnchor`，确保 $z \le 0$）
- [ ] T021 [US2] 将通行走廊解算接入 `WalkMate/Core/Engine/SpatialPerceptionEngine.swift`，填充 `SpatialPerceptionResult.corridor`
- [ ] T021b [US2] 编写几何与走廊算法测试 `Tests/GeometryTests/GeometryTests.swift`（测试 1.57MB LUT 反投影精度、RANSAC 地面拟合误差 < 5cm 与 EDT 走廊提取 targetAnchor.z <= 0）

**检查点 (Checkpoint)**: 用户故事 1 与用户故事 2 协同工作！实时相机流驱动深度模型与走廊解算，成功输出开门通行导向。

---

## Phase 5: User Story 3 - 生理视角动态障碍物感知与优先级排序 (Priority: P1)

**目标**: 在人类生理视觉角度（120°~140° 前向扇区）内提取障碍物，结合距离与动态逼近速度输出 Top 3 高危障碍物

**独立测试验证**: 在前方 1.5 米放置静止椅子，左前方 2.5 米有行人迎面走来，系统稳定输出两处障碍物坐标，并将迎面走来的行人动态提升为 Top 1。

- [ ] T022 [P] [US3] 实现前向生理视角空间滤波器 `WalkMate/Core/Analysis/ObstacleSectorDetector.swift`（提取水平前向正负 60°~70°、高度 0.1m~2.0m 的障碍物点云聚类）
- [ ] T023 [US3] 在 `WalkMate/Core/Analysis/ObstacleSectorDetector.swift` 中实现动态接近速率 ($\Delta d / \Delta t$) 计算与加权评分排序算法，截断输出 Top 3 障碍物列表
- [ ] T024 [US3] 将 Top 3 障碍物输出接入 `WalkMate/Core/Engine/SpatialPerceptionEngine.swift`，填充 `SpatialPerceptionResult.obstacles`
- [ ] T024b [US3] 编写前向避障与排序测试 `Tests/PerceptionTests/ObstacleSectorTests.swift`（测试 120°~140° 生理视角过滤与动态逼近 Top 3 加权排序逻辑）

**检查点 (Checkpoint)**: 用户故事 1、2、3 完整闭环！兼具开门引导与前向防撞，具备交付给下游空间音频驱动的核心能力。

---

## Phase 6: User Story 4 - 地面跌落断层与下行阶梯几何检测 (Priority: P2)

**目标**: 监视脚下地面连续性，检测 15 厘米以上向下阶跃落差，输出跌落踩空警报

**独立测试验证**: 在距离下行台阶或地面凹坑 1.5 米处移动，系统在 1.2 米前触发 `DropOffHazardEvent` 告警。

- [ ] T025 [US4] 实现地面跌落与下行阶梯检测器 `WalkMate/Core/Analysis/DropOffDetector.swift`（检测前方地面深度突变向下落差 > 0.15 米）
- [ ] T026 [US4] 将跌落危险事件接入 `WalkMate/Core/Engine/SpatialPerceptionEngine.swift`，填充 `SpatialPerceptionResult.dropOff` 并在高危时触发快速代理回调

**检查点 (Checkpoint)**: 增加防踩空安全底线防护，满足完整前向安全性。

---

## Phase 7: User Story 5 - 动态后退意图识别与后向倒车雷达保护 (Priority: P2)

**目标**: 融合 IMU 纵向加速度与 DAP 前后深度变化率识别后退动作，瞬间反转激活后向 180° 倒车雷达模式

**独立测试验证**: 用户向后退一步，系统在 200 毫秒内检测到状态变为 `.backward`，障碍物与跌落检测自动切换为身后 180° 视角并标明 `isRearHazard == true`。

- [ ] T027 [P] [US5] 实现运动意图估计器 `WalkMate/Core/Analysis/MotionIntentEstimator.swift`（融合前后向加速度瞬时脉冲与 DAP 深度差分，输出 `UserMotionState`）
- [ ] T028 [US5] 改造 `WalkMate/Core/Analysis/ObstacleSectorDetector.swift` 与 `DropOffDetector.swift`，在状态为 `.backward` 时动态切换检测空间至后方 180° 并设置 `isRearHazard = true`
- [ ] T029 [US5] 将动态运动状态与后退雷达输出接入 `WalkMate/Core/Engine/SpatialPerceptionEngine.swift`
- [ ] T029b [US5] 编写运动状态与倒车雷达测试 `Tests/PerceptionTests/MotionIntentTests.swift`（测试 IMU 加速度脉冲+深度差分在 200ms 内识别后退动作并反转激活 180° 视角）

**检查点 (Checkpoint)**: 全功能全景空间感知闭环达成！前行看前向，后退防身后，全向 360 度优势发挥至极致。

---

## Phase 8: Polish & Cross-Cutting Concerns (工程润色与真机全链路验证)

**目标**: 工程自动构建、无障碍审查与全链路延迟压测

- [ ] T030 执行 `xcodegen generate` 重新同步工程配置，并执行 `xcodebuild` 验证全项目静态分析与零警告编译 (Zero Warnings)
- [ ] T031 [P] 审查并验证全工程代码注释符合宪章原则五（全中文注释先于核心逻辑），日志采用 Swift `Log` 工具且无 `print()`
- [ ] T032 [P] 审查全界面 VoiceOver 读屏与触控尺寸无障碍合规性（所有按钮触控目标 >= 48x48pt）
- [ ] T033 执行 `specs/001-dap-spatial-perception/quickstart.md` 场景 5 进行 60 秒持续推流压测，验证全链路单帧端到端延迟严格小于 130 毫秒

---

## 依赖关系与执行拓扑 (Dependencies & Execution Order)

```text
Phase 1: Setup (T001 ~ T003)
  ↓
Phase 2: Foundational (T004 ~ T010) [阻塞后续所有用户故事]
  ↓
Phase 3: User Story 1 (T011 ~ T016b) [MVP 核心硬件数据源]
  ↓
Phase 4: User Story 2 (T017 ~ T021b) [空间通道导向]
  ↓
Phase 5: User Story 3 (T022 ~ T024b) [前向避障]
  ↓
Phase 6: User Story 4 (T025 ~ T026) [防踩空] & Phase 7: User Story 5 (T027 ~ T029b) [后退雷达]
  ↓
Phase 8: Polish (T030 ~ T033) [构建、无障碍与延迟验收]
```

### 并行开发机会
- **Phase 1**: T002 与 T003 可并行；
- **Phase 2**: T005, T006, T008 可并行开发；
- **Phase 3**: T011（解码）与 T012（IMU）可并行，T014 与 T015 界面组件可并行；
- **Phase 4**: T017（反投影 LUT）与 T018（重力对齐）可并行；
- **Phase 5 & 6 & 7**: 几何底层就绪后，避障聚类（US3）、跌落检测（US4）与运动意图（US5）的算法实现可并行开发。

---

## 实施策略与增量交付 (Implementation Strategy)

1. **MVP 阶段（User Story 1）**：完成 Phase 1、Phase 2 与 Phase 3，在真机上验证相机连接、全景实时画面流畅播放与 IMU 传感器刷新；
2. **第二增量（User Story 2 + User Story 3）**：完成空间点云、地面剥离、开门走廊规划与前向 Top 3 避障，向外输出与空间音频兼容的三维数据；
3. **第三增量（User Story 4 + User Story 5）**：完成防踩空跌落检测与后退倒车雷达模式，达成全向 360 度安全闭环；
4. **最终验收**：压测端到端延迟 < 130ms，验证 VoiceOver 无障碍合规。
