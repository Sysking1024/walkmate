# 实施计划：基于 DAP 的全景空间感知与避障系统 (Implementation Plan)

**特性分支**: `001-dap-spatial-perception` | **日期**: 2026-09-22 | **需求规范**: [spec.md](./spec.md)

**输入**: 来自 `specs/001-dap-spatial-perception/spec.md` 的功能规范与技术输入。

---

## 概述 (Summary)

本项目基于 Insta360 官方专有的 DAP（Depth Any Panoramas）基础大模型，为视障人群打造端到端毫秒级延迟的 360 度空间几何感知与避障系统。系统通过 Insta360 官方 SDK 接入真实全景视频流与六轴 IMU 数据，借助 Apple Accelerate 向量化预处理与 Apple Neural Engine（ANE）硬件加速，在 iPhone 15 上实现 128.6ms 的全链路超低延迟推理。通过预计算方向查表法、动态 RANSAC 地面剥离、人体宽度安全通行走廊规划以及后退倒车雷达模式，向外输出与 iOS 空间音频（`AVAudio3DMixing`）原生兼容的三维相对空间坐标，为视障用户提供直觉性的非视觉安全导航体验。

---

## 技术上下文 (Technical Context)

- **开发语言与版本**: Swift 5.9+, iOS 17.0+
- **核心依赖框架**:
  - `CoreML`（强制 ANE 神经引擎硬件执行）；
  - `Accelerate`（`vImage` 零拷贝图像缩放，`vDSP` 向量化浮点运算与矩阵计算）；
  - `simd`（硬件级三维向量与四元数运算）；
  - `SwiftUI`（符合无障碍规范的极简控制与遥测预览界面）；
  - `Insta360 Camera SDK`（官方 iOS 框架，用于 Wi-Fi 连接、硬件解码推流与 IMU 回调）。
- **数据存储方式**: 纯内存环形缓冲区（In-memory Ring Buffer，零磁盘 I/O，确保极速低延迟）。
- **测试框架**: `XCTest`（针对几何反投影、RANSAC 平面拟合、EDT 走廊规划与运动状态机的单元与性能测试）。
- **目标硬件平台**: iPhone 15 / iPhone 15 Pro / iPhone 16 系列物理真机（必须配备 Apple 神经引擎 ANE）。
- **工程构建体系**: `xcodegen`（通过 `project.yml` 声明式管理工程结构，支持一秒重新生成 Xcode 工程）。
- **性能目标**:
  - 端到端单帧总延迟 $\le 130\text{ ms}$（稳定 $\ge 8.0\text{ FPS}$）；
  - 运行时物理内存占用（RAM）$\le 160\text{ MB}$；
  - 核心区间（0.5m~3.0m）测距平均物理误差 $\le 3\text{ cm}$。
- **约束要求**:
  - 100% 移动端本地脱机全速运行，严禁依赖云端服务器；
  - 绝对无障碍优先：界面交互组件尺寸 $\ge 48\times 48\text{ pt}$，深度集成 VoiceOver；
  - 统一全中文注释、日志与文档，代码标识符统一使用行业英文规范。

---

## 宪章核查 (Constitution Check)

*门禁：Phase 0 研究前必须核准，Phase 1 设计后再次复核。*

1. **原则一：项目背景与 ANE 算力保证**
   - 严格采用 Insta360 官方 DAP 大模型 CoreML INT8 原生包，强制运行在 ANE 神经引擎上，不妥协为第三方轻量小模型。 -> **通过 (PASS)**
2. **原则二：极致低延迟约束**
   - 经实测预算推演，全链路总耗时 128.6ms（Accelerate 11.3ms + ANE 97.8ms + 几何反投影 1.0ms + RANSAC 2.5ms + 走廊规划 3.5ms），达到每秒 8 帧以上实时避障标准。 -> **通过 (PASS)**
3. **原则四：绝对无障碍适配（最高底线要求）**
   - 界面所有可点击按钮（连接/断开设备）尺寸均大于 $48\times 48$ 像素，配有无障碍标签与提示；传感器数据面板支持 VoiceOver 线性顺序朗读；空间音频坐标系直接兼容。 -> **通过 (PASS)**
4. **原则五：严格统一的中文语言规范**
   - 所有产物（Spec、Plan、Tasks、代码注释、业务日志）严格统一使用中文；代码类名、方法名遵循英文规范。 -> **通过 (PASS)**
5. **原则六：Git 提交规范**
   - 纯中文提交消息，按功能阶段即时提交。 -> **通过 (PASS)**
6. **原则七：依赖库引入规范**
   - 仅使用 Insta360 官方 SDK 与 Apple 原生系统框架（CoreML, Accelerate, simd, SwiftUI），杜绝引入任何非必要第三方库。 -> **通过 (PASS)**
7. **原则八与原则九：日志语言与统一埋点**
   - 业务日志内容全中文，日志级别遵循行业标准英文枚举（DEBUG, INFO, WARNING, ERROR），使用 Swift 统一日志工具，严禁使用 `print()` 调试。 -> **通过 (PASS)**
8. **原则十二：极致简朴与外科手术式修改 (YAGNI)**
   - 砍掉离线样本模拟器等过度设计，直攻真实相机数据流；采用预计算 LUT 优化数学性能；代码差分最小化。 -> **通过 (PASS)**

