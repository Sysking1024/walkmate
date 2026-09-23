# 任务清单：003-minimal-field-pilot 极简真机实测与轻量导航闭环 (Tasks)

**输入**: 来自 `specs/003-minimal-field-pilot/` 的全部设计产物（[plan.md](./plan.md), [spec.md](./spec.md), [data-model.md](./data-model.md), [contracts/pilot_view_model_contract.md](./contracts/pilot_view_model_contract.md), [research.md](./research.md), [quickstart.md](./quickstart.md)）

**开发与组织原则**:
1. **现有资产 100% 复用（底层零改动）**：DAP ANE 推理（98ms）、Accelerate 硬件预处理（11ms）、LUT 球面投影、RANSAC 地面拟合、360° 聚类与 MOT 追踪、BEV 路径规划以及 SpatialAudioPlayer 3D 双耳音频中枢全部原样复用，底层代码零修改；
2. **外科手术式修改**：仅修改 `ContentView.swift`、`Info.plist` 与 `project.yml` 三个现有文件，新增一个测试文件 `PilotViewModelTests.swift`；
3. **测试先行 (TDD)**：在修改 UI 与 ViewModel 逻辑前，先行编写单元测试用例，驱动业务层前向 130° 过滤与启停状态机实现。

---

## 格式说明：`- [ ] [TaskID] [P?] [Story?] 任务描述与文件路径`

- **[P]**: 标记可并行执行的任务（不同文件、无未完成依赖）
- **[Story]**: 用户故事编号（[US1], [US2], [US3]），仅在用户故事阶段使用
- 所有任务均包含明确具体的文件路径

---

## Phase 1: Setup (系统权限与工程配置补全)

**目标**: 配置 iOS 后台音频权限，补齐测试工程 Targets，确保锁屏不挂起与测试套件齐备

- [x] T001 [P] 在 `WalkMate/Info.plist` 中添加 `UIBackgroundModes` 键并注入 `audio` 模式，确保视障测试者息屏或将手机放入口袋行走时音频与推理不被系统挂起
- [x] T002 在 `WalkMate/project.yml` 中补齐 `AudioTests` 与新增 `AppTests` 测试目标及 scheme，并执行 `xcodegen generate` 重新生成 `WalkMate.xcodeproj`，确保所有测试模块纳入 Xcode 工程构建


---

## Phase 2: Foundational (现有算法与底座资产确认)

**目标**: 明确现有底座算法资产完备性，固化底层接口边界（本阶段全部为现有资产，零代码编写）

- [x] T002b 确认并冻结现有已实现算法底层：`AcceleratePreprocessor.swift`、`DAPEngine.swift`、`SphericalProjector.swift`、`GravityAligner.swift`、`GroundPlaneEstimator.swift`、`ObstacleDetector.swift`、`ObstacleTracker.swift`、`PassageRoutePlanner.swift`、`SpatialPerceptionEngine.swift`、`SpatialAudioPlayer.swift` 与 `CameraPipeline.swift` 全部 100% 保持现状，本特性严禁修改其底层代码

**检查点 (Checkpoint)**: 工程配置与权限就绪，底座资产完备冻结，进入用户故事实施阶段。

---

## Phase 3: User Story 1 - 全屏沉浸式实时全景视频预览与双按钮极简控制 (Priority: P1) 🎯 MVP

**目标**: 移除遥测 HUD 与冗余卡片，将全景视频流铺满全屏，左下角放置连接按钮，右下角放置感知启停按钮，保证无障碍触控尺寸与对比度

**独立测试验证**: 启动应用，确认主屏无遥测卡片，视频预览区填满屏幕；点击左下角按钮顺利连接/断开相机，右下角按钮在未连接时禁用、连接后激活。

### 1. 测试先行 (TDD) ⚠️ 在实现前编写测试用例
- [ ] T003 [P] [US1] 创建 `Tests/AppTests/PilotViewModelTests.swift` 并编写全屏 UI 与双按钮状态测试（断言相机连接状态机流转、左下角连接/断开切换指令、以及右下角感知按钮在未连接时禁用、已连接时激活）

### 2. 核心界面实现
- [ ] T004 [US1] 重构 `WalkMate/App/ContentView.swift` 界面布局：移除 `SensorTelemetryCard` 引用与 `ScrollView`，采用 `ZStack` 将 `PanoramicStreamView(previewView: viewModel.previewView, isConnected: ..., isFullScreen: true)` 铺满全屏背景（`.ignoresSafeArea()`），底部左下角固定放置相机连接/断开按钮，右下角固定放置开始/停止感知按钮，触控靶心尺寸严格设为 $56\times 56\text{pt}$（满足 $\ge 48\text{pt}$ 无障碍底线），对比度严格 $\ge 4.5:1$，配置 VoiceOver 语义标签、交互提示与状态语音播报

**检查点 (Checkpoint)**: 用户故事 1 交付！界面纯净全屏呈现，相机推流与双按钮触控完全独立可用。

---

## Phase 4: User Story 2 - 感知与空间音频启停独立控制 (Priority: P1)

**目标**: 将“相机推流预览”与“大模型深度感知计算”生命周期解耦，点击右下角“开始”后才抓取视频帧送入模型并启动音频，点击“停止”后立即停止推理并静音；覆盖掉线安全重置与响应延迟指标

**独立测试验证**: 相机连接推流时，模型不工作；点击右下角“开始”，后台开始处理帧流并输出音频；点击“停止”，音频立即静音且停止向模型投递帧，全屏推流持续流畅；相机意外掉线时，自动停止感知并静音。

