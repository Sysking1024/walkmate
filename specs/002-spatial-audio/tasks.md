# 任务清单：002-spatial-audio 空间音频辅助导航与康复激励播放器

**输入**：设计文档位于 `specs/002-spatial-audio/`（`plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`）  
**前置条件**：`specs/002-spatial-audio/plan.md`（已就绪）、`specs/002-spatial-audio/spec.md`（已就绪）  
**测试策略**：遵循宪章原则十三与敏捷规范，采用**测试先行（TDD）**模式，先写单元测试断言，再编写实现代码，确保 100% 覆盖。

---

## 格式规范：`- [ ] [TaskID] [P?] [Story?] 任务描述（包含明确文件路径）`

- **[P]**：可并行执行的任务（不同文件，无未完成依赖）
- **[Story]**：所属用户故事标签（`[US1]`、`[US2]`、`[US3]`，仅用于用户故事阶段）
- 每个任务必须指明具体的文件路径

---

## 现有资产与算法复用备忘（零重复开发）

- **`WalkMate/Core/Toolkits/SpatialAudioKit.swift`**：`[现有，无需改动]`，直接复用其 `toSpatialAudioRenderParams(position:boundingSize:)` 现成算法转换 `AVAudio3DPoint` 与距离衰减。
- **`WalkMate/Core/Perception/ObstacleDetector.swift`**：`[现有，无需改动]`，输出现成 `ObstacleItem.position`。
- **`WalkMate/Core/Perception/PassageRoutePlanner.swift`**：`[现有，无需改动]`，输出现成 `RouteWaypoint.position`。
- **`WalkMate/Core/Engine/SpatialPerceptionEngine.swift`**：`[现有，无需改动]`，全链路数据总成无需改动。

---

## Phase 1: Setup（共享基础设施与目录初始化）

**目标**：初始化音频子系统代码与测试目录骨架，确保工程编译 Target 配置正确。

- [X] T001 在工程中创建音频模块与测试目录结构 `WalkMate/Core/Audio/` 与 `Tests/AudioTests/`

---

## Phase 2: Foundational（底层数学合成器与音频图基础）

**目标**：构建纯代码参数化音频合成器与基础 `AVAudioEngine` 3D 声学环境节点，阻塞所有后续用户故事。

- [X] T002 [P] [测试先行] 编写纯代码参数化音频合成器测试套件 `Tests/AudioTests/ProceduralAudioSynthesizerTests.swift`，断言金属音（4410点）、脚步音（3528点）与奖励和弦音（17640点）的 PCM 采样点数、44.1kHz 单声道格式及 $[-1.0, 1.0]$ 幅度有效性
- [X] T003 [P] 实现纯代码数学参数化音频合成器 `WalkMate/Core/Audio/ProceduralAudioSynthesizer.swift`，基于 DSP 物理建模在内存中实时生成三种标准 PCM Buffer，使 T002 测试通过
- [X] T004 实现空间音频播放器基础骨架 `WalkMate/Core/Audio/SpatialAudioPlayer.swift`，初始化 `AVAudioEngine` 与 `AVAudioEnvironmentNode`（配置 `.HRTFHQ` 双耳模式），复用 `SpatialAudioKit.toSpatialAudioRenderParams` 实现坐标映射（默认点声源包围盒 `0.2m`），挂载 3 个专用 `AVAudioPlayerNode`，提供 `start()`、`stop()` 与 `reset()` 生命周期契约方法

**检查点**：基础音频图与内存声音合成器就绪，全部通过基础编译与测试。

---

## Phase 3: User Story 1 - 危险障碍物金属撞击双音确认警示 (Priority: P1) 🎯 MVP

**目标**：实现障碍物三维方位固定 800ms 间隔播放 2 次金属撞击音，机制与策略分离，双响播完自动安静，高频重复调用平滑移动声源防重入爆音。  
**独立测试标准**：调用 `setObstacleTarget(position:)` 传入左侧坐标，左声道间隔 800ms 发出 2 声金属撞击音后自动静音；期间重复调用不打断重入；传入 nil 立即静音。

### 测试先行
- [X] T005 [P] [US1] 编写障碍物双音状态机与防重入测试用例于 `Tests/AudioTests/SpatialAudioPlayerTests.swift`（验证 800ms 间隔双响、completed 自动静音、高频重复调用防重入平滑移动与坐标插值、双响期间脚步声 Ducking 压低至 30% 与恢复、nil 及 reset 立即停止）

### 实现
- [X] T006 [US1] 在 `WalkMate/Core/Audio/SpatialAudioPlayer.swift` 中实现 `setObstacleTarget(position: SIMD3<Float>?)` 与 `ObstacleAlertState` 发声状态机，以 800ms 间隔驱动播放 2 次金属撞击音并防重入，支持坐标插值平滑与发声期间对脚步声节点的自动 Ducking 压低至 30% 与恢复，使 T005 测试通过

