# 实施计划：全景空间感知与导航基础数据 API (Implementation Plan)

**特性分支**: `001-dap-spatial-perception` | **日期**: 2026-09-22（修订于 2026-09-23） | **需求规范**: [spec.md](./spec.md)

**输入**: 来自 `specs/001-dap-spatial-perception/spec.md` 的功能规范、`../DAP` 算法研究与 `~/Downloads/iOS_v1.10.4` 官方相机 SDK 样本研究。

---

## 概述 (Summary)

本项目基于 Insta360 官方专有的 **DAP (Depth Any Panoramas, CVPR 2026)** 全景深度估计大模型，打造面向视障出行与康复场景的**底层空间感知与导航基础设施 SDK（类似高德地图 SDK）**。

系统在**已完成并验证通畅的 Insta360 相机 Wi-Fi 连接与实时流预览基石**之上，利用 Apple Neural Engine（ANE）硬件加速与 Accelerate 向量化流水线，在 iPhone 15/16 上实现 121ms 的端到端实时推理。底层纯粹交付三大核心能力：
1. **全场景 360° 障碍物数据 API (`ObstacleData`)**：统合地面凸起、高空悬挂、下沉台阶断层与动态实体，输出三维坐标、包围盒、相对速度与跨帧持久 Tracking ID；
2. **可通行路线折线数据 API (`PassableRouteData`)**：基于 BEV 自由空间栅格与欧氏距离变换（EDT），输出带瓶颈通行净宽的连续路径航路点序列（Waypoints）与安全纵深；
3. **空间音频与空间几何转换工具箱 (`SpatialAudioKit`)**：提供钟表方位逆空间编码、iOS 原生 3D 空间音频声源锚点、双声道声相降级与几何碰撞检测的**无状态纯函数工具集（严格零音频播放）**。

---

## 技术上下文 (Technical Context)

