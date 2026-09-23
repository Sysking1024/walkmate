# 技术实施规划书：空间感知实测多模态数据采集与离线回放系统 (004-perception-data-collector)

**特性分支**: `004-perception-data-collector` | **日期**: 2026-09-23 | **需求规范**: [spec.md](./spec.md)

---

## 一、 方案摘要 (Summary)

针对真机实测中由于地面杂波与通道门限严格导致频发“只有敲击声、没有脚步声、大量‘前方受阻’”的精度调优难题，构建**低开销实测多模态数据采集与离线回放调优闭环系统**。
方案采用**分级动态异步存储策略**：
1. **高频时序遥测（10~30Hz）**：通过专用后台异步队列与环形缓冲区，将微秒时间戳、IMU 姿态角、地面拟合参数 $(A, B, C, D)$、估算相机高度、障碍物三维列表与航路点实时流式写入行式 JSON (`telemetry.jsonl`)，零 I/O 阻塞；
2. **低频关键帧快照（1~2Hz）**：抽样持久化压缩全景图（JPEG）与深度矩阵（二进制）；
3. **极简交互与传输**：将主界面右上角原有“拷贝日志”按钮升级替换为“实测采集与日志”复合入口，录制完成后利用工程既有的 `SSZipArchive` 极速打包并通过系统原生 **AirDrop（隔空投送）** 秒传 Mac；
4. **离线高保真回放**：在工程内实现 XCTest 原生回放套件（`ReplayTests`），开发者在 Mac 上无需出门即可逐帧重现真实路况、微调算法参数并自动化评估航路点生成率提升指标。

---

## 二、 技术上下文与架构指标 (Technical Context)

* **编程语言与版本**: Swift 5.9 (开启 `@unchecked Sendable` 并发安全检查，对齐 iOS 17.0+)
* **主要系统框架与既有依赖**:
  * Foundation / Combine / SwiftUI (UI 响应式状态管理)
  * CoreVideo / Accelerate / ImageIO (无损压缩与图像处理)
  * `SSZipArchive.xcframework` (**既有依赖**，位于 `WalkMate/Frameworks/SSZipArchive.xcframework`，用于目录 zip 打包，**零新引入依赖**)
* **存储机制**:
  * 移动端沙盒文件系统: `Documents/Sessions/<sessionId>/`
  * 时序文件: 流式追加写入的 JSON Lines (`telemetry.jsonl`)
  * 视觉文件: `frames/<timestamp>.jpg` 与 `depths/<timestamp>.bin`
* **测试框架**: XCTest (包含自动化单元测试与离线回放仿真套件)
* **运行平台目标**: iOS 17.0+ (真机 iPhone 15 / 16 系列) & macOS (开发机离线回放)
* **性能指标约束**:
  * 采集开启时视频推流与感知主链路平均帧率波动 $< 5\%$
  * 端到端处理延迟增加 $< 10\text{ms}$
  * 单次 3 分钟外场行走采集数据包总体积 $< 50\text{MB}$
  * 移动端本地打包压缩耗时 $< 3\text{秒}$
* **存储保护阈值**: 设备空闲存储空间 $< 500\text{MB}$ 时强制阻断录制以保护系统

---

## 三、 宪章符合性核查 (Constitution Check)

*门禁检查：必须严格对齐 `.specify/memory/constitution.md` 核心原则。*

| 宪章原则 | 核查要求 | 本规划实施措施 | 判定 |
| :--- | :--- | :--- | :---: |
| **原则二：极致低延迟** | 严禁写盘阻塞推理与音频实时性 | 采用独立后台 Utility QoS 串行队列与环形内存缓冲，推理主线程仅做内存投递，闪存 I/O 绝对异步。 | **通过** |
| **原则四：绝对无障碍适配** | UI 符合读屏规范与双轨定律 | 录制按钮提供无障碍专用标签（“开始实测数据采集”、“停止实测采集，当前已录制X分X秒”），操作具备全局系统 Announcement 朗读。 | **通过** |
| **原则五：严格统一中文规范** | 业务注释、文档、UI 文本全中文 | 规划文档、代码注释、错误信息、日志消息全量中文；代码标识符与结构化 Log Level 遵循行业英文标准。 | **通过** |
| **原则七：依赖库引入规范** | 严禁盲目引入第三方依赖 | 会话打包 100% 复用工程既有的 `SSZipArchive.xcframework`，分享采用系统原生 `UIActivityViewController`，零新外部依赖引入。 | **通过** |
| **原则十二：极致简朴与外科手术** | 最小化 Diff，杜绝过度设计 | 离线回放以 XCTest 原生套件交付，不设计复杂多余的桌面 GUI 应用；界面上直接复用右上角既有按钮位置。 | **通过** |
| **原则十三：调试验证与测试先行** | 具备量化测试与验证能力 | 规划了 `SessionStorageManagerTests`、`PerceptionCollectorTests` 以及 `PerceptionReplayTests`。 | **通过** |

---