**检查点**：MVP 交付达成！核心避障双音确认警示功能可独立运行与完整测试。

---

## Phase 4: User Story 2 - 安全可行路线前方领路脚步声 (Priority: P1)

**目标**：以成人自然行走步频（约 1.0s ~ 1.2s 一步），在前方安全航路点三维方位周期性播放轻快踏地声，引导用户循声前行；传入 nil 自动静音。  
**独立测试标准**：调用 `setNavigationTarget(position:)` 传入前方坐标，双耳中央以 1.1s 步速稳定传出自然脚步声；坐标右偏时声源右移；传入 nil 定时器停止。

### 测试先行
- [X] T007 [P] [US2] 编写导航脚步声自然步频与方位追踪测试用例于 `Tests/AudioTests/SpatialAudioPlayerTests.swift`（验证 1.0s~1.2s 步频定时调度、声源方位平移与 nil 安全取消）

### 实现
- [X] T008 [US2] 在 `WalkMate/Core/Audio/SpatialAudioPlayer.swift` 中实现 `setNavigationTarget(position: SIMD3<Float>?)` 与后台步频调度定时器，循环播放轻快脚步声，使 T007 测试通过

**检查点**：导航脚步声领路功能就绪，可与 US1 共同发声并各自保持独立语义。

---

## Phase 5: User Story 3 - 行走康复训练达标激励音与自动让位 (Priority: P2)

**目标**：单次触发播放上行大三和弦清脆和声（约 0.4s），播放期间自动轻微压低背景脚步声以突出表扬成就感，播完后自然恢复。  
**独立测试标准**：调用 `playRewardSound()`，单次播发暖心和弦；脚步声音量平滑淡出压低至 30%，和弦播完后音量平滑恢复 100%。

### 测试先行
- [X] T009 [P] [US3] 编写康复激励音单次触发与脚步声压音让位测试用例于 `Tests/AudioTests/SpatialAudioPlayerTests.swift`（验证单次和弦触发、播放期间脚步声音量平滑压低至 30% 与播完恢复 100%）

### 实现
- [X] T010 [US3] 在 `WalkMate/Core/Audio/SpatialAudioPlayer.swift` 中实现 `playRewardSound()`，调度和弦专用节点并在发声期间自动对脚步声节点执行音量 Ducking 压低至 30% 与平滑恢复，使 T009 测试通过

**检查点**：三大用户故事全量实现，具备防撞双音、领路脚步、康复激励完整体验。

---

## Phase 6: Polish & Cross-Cutting Concerns（系统健壮性与回归测试）

**目标**：补齐系统级音频打断处理，并执行全工程全量回归测试，达到交付标准。

- [ ] T011 在 `WalkMate/Core/Audio/SpatialAudioPlayer.swift` 中集成 `AVAudioSession` 中断监听（电话呼入、Siri 激活、耳机拔出断开），实现自动安全暂停与恢复
- [ ] T012 编写全景图驱动空间音频端到端集成测试 `Tests/PerceptionTests/PerceptionAudioIntegrationTests.swift`，加载真实样本 `tmp/pano_indoor.jpg` 注入 `SpatialPerceptionEngine`，在感知代理回调中驱动 `SpatialAudioPlayer.shared.setObstacleTarget` 与 `setNavigationTarget`，验证真实图像输入下全链路闭环，断言零崩溃、零主线程掉帧与声源坐标正确绑定
- [ ] T013 运行全工程完整回归测试套件（执行 `InferenceTests`, `GeometryTests`, `PerceptionTests`, `ToolkitTests`, `AudioTests` 全量用例并断言接口时延 $\le 20\text{ms}$），确保 100% 绿灯且零编译警告

---

## 故事依赖与并行执行关系 (Dependencies & Parallel Opportunities)

```text
Phase 1: Setup (T001)
         ↓
Phase 2: Foundational (T002 测试 → T003 合成器 → T004 播放器骨架)
         ↓
┌───────────────────────────────────────┐
│ Phase 3: US1 障碍物双音警示 (T005 → T006) 🎯 MVP
└──────────────────┬────────────────────┘
                   ↓
┌───────────────────────────────────────┐
│ Phase 4: US2 导航脚步领路声 (T007 → T008)
└──────────────────┬────────────────────┘
                   ↓
┌───────────────────────────────────────┐
│ Phase 5: US3 康复和弦激励音 (T009 → T010)
└──────────────────┬────────────────────┘
                   ↓
Phase 6: Polish & 全量回归 (T011 → T012 → T013)
```

- **并行机会**：
  - T002（合成器测试）与 T004（播放器骨架）可由不同开发单元并行编写；
  - 在 Phase 2 就绪后，US1、US2、US3 的测试用例（T005, T007, T009）完全基于不同接口特性，可并行编写。
