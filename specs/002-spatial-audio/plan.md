# 技术实现计划：002-spatial-audio 空间音频辅助导航与康复激励播放器

**特性分支**：`002-spatial-audio` | **创建日期**：2026-09-23 | **规范文档**：[spec.md](spec.md)  
**输入**：来自 `specs/002-spatial-audio/spec.md` 的功能规范与澄清决议

---

## 概述与核心目标 (Summary)

本项目为 Insta360 视障辅助黑客松项目的音频交互中枢。本特性旨在构建一套面向视障行走的极简、低延迟、零外部资源依赖的原生空间音频播放服务（`SpatialAudioPlayer`），实现：
1. **避障警示**：在危险障碍物三维方位以固定 800ms 间隔播放 2 次金属撞击声（“当……当”），双音确认后自动静音，彻底消除听觉轰炸；
2. **路径领路**：在前方安全航路点方位按成人自然步频（约 1.0s ~ 1.2s）持续播放轻快脚步声，引导用户循声前行；
3. **康复激励**：单次触发播放上行大三和弦清脆和声（八音盒音色），给予视障者正向成就反馈；
4. **纯代码合成与零文件依赖**：全套音效由 DSP 数学公式在内存实时合成，不依赖任何外部 MP3/WAV 文件。

---

## 技术上下文 (Technical Context)

- **开发语言与版本**：Swift 6.0 / iOS 18+ SDK
- **核心系统依赖**：原生 `AVFoundation`（`AVAudioEngine`, `AVAudioEnvironmentNode`, `AVAudioPlayerNode`, `AVAudioPCMBuffer`）
- **复用既有模块**：项目内现有纯计算工具箱 `SpatialAudioKit`，零引入任何第三方库
- **数据持久化**：无（纯内存与音频图运行时状态）
- **测试框架**：原生 `XCTest`
- **目标平台**：iOS 18+（iPhone 15 / iPhone 16 等 A 系列芯片设备及模拟器）
- **性能红线**：
  - 内存 PCM 音频合成耗时 $\le 1\text{ms}$，内存占用 $\le 100\text{KB}$；
  - 声源目标空间坐标位移响应时延 $\le 20\text{ms}$；
  - 主线程调用耗时 $\le 0.5\text{ms}$（内部所有节点与定时器调度均在后台串行队列执行）。

---

## 宪章对齐检查 (Constitution Check)

- **原则一（项目背景）**：✅ 符合。为 Insta360 黑客松极简 Demo 打造，专精苹果生态原生音频能力，快速落地。
- **原则二（极致低延迟）**：✅ 符合。基于系统底层 `AVAudioEngine` 原生音频图与 CoreAudio 管道，零多余抽象，调度开销在微秒级。
- **原则四（绝对无障碍适配）**：✅ 符合。技术文档排版纯文本化，杜绝屏幕阅读器不友好的 ASCII 流程图；声学交互采用“双音确认+自然步频”，杜绝听觉过载。
- **原则五（严格统一中文）**：✅ 符合。代码标识符采用标准英文命名，所有设计文档、任务、注释与日志严格全中文。
- **原则六（Git 提交规范）**：✅ 符合。纯中文 Commit，分步推进。
- **原则七（依赖库使用与引入）**：✅ 符合。100% 使用 Apple 原生标准库，严禁引入任何第三方依赖。
- **原则九（统一业务日志埋点）**：✅ 符合。使用系统统一 `Log.info / Log.warning` 工具，严禁裸调用 `print()`。
- **原则十（质量门禁）**：✅ 符合。全工程构建与测试 100% 保持通过。

---

## 现有资产与算法复用矩阵 (Algorithm & Code Reuse Inventory)

在本次开发中，严格区分**“现有无需改动”**、**“现有已实现算法直接复用”**与**“增量新开发”**的界限，绝不重复造轮子：

### 1. 现有代码资产（100% 现有，完全无需修改代码）

- **`WalkMate/Core/Toolkits/SpatialAudioKit.swift`**：
  - **状态**：**[现有，无需改动]**
  - **已实现算法与复用说明**：
    1. 原生 3D 空间音频坐标映射与衰减角算法：已在 `SpatialAudioKit.toSpatialAudioRenderParams(position:boundingSize:)` 中实现，将相对坐标 $(x, y, z)$ 直接转换为 `AVAudio3DPoint` 与距离倒数衰减系数（0.5m 处为 1.0, 5.0m 处衰减至 0.1）。`SpatialAudioPlayer` 将**直接调用该纯函数**，对于障碍物与导航点声源统一传入标准包围盒 `SIMD3<Float>(0.2, 0.2, 0.2)`，严禁另起炉灶重写坐标换算。
    2. 双声道声相平衡算法：已在 `SpatialAudioKit.toStereoFallbackParams(azimuth:distance:)` 中实现，必要时用于立体声降级。
    3. 钟表逆空间编码：已在 `SpatialAudioKit.toClockDirection` 中实现，供语音提示复用。
- **`WalkMate/Core/Perception/ObstacleDetector.swift`**：
  - **状态**：**[现有，无需改动]**
  - **说明**：已实现全场景障碍物聚类、距离解算与 $< 0.3\text{m}$ 盲区规约，输出的 `ObstacleItem.position` 供业务层直接取用传入音频播放器。