### 1. 测试先行 (TDD) ⚠️ 在实现前编写测试用例
- [ ] T005 [US2] 在 `Tests/AppTests/PilotViewModelTests.swift` 中扩展感知独立启停状态机测试（断言 `isPerceiving` 切换、`didReceiveFrame` 仅在 `isPerceiving == true` 时投递给引擎、停止感知时音频播放器调用 `reset()` 立即静音；断言相机意外掉线 `.failed`/`.noConnection` 时自动将 `isPerceiving` 重置为 `false` 并静音；验证启停与静音响应延迟满足 SC-002 性能指标）

### 2. 核心状态机实现
- [ ] T006 [US2] 在 `WalkMate/App/ContentView.swift` 的 `CameraViewModel` 中引入 `isPerceiving: Bool` 响应式状态与 `togglePerception()` 控制方法，在 `didReceiveFrame` 中添加 `isPerceiving` 门禁过滤，实现启停时与 `SpatialAudioPlayer.shared.start()/reset()` 及 `perceptionEngine?.start()/stop()` 的联动；并在 `didUpdateState` 中实现掉线安全自愈（`.failed`/`.noConnection` 时自动重置感知状态并静音）

**检查点 (Checkpoint)**: 用户故事 2 交付！大模型推理与空间音频拥有独立受控的启停机制，具备掉线自愈能力，不额外浪费 iPhone 电量与发热。

---

## Phase 5: User Story 3 - 业务层前向扇区（130°）及 1 米极近避障与首航路点导航 (Priority: P1)

**目标**: 在业务层对全景障碍物执行前向 130°（$|\text{azimuth}| \le 65^\circ$）与 1 米近身筛选，仅对前向贴身威胁触发双音金属报警，身后绝对静音；提取首航路点驱动 1.1s 领路脚步声；加入异步飞行帧门禁

**独立测试验证**: 前方 0.8 米障碍物触发双音报警，身后 0.8 米障碍物完全静音；有效通行路线驱动正前方领路脚步声，路线受阻自动静音；停止感知后异步回调绝不唤醒音频。

### 1. 测试先行 (TDD) ⚠️ 在实现前编写测试用例
- [ ] T007 [US3] 在 `Tests/AppTests/PilotViewModelTests.swift` 中扩展业务层前向扇区与避障导航过滤测试（断言身侧/身后障碍物静音过滤、前向 $130^\circ$ 且 $\le 1.0\text{m}$ 最近障碍物坐标提取并调用 `SpatialAudioPlayer.setObstacleTarget`、路线第 1 个航路点提取并调用 `SpatialAudioPlayer.setNavigationTarget`、无障碍物/无路线时传入 `nil` 静音；断言 `isPerceiving == false` 时收到异步感知回调被严格静默拦截）

### 2. 核心业务过滤实现
- [ ] T008 [US3] 在 `WalkMate/App/ContentView.swift` 的 `CameraViewModel` 中接入 `SpatialAudioPlayer.shared`，在 `didProduceObstacles` 与 `didProducePassableRoute` 入口处统一加入 `guard isPerceiving else { return }` 异步门禁；实现前向 130° 扇区（$|\text{azimuth}| \le 65^\circ$）与 $\le 1.0\text{m}$ 最小距离筛选，在 `didProducePassableRoute` 中实现 `waypoints.first` 首航路点导引

**检查点 (Checkpoint)**: 用户故事 3 交付！真机实测三大支柱（全屏预览 + 独立启停 + 前向避障与领路）全部打通形成闭环。

---

## Phase 6: Polish & Cross-Cutting Concerns (全量回归与真机部署就绪)

**目标**: 全量测试套件 100% 绿灯回归、静态检查零警告、完成真机实测交付准备

- [ ] T009 运行全工程自动化单元测试套件（执行 `xcodebuild test`，涵盖 `AppTests`, `AudioTests`, `CameraTests`, `InferenceTests`, `GeometryTests`, `PerceptionTests`, `ToolkitTests`），断言全量用例 100% 绿灯通过
- [ ] T010 重新执行 `xcodegen generate` 并执行 `xcodebuild -destination "generic/platform=iOS" build`，确保零编译错误、零警告，输出真机部署最终 App 产物

---

## 依赖拓扑与执行顺序 (Dependencies & Execution Order)

```text
Phase 1: Setup (T001 Info.plist 权限 & T002 project.yml 工程生成)
  ↓
Phase 2: Foundational (T002b 确认底座资产 100% 复用)
  ↓
┌────────────────────────────────────────────────────────┐
│ Phase 3: User Story 1 (全屏 UI 与双按钮)                │
│ [测试先行] T003 (UI 与状态机测试) → [实现] T004 (ContentView 重构) │
└───────────────────────────┬────────────────────────────┘
                            ↓
┌────────────────────────────────────────────────────────┐
│ Phase 4: User Story 2 (感知启停独立控制与掉线自愈)      │
│ [测试先行] T005 (启停门禁测试) → [实现] T006 (isPerceiving 联动) │
└───────────────────────────┬────────────────────────────┘
                            ↓
┌────────────────────────────────────────────────────────┐
│ Phase 5: User Story 3 (前向 130° 避障与首航路点导引)     │
│ [测试先行] T007 (扇区与过滤测试) → [实现] T008 (ViewModel 音频驱动) │
└───────────────────────────┬────────────────────────────┘
                            ↓
Phase 6: Polish & Regression (T009 全量测试回归 & T010 零警告真机构建)
```

---

## 并行执行机会 (Parallel Opportunities)

- **Phase 1 内部**：T001 (`Info.plist`) 与 T002 (`project.yml`) 可完全并行修改与配置；
- **测试用例编写**：T003、T005、T007 均位于 `Tests/AppTests/PilotViewModelTests.swift` 中，按用户故事阶段顺序增量添加对应测试套件，严格保证在对应业务代码实现前完成测试编写（TDD）。