- **开发语言与版本**: Swift 5.9+, iOS 17.0+
- **核心依赖框架**:
  - `CoreML`（强制 ANE 神经引擎硬件执行 `dap_256x512_int8.mlpackage`）；
  - `Accelerate`（`vImage` 零拷贝图像快速降采样至 $256 \times 512$，$vDSP` 向量化浮点运算与矩阵计算）；
  - `simd`（硬件级三维向量与四元数重力姿态运算）；
  - `SwiftUI`（已完成的无障碍极简控制与推流/传感器遥测面板）；
  - `Insta360 Camera SDK`（官方 iOS 框架，用于 Wi-Fi Socket 连接、硬件推流解码与 IMU 姿态回调）。
- **数据存储方式**: 纯内存环形缓冲区（In-memory Ring Buffer，零磁盘 I/O，确保极速低延迟）。
- **测试框架**: `XCTest`（针对几何反投影、RANSAC 平面拟合、EDT 走廊规划、MOT 目标追踪与 `SpatialAudioKit` 纯计算工具的单元测试）。
- **目标硬件平台**: iPhone 15 / iPhone 15 Pro / iPhone 16 系列物理真机（必须配备 Apple 神经引擎 ANE）。
- **工程构建体系**: `xcodegen`（通过 `project.yml` 声明式管理工程结构，支持一秒重新生成 Xcode 工程）。
- **性能目标**:
  - 端到端单帧总延迟 $\le 130\text{ ms}$（实测时延预算 $121.2\text{ ms}$，稳跑 $\ge 8.0\text{ FPS}$）；
  - 运行时物理内存占用（RAM）$\le 150\text{ MB}$；
  - 核心区间（0.5m~3.0m）测距平均物理误差 $\le 3\text{ cm}$；
  - 工具箱数学转换耗时 $\le 0.05\text{ ms}$。
- **约束要求**:
  - 100% 移动端本地脱机全速运行，绝不依赖云端服务器；
  - 绝对无状态与零音频播放：`SpatialAudioKit` 仅负责数学转换，绝不触碰全局 `AVAudioSession`；
  - 统一全中文注释、日志与文档，代码标识符遵循行业英文规范。

---

## 宪章核查 (Constitution Check)

*门禁：Phase 0 研究前已核准，Phase 1 设计后复核全项通过。*

1. **原则一：项目背景与 ANE 算力保证**
   - 严格采用 Insta360 官方专有的 DAP 基础大模型 CoreML INT8 原生包，整图在 ANE 神经引擎上原生执行，不妥协为第三方轻量小模型。 -> **通过 (PASS)**
2. **原则二：极致低延迟约束**
   - 经实测预算推演，全链路总耗时 $121.2\text{ms}$（预处理 11.2ms + ANE 推理 97.8ms + 方向 LUT 反投影 0.9ms + RANSAC 2.5ms + BEV/EDT 路线解算 3.5ms + MOT 追踪 0.5ms + 数据广播 4.8ms），稳定达到每秒 8 帧以上实时避障要求。 -> **通过 (PASS)**
3. **原则四：绝对无障碍适配（最高底线要求）**
   - 已完成的相机控制界面按钮尺寸严格 $\ge 48\times 48\text{ pt}$，配有无障碍标签；传感器面板采用中文逗号边界阻断单卡片聚焦；输出的三维坐标与 iOS 空间音频（`AVAudio3DMixing`）原生对齐。 -> **通过 (PASS)**
4. **原则五：严格统一的中文语言规范**
   - 所有产物（Spec、Plan、Research、Data-model、Contracts、Quickstart、代码注释、业务日志）严格统一使用中文；代码标识符遵循行业英文规范。 -> **通过 (PASS)**
5. **原则六：Git 提交规范**
   - 纯中文提交消息，按功能阶段即时提交。 -> **通过 (PASS)**
6. **原则七：依赖库引入规范**
   - 仅使用 Insta360 官方 SDK 与 Apple 原生系统框架（CoreML, Accelerate, simd, SwiftUI），杜绝引入任何非必要第三方库。 -> **通过 (PASS)**
7. **原则八与原则九：日志语言与统一埋点**
   - 业务日志内容全中文，日志级别遵循英文标准枚举，使用统一封装的 `Log.swift` 工具，严禁使用裸 `print()`。 -> **通过 (PASS)**
8. **原则十二：极致简朴与外科手术式修改 (YAGNI)**
   - 纯粹交付三大核心 API，剔除所有上层业务逻辑（圆环、积分、规则引擎）；采用预计算 1.57MB 方向 LUT 规避三角函数开销；代码差分最小化。 -> **通过 (PASS)**

---

## 项目工程结构 (Project Structure)

### 1. 规范与设计文档
```text
specs/001-dap-spatial-perception/
├── plan.md              # 实施计划 (本文件)
├── research.md          # Phase 0 输出：技术决策与延迟预算报告
├── data-model.md        # Phase 1 输出：数据模型与实体契约
├── quickstart.md        # Phase 1 输出：快速验证与测试场景指南
├── checklists/          # 需求质量验证清单
│   └── requirements.md
├── contracts/           # Phase 1 输出：接口契约目录
│   ├── camera_pipeline_contract.md  # 相机流基石契约 (已完成基线)
│   └── perception_api_contract.md   # 空间感知对外服务契约 (三大核心能力)
└── tasks.md             # Phase 2 输出：详细任务拆解 (由 /speckit-tasks 生成)
```

### 2. 源代码与资源目录规划
```text
WalkMate/
├── App/
│   ├── WalkMateApp.swift            # 应用程序入口
│   ├── ContentView.swift            # 主界面：极简设备控制与画面/传感器预览 HUD (已完成基线)
│   └── Views/                       # 界面子组件 (已完成基线)
│       ├── PanoramicStreamView.swift # 1080P 全景实时视频流渲染视图
│       └── SensorTelemetryCard.swift # 六轴传感器与推流遥测普通文本卡片
├── Core/
│   ├── Camera/                      # 【已完成基石】相机连接与视频流管道
│   │   ├── CameraPipeline.swift     # 基于 INSCameraManager.socket() 的连接、生命周期管理
│   │   ├── StreamPlayerBridge.swift # 基于 INSCameraSessionPlayer 的 H.265/H.264 解码与帧提取
│   │   └── GyroDataHandler.swift    # 基于 INSCameraSessionGyroDelegate 的六轴数据同步解析
│   ├── Inference/                   # 第 2 层：DAP 深度推理引擎
│   │   ├── DAPEngine.swift          # CoreML INT8 ANE 硬件执行器 (Float16 安全绑定)
│   │   └── AcceleratePreprocessor.swift # vImage+vDSP 硬件向量化预处理 (11.2ms)
│   ├── Geometry/                    # 第 3 层：空间点云与地面分离
│   │   ├── SphericalProjector.swift # 预计算方向 LUT + vDSP 毫秒级反投影 (13万点, 0.9ms)
│   │   ├── GravityAligner.swift     # 基于 IMU 姿态的重力垂直坐标对齐
│   │   └── GroundPlaneEstimator.swift # 纯动态 RANSAC 下半球地面拟合与高程分层 (2.5ms)
│   ├── Perception/                  # 第 4 层：全场景障碍物与可通行路线解算
│   │   ├── ObstacleDetector.swift   # 360° 障碍物点云聚类、包围盒提取与类型判别
│   │   ├── ObstacleTracker.swift    # 3D 欧氏距离门限 MOT 跨帧稳定追踪与 ID 分配
│   │   └── PassageRoutePlanner.swift# 300x300 BEV 栅格 + EDT 通行走廊航路点 (Waypoints) 提取
│   ├── Toolkits/                    # 第 5 层：空间音频与空间几何转换工具箱
│   │   └── SpatialAudioKit.swift    # 钟表逆空间编码、3D 声源锚点、双声道声相与净空碰撞检测
│   ├── Engine/                      # 空间感知对外服务中枢
│   │   └── SpatialPerceptionEngine.swift # 协调全链路管道，广播 ObstacleData 与 PassableRouteData
│   └── Utils/                       # 通用工具
│       └── Log.swift                # 统一业务结构化日志工具 (遵循宪章原则八/九)
├── Models/                          # 数据实体模型 (data-model.md)
│   ├── FrameModels.swift            # PanoramicFrame, DepthMatrix
│   ├── PerceptionModels.swift       # ObstacleData, ObstacleItem, PassableRouteData, RouteWaypoint
│   ├── ToolModels.swift             # ClockPromptData, SpatialAudioRenderParams, StereoFallbackParams, ClearanceResult
│   └── TelemetryModels.swift        # SensorTelemetry, CameraConnectionState, ThreatLevel
├── Resources/
│   └── Models/
│       └── dap_256x512_int8.mlpackage # ANE 原生 INT8 量化模型包 (319 MB)
└── project.yml                      # xcodegen 工程定义文件