---

## 项目工程结构 (Project Structure)

### 1. 规范与设计文档
```text
specs/001-dap-spatial-perception/
├── plan.md              # 实施计划 (本文件)
├── research.md          # Phase 0 输出：技术决策与延迟预算报告
├── data-model.md        # Phase 1 输出：数据模型与实体契约
├── quickstart.md        # Phase 1 输出：快速验证与测试场景指南
├── contracts/           # Phase 1 输出：接口契约目录
│   ├── camera_pipeline_contract.md  # 相机硬件流契约
│   └── perception_api_contract.md   # 空间感知对外服务契约
└── tasks.md             # Phase 2 输出：详细任务拆解 (由 /speckit-tasks 生成)
```

### 2. 源代码与资源目录规划
```text
WalkMate/
├── App/
│   ├── WalkMateApp.swift            # 应用程序入口
│   ├── ContentView.swift            # 主界面：极简设备控制与画面/传感器预览 HUD
│   └── Views/                       # 界面子组件
│       ├── PanoramicStreamView.swift # 1080P 全景实时视频流渲染视图
│       └── SensorTelemetryCard.swift # 六轴传感器与推流遥测普通文本卡片 (静态被动展示)
├── Core/
│   ├── Camera/                      # 第 1 层：相机连接与视频流管道
│   │   ├── CameraPipeline.swift     # 基于 INSCameraManager 的连接与生命周期管理
│   │   ├── StreamPlayerBridge.swift # INSCameraSessionPlayer 硬件解码与帧回调
│   │   └── GyroDataHandler.swift    # INSCameraSessionGyroDelegate 六轴数据同步
│   ├── Inference/                   # 第 2 层：DAP 深度推理引擎
│   │   ├── DAPEngine.swift          # CoreML INT8 ANE 硬件执行器 (Float16 安全绑定)
│   │   └── AcceleratePreprocessor.swift # vImage+vDSP 硬件向量化预处理 (11ms)
│   ├── Geometry/                    # 第 3 层：空间点云与地面分离
│   │   ├── SphericalProjector.swift # 预计算方向 LUT + vDSP 毫秒级反投影 (13万点)
│   │   ├── GravityAligner.swift     # 基于 IMU 姿态的重力垂直坐标对齐
│   │   └── GroundPlaneEstimator.swift # 纯动态 RANSAC 下半球地面拟合 (2.5ms)
│   ├── Analysis/                    # 第 4 层：避障、走廊与运动状态解算
│   │   ├── MotionIntentEstimator.swift # IMU 纵向加速度脉冲 + 深度差分状态机
│   │   ├── PassageCorridorPlanner.swift# 300x300 BEV 栅格 (分辨率 0.02m，覆盖左右 ±3m 与纵深 0~6m) + EDT 人体通行走廊提取
│   │   ├── ObstacleSectorDetector.swift# 生理视角 120°~140° Top 3 动态避障
│   │   └── DropOffDetector.swift     # 前后双向 15cm 下行台阶防踩空检测
│   ├── Engine/                      # 空间感知对外服务中枢
│   │   └── SpatialPerceptionEngine.swift # 协调全链路管道，向外广播 SpatialPerceptionResult
│   └── Utils/                       # 通用工具
│       └── Log.swift                # 统一业务结构化日志工具 (遵循宪章原则八/九)
├── Models/                          # 数据实体模型 (data-model.md)
│   ├── FrameModels.swift            # PanoramicFrame, DepthMatrix
│   ├── PerceptionModels.swift       # SpatialObstacleItem, PassageCorridorGeometry, DropOffHazardEvent
│   └── TelemetryModels.swift        # SensorTelemetry, CameraConnectionState, UserMotionState, ThreatLevel
├── Resources/
│   └── Models/
│       └── dap_256x512_int8.mlpackage # ANE 原生 INT8 量化模型包 (319 MB)
└── project.yml                      # xcodegen 工程定义文件

Tests/
├── CameraTests/                     # 相机连接与数据解析单元测试
├── InferenceTests/                  # 预处理与 CoreML 张量绑定测试
├── GeometryTests/                   # 反投影与地面拟合精度测试
└── PerceptionTests/                 # 走廊规划与避障排序逻辑测试
```

---

## 复杂度追踪 (Complexity Tracking)

| 设计选择 / 潜在复杂点 | 为何必要 | 被否决的简单方案及原因 |
| :--- | :--- | :--- |
| **预计算 1.57MB 方向 LUT** | 必须将 13 万点反投影耗时压制在 1ms 内，保住 130ms 总时延红线 | 运行时动态计算 `sin`/`cos`：虽然节省 1.5MB 内存，但单帧耗时增加 25ms 以上，无法接受 |
| **纯动态 RANSAC 地面拟合** | 视障者佩戴相机姿态多变（手持/胸前/肩部/头盔），固定高度会产生严重误判 | 静态预设 1.4 米高度：算法极简，但在手持或坐下等场景下会将正常地面误判为障碍物 |
| **IMU 加速度 + 深度双模运动判定** | 避免身体微小晃动误触发后退倒车雷达模式 | 单一加速度计判定：身体行走自然晃动会产生大量误判，导致前后视角来回跳动 |