## 四、 既有资产、修改点与新增架构清单 (Project Assets Inventory)

为严格落实用户关于“明确表述哪些是既有无需改动、哪些需要修改、哪些既有算法已被复用”的要求，特建立以下无歧义清单：

### 1. 既有已实现、完全保持无需改动的资产 (Existing & Unchanged)

以下模块在前期（001~003）已全面实现并经过 100% 单测验证，**本次技术方案直接调用或复用，严禁推倒重写**：

* `WalkMate/Core/Camera/CameraPipeline.swift`：相机 Wi-Fi 套接字握手、双鱼眼裸流推流与帧率统计。
* `WalkMate/Core/Camera/GyroDataHandler.swift`：相机 6 轴 IMU 姿态插值与加速度聚合。
* `WalkMate/Core/Camera/StreamPlayerBridge.swift`：Insta360 官方播放器桥接与 CAEAGLLayer 视图渲染。
* `WalkMate/Core/Inference/DAPEngine.swift`：CoreML/ANE 硬件加速的 $256 \times 512$ 深度推理引擎（已支持真机 `.mlmodelc` 检索）。
* `WalkMate/Core/Inference/AcceleratePreprocessor.swift`：vImage 硬件加速图像格式转换。
* `WalkMate/Core/Geometry/SphericalProjector.swift`：全景深度图球面反投影三维点云算法。
* `WalkMate/Core/Geometry/GravityAligner.swift`：点云重力方向对齐变换矩阵计算。
* `WalkMate/Core/Geometry/GroundPlaneEstimator.swift`：RANSAC 地面平面拟合 $Ax+By+Cz+D=0$ 算法与相机离地高度计算。
* `WalkMate/Core/Perception/ObstacleDetector.swift`：三维点云聚类与障碍物检测算法。
* `WalkMate/Core/Perception/ObstacleTracker.swift`：跨帧障碍物时序跟踪与状态机。
* `WalkMate/Core/Perception/PassageRoutePlanner.swift`：300x300 BEV 栅格投影、欧式距离变换 (EDT) 与 A* 全局可行走廊规划算法。
* `WalkMate/Core/Audio/SpatialAudioPlayer.swift`：3D 空间音频导航与障碍物双金属音警报。
* `WalkMate/Core/Audio/ProceduralAudioSynthesizer.swift`：内存 PCM 物理建模音频合成器。
* `WalkMate/Frameworks/SSZipArchive.xcframework`：既有 Zip 压缩动态库。

### 2. 既有需进行外科手术式扩展的文件 (Existing & Needs Modification)

* `WalkMate/Core/Engine/SpatialPerceptionEngine.swift`：
  * **修改点**：目前流水线处理完一帧后仅将 `ObstacleData` 和 `PassableRouteData` 派发给 delegate。需要增加数据钩子，允许采集器获取内部产生的地面方程 `[A, B, C, D]`、估算相机高度 `cameraHeight` 以及当前的 `DepthMatrix`。
* `WalkMate/App/ContentView.swift`：
  * **修改点**：将右上角的 `[拷贝日志]` 按钮替换为实测采集与管理复合按钮；维护 `collector` 的生命周期，并在展开的面板中集成“实测会话管理”与保留的“拷贝纯文本日志”双入口。
* `WalkMate/project.yml`：
  * **修改点**：在 targets 中增加 `ReplayTests` 测试目标，声明对 `WalkMate` 与 `SSZipArchive` 的依赖，供 `xcodegen` 生成。

### 3. 本次全新创建的模块 (Brand New Assets)

* `WalkMate/Models/CollectorModels.swift`：定义会话元数据 `SessionMetadata`、帧遥测 `FrameTelemetryRecord`（Codable）及视图项 `SessionSummaryItem`。
* `WalkMate/Core/Collector/PerceptionDataCollector.swift`：核心数据采集协调器，管理会话、内存环形队列、分级采样与异步写盘。
* `WalkMate/Core/Collector/SessionStorageManager.swift`：磁盘存储管理器，负责沙盒目录管理、空间检查（500MB警戒线）、会话列表管理与调用 `SSZipArchive` 打包。
* `WalkMate/App/Views/SessionManagementSheet.swift`：会话管理与 AirDrop 导出抽屉视图组件。
* `Tests/AppTests/SessionStorageManagerTests.swift`：沙盒会话管理、空间检测与 zip 打包测试。
* `Tests/AppTests/PerceptionDataCollectorTests.swift`：异步无损采样、JSONL 序列化与生命周期测试。
* `Tests/ReplayTests/PerceptionReplayer.swift`：离线回放数据加载与解包驱动器（实现 `PerceptionReplayerProtocol`）。
* `Tests/ReplayTests/PerceptionReplayTests.swift`：Mac 端离线回放套件，读取解压的实测会话并重跑算法流水线。

---

## 五、 项目代码结构变更明细 (Repository Layout & File Annotations)