Tests/
├── CameraTests/                     # 相机连接与数据解析单元测试 (已通过基线)
├── InferenceTests/                  # 预处理与 CoreML 张量绑定测试
├── GeometryTests/                   # 方向 LUT 反投影与动态地面拟合精度测试
├── PerceptionTests/                 # 360° 障碍物聚类、MOT 跨帧跟踪与路线折线点提取测试
└── ToolkitTests/                    # SpatialAudioKit 纯计算工具转换精度与性能测试
```

---

## 复杂度追踪 (Complexity Tracking)

| 设计选择 / 潜在复杂点 | 为何必要 | 被否决的简单方案及原因 |
| :--- | :--- | :--- |
| **相机连接部分保持既有基线** | 既有代码（`CameraPipeline`）已完成 Wi-Fi Socket 连接、解码与 IMU 同步并通过真机验证，无需推倒重来 | 重写相机层：违反宪章原则十二（外科手术式修改），增加不必要的回归风险 |
| **预计算 1.57MB 方向 LUT** | 必须将 13 万个 3D 点反投影耗时压制在 1ms 内，保住 130ms 总时延红线 | 运行时动态调用 `sin`/`cos`：单帧额外增加 25ms 计算开销，严重挤占 ANE 与上层时间 |
| **纯动态 RANSAC 地面拟合** | 视障佩戴姿态各异（手持/胸前/肩部），固定安装高度先验在起坐或手部晃动时会发生严重误报 | 静态预设 1.4 米高度先验：虽然简单，但相机随步态晃动时会将正常平地误判为高危障碍 |
| **3D 欧氏距离门限 MOT 跨帧追踪** | 保证目标在移动过程中具有持续稳定的 `id`，使上层能无缝判断避障位移 | 仅输出单帧无状态聚类：上层无法判断物体前后运动关系，必须在上层重新实现多目标追踪 |
| **BEV 栅格 + EDT 航路折线点提取** | 视障行走不仅需要单一方位角，还需要弯道、门口等连续几何通道指引 | 简单前向射线检测：只能探测是否有墙，无法在复杂室内提取最优通行中轴线与通道瓶颈净宽 |
| **SpatialAudioKit 严格做成纯函数** | 保证计算零开销，且 100% 杜绝抢夺系统音频会话与 VoiceOver 焦点 | 底层内置播放器：会与上层音乐、读屏发生系统级音频冲突导致静音或崩溃 |