- **`WalkMate/Core/Perception/PassageRoutePlanner.swift`**：
  - **状态**：**[现有，无需改动]**
  - **说明**：已实现人体通行净宽与滞后状态机，输出的连续 `RouteWaypoint.position` 供业务层直接取用传入音频播放器。
- **`WalkMate/Core/Engine/SpatialPerceptionEngine.swift`**：
  - **状态**：**[现有，无需改动]**
  - **说明**：感知总成流水线已完整就绪，通过 Delegate 和 AsyncStream 分发数据，无需改动。

### 2. 增量新建代码资产（本特性新增）

- **`WalkMate/Core/Audio/ProceduralAudioSynthesizer.swift`**：
  - **状态**：**[新增]**
  - **职责**：纯数学参数化音频合成器。基于 DSP 物理建模在内存中合成金属敲击声（4410点）、轻快脚步声（3528点）、康复激励和弦音（17640点）三套标准单声道 PCM Buffer。
- **`WalkMate/Core/Audio/SpatialAudioPlayer.swift`**：
  - **状态**：**[新增]**
  - **职责**：空间音频播放服务中枢与对外门面。管理 `AVAudioEngine` 与 `AVAudioEnvironmentNode`（HRTF 双耳模式），挂载 3 个专用播放节点，提供 `setObstacleTarget`（800ms 双响、坐标插值平滑与发声期间脚步声自动压音至 30%）、`setNavigationTarget`（自然步频领路）、`playRewardSound`（瞬态和弦与自动压音至 30%）以及 `reset()` 全局重置四大核心接口。
- **`Tests/AudioTests/ProceduralAudioSynthesizerTests.swift`**：
  - **状态**：**[新增]**
  - **职责**：纯代码音频合成器单元测试，验证各音效 PCM 采样点数、幅度范围（$[-1.0, 1.0]$）及有效性。
- **`Tests/AudioTests/SpatialAudioPlayerTests.swift`**：
  - **状态**：**[新增]**
  - **职责**：空间音频播放器状态机与调度单元测试，验证双音确认节奏、步频定时器、和弦与避障双响触发时的脚步声让位（Ducking 压低至 30% 及恢复）、声源坐标平滑插值以及空值/`reset()` 静音逻辑。
- **`Tests/PerceptionTests/PerceptionAudioIntegrationTests.swift`**：
  - **状态**：**[新增]**
  - **职责**：全景图端到端联动集成测试。加载真实样本 `tmp/pano_indoor.jpg` 注入 `SpatialPerceptionEngine`，并在感知代理回调中驱动 `SpatialAudioPlayer.setObstacleTarget` 与 `setNavigationTarget`，验证真实图像输入下视觉到空间音频的完整闭环，断言零崩溃、零线程死锁与正确发声。

---

## 项目代码结构 (Project Code Structure)

### 本特性规划涉及的工程文件全景（无歧义标注）

```text
WalkMate/
├── Core/
│   ├── Audio/                                          # [新增目录] 空间音频播放子系统
│   │   ├── ProceduralAudioSynthesizer.swift            # [新增] 纯数学内存 PCM 物理建模合成器
│   │   └── SpatialAudioPlayer.swift                    # [新增] 空间音频播放服务中枢与门面单例
│   ├── Toolkits/
│   │   └── SpatialAudioKit.swift                       # [现有，无需改动] 提供 3D 音频坐标与衰减换算纯算法
│   ├── Perception/
│   │   ├── ObstacleDetector.swift                      # [现有，无需改动] 障碍物检测与极坐标换算
│   │   └── PassageRoutePlanner.swift                   # [现有，无需改动] 可行路径折线点解算
│   └── Engine/
│       └── SpatialPerceptionEngine.swift               # [现有，无需改动] 感知全链路流水线总成
└── Tests/
    ├── AudioTests/                                     # [新增目录] 空间音频单元测试套件
    │   ├── ProceduralAudioSynthesizerTests.swift       # [新增] 内存声音合成算法单元测试
    │   └── SpatialAudioPlayerTests.swift               # [新增] 播放器生命周期、双响状态机与防重入测试
    └── PerceptionTests/
        ├── PerceptionEngineTests.swift                 # [现有，无需改动] 感知引擎基础测试
        └── PerceptionAudioIntegrationTests.swift       # [新增] 全景图驱动空间音频端到端集成测试
```

---

## 阶段规划与交付物 (Phases & Deliverables)

### Phase 0: 概念与技术调研 (已完成)
- 产物：`specs/002-spatial-audio/research.md`
- 结论：确立 `AVAudioEngine + AVAudioEnvironmentNode (HRTF)` 架构；确立纯代码物理建模合成参数；明确对 `SpatialAudioKit` 既有坐标换算算法的 100% 复用。

### Phase 1: 契约设计与数据建模 (已完成)
- 产物：
  - `specs/002-spatial-audio/data-model.md`
  - `specs/002-spatial-audio/contracts/spatial-audio-player-api.md`
  - `specs/002-spatial-audio/quickstart.md`
- 结论：确立两大状态目标接口与单次激励接口；确立“机制与策略分离”原则（触发时机由业务层完全主控，播放器负责 800ms 双响与防重入爆音）。

### Phase 2: 任务分解与执行准备 (待启动)
- 后续通过 `/speckit-tasks` 生成有序的任务清单 `tasks.md`，指导实现。