```text
WalkMate/
├── App/
│   ├── ContentView.swift                  # [既有修改: 升级右上角按钮为采集入口并挂载数据钩子]
│   ├── WalkMateApp.swift                  # [既有保持: 主入口 TabView 双页结构]
│   └── Views/
│       ├── PanoramicStreamView.swift      # [既有保持: 全屏推流画面]
│       ├── SensorTelemetryCard.swift      # [既有保持: 传感器卡片]
│       └── SessionManagementSheet.swift   # [新增: 实测会话管理与 AirDrop 导出抽屉]
├── Core/
│   ├── Audio/                             # [既有保持: 空间音频与物理建模合成器]
│   │   ├── SpatialAudioPlayer.swift
│   │   └── ProceduralAudioSynthesizer.swift
│   ├── Camera/                            # [既有保持: 相机流与陀螺仪聚合]
│   │   ├── CameraPipeline.swift
│   │   ├── GyroDataHandler.swift
│   │   └── StreamPlayerBridge.swift
│   ├── Collector/                         # [新增目录: 实测多模态采集与存储子系统]
│   │   ├── PerceptionDataCollector.swift  # [新增: 异步环形缓冲采集协调器]
│   │   └── SessionStorageManager.swift    # [新增: 沙盒会话管理与 SSZipArchive 打包器]
│   ├── Engine/
│   │   └── SpatialPerceptionEngine.swift  # [既有修改: 暴露地面拟合参数与深度矩阵采集钩子]
│   ├── Geometry/                          # [既有保持: 点云投影、重力对齐与地面拟合算法]
│   │   ├── GroundPlaneEstimator.swift
│   │   ├── GravityAligner.swift
│   │   └── SphericalProjector.swift
│   ├── Inference/                         # [既有保持: DAP ANE 深度推理与预处理]
│   │   ├── DAPEngine.swift
│   │   └── AcceleratePreprocessor.swift
│   ├── Perception/                        # [既有保持: 障碍物检测与 A* 路线规划算法]
│   │   ├── ObstacleDetector.swift
│   │   ├── ObstacleTracker.swift
│   │   └── PassageRoutePlanner.swift
│   └── Utils/
│       └── Log.swift                      # [既有保持: 统一日志工具与内存环形缓冲]
├── Models/
│   ├── CollectorModels.swift              # [新增: 会话元数据与帧遥测 Codable 实体]
│   ├── PerceptionModels.swift             # [既有保持: 障碍物与路线数据结构]
│   └── FrameModels.swift                  # [既有保持: 全景图像帧结构]
├── Frameworks/
│   └── SSZipArchive.xcframework           # [既有保持: 项目内置 Zip 压缩动态库]
└── project.yml                            # [既有修改: 添加 ReplayTests 测试目标与目录配置]

Tests/
├── AppTests/                              # [既有增量: 增加采集器与存储测试]
│   ├── PilotViewModelTests.swift          # [既有保持]
│   ├── SessionStorageManagerTests.swift   # [新增: 存储与压缩单测]
│   └── PerceptionDataCollectorTests.swift # [新增: 采集时序与分级采样单测]
├── AudioTests/                            # [既有保持: 空间音频专项单测]
├── CameraTests/                           # [既有保持: 相机管道单测]
├── GeometryTests/                         # [既有保持: 几何算法单测]
├── InferenceTests/                        # [既有保持: DAP 模型推理单测]
├── PerceptionTests/                       # [既有保持: 感知与寻路单测]
└── ReplayTests/                           # [新增测试目标: 离线回放与调优基准]
    ├── Datasets/                          # [新增目录: 存放样本会话用于回归验证]
    ├── PerceptionReplayer.swift           # [新增: 离线回放数据加载与解压驱动器]
    └── PerceptionReplayTests.swift        # [新增: 离线数据回灌与调参评估测试]
```

---

## 六、 复杂度评估与防过度设计审查 (Complexity Tracking)

> 严格遵守宪章原则十二（极致简朴、拒绝过度设计）。

| 潜在复杂度项 | 宪章审核结论 | 采纳的具体简化方案 |
| :--- | :---: | :--- |
| **引入独立 CoreData 或 SQLite 数据库** | **否决** | 采用最朴素的文件系统目录结构，每个会话一个独立文件夹，元数据直接使用单一 `metadata.json`，时序数据直接使用文本 `telemetry.jsonl`，零数据迁移负担。 |
| **引入新第三方压缩库（如 ZIPFoundation）** | **否决** | 项目已包含 `SSZipArchive.xcframework`，直接调用 `SSZipArchive.createZipFile`，零新增依赖。 |
| **开发独立 macOS 桌面回放 GUI App** | **否决** | 采用 XCTest 编写的原生回放驱动套件，直接在命令行或 Xcode 运行并输出量化对比摘要，免除维护双端 UI 代码的庞大成本。 |
| **复杂网络上传接口与远端服务器存储** | **否决** | 采用 iOS 原生 `UIActivityViewController` 支持 AirDrop 秒传，无需后端服务与云存储配置，外场脱机亦可稳定使用。 |
