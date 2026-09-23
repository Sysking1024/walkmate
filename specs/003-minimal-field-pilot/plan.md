# 技术方案与实施规划：003-minimal-field-pilot 极简真机实测

**特性分支**: `003-minimal-field-pilot` | **创建日期**: 2026-09-23 | **规范文档**: [`specs/003-minimal-field-pilot/spec.md`](./spec.md)

**输入**: 来自 `specs/003-minimal-field-pilot/spec.md` 的功能需求与用户指令。

---

## 一、方案概要 (Summary)

面向 iPhone 15 与 Insta360 全景相机的真实物理场景步行实测，在**最短时间内打通“全屏监控 $\rightarrow$ 独立启停 $\rightarrow$ 深度感知 $\rightarrow$ 空间音频闭环”**：
1. **现有算法与底座资产 100% 复用**：DAP ANE 硬件推理（98ms）、Accelerate 硬件预处理（11ms）、球面反投影、动态 RANSAC 地面拟合、360° 空间聚类与追踪、BEV 路径规划、以及 ProceduralAudioSynthesizer 内存 DSP 合成器与 SpatialAudioPlayer 3D HRTF 双耳声学图已全部在前期实现完备，本特性**零重复开发，底层算法代码零修改**；
2. **UI 极简沉浸式重构**：移除多余的六轴传感器遥测 HUD（`SensorTelemetryCard`）与所有文字干扰卡片，将全景视频流视图（`PanoramicStreamView`）全屏铺满主屏幕；
3. **控制状态机解耦**：左下角保留相机连接/断开按钮，右下角新增独立“开始/停止感知”主控按钮，实现视频推流监控与大模型深度推理的生命周期解耦，保护机身功耗与发热；
4. **业务层前向 130° 与 1 米近身双重避障过滤**：在 `CameraViewModel` 中对全景障碍物进行业务级初筛（$|\text{azimuth}| \le 65^\circ \land distance \le 1.0\text{m}$），仅报前向贴身威胁，彻底消除身后误报；
5. **首航路点快速导引**：直接提取规划路线的第 1 个航路点坐标送入 `SpatialAudioPlayer.setNavigationTarget`，驱动 1.1s 自然步频领路脚步声。

---

## 二、技术上下文 (Technical Context)

- **开发语言与版本**: Swift 5.9
- **核心依赖框架**: SwiftUI, AVFoundation (HRTF 3D 声学图), Accelerate (vImage+vDSP), CoreML (MIL 编译 ANE INT8 模型), INSCameraSDK, INSCameraServiceSDK
- **数据持久化**: 无（内存零延迟实时流流水线）
- **测试框架**: XCTest (基于真实样本 `tmp/pano_indoor.jpg` 进行端到端回归断言)
- **目标平台**: iOS 17.0+ (物理设备目标：iPhone 15 / `arm64`)
- **工程类型**: 原生 iOS SwiftUI 移动端应用（通过 `xcodegen` 组织管理）
- **性能指标目标**: ANE 纯硬件推理 $\le 98\text{ms}$，端到端延迟 $\le 125\text{ms}$，感知吞吐 $\approx 8.2\text{ FPS}$，启停响应 $< 200\text{ms}$，静音响应 $< 50\text{ms}$
- **约束要求**: App 内存占用 $\le 150\text{MB}$，开启 `audio` 后台模式确保锁屏不挂起，严格全中文注释与日志，所有触控靶心 $\ge 48\text{pt}$，对比度 $\ge 4.5:1$

---

## 三、宪章质量门禁自检 (Constitution Check)

| 原则条目 | 门禁要求 | 本规划落实与审查结果 | 状态 |
| :--- | :--- | :--- | :---: |
| **原则一：项目背景** | 基于 Insta360 DAP 大模型与 iPhone ANE 端侧独立运行 | 严格运行本地 CoreML INT8 模型，不使用任何外部云服务。 | ✅ 通畅 |
| **原则二：极致低延迟** | 视频解析到音频反馈端到端极低延迟 | 业务层仅对目标点进行 O(N) 极速筛选（N $\le 20$，耗时 $< 0.05\text{ms}$），零主线程卡顿。 | ✅ 通畅 |
| **原则四：绝对无障碍适配** | 触控尺寸 $\ge 48\text{pt}$，对比度 $\ge 4.5:1$，VoiceOver 读屏无噪点 | 左右双按钮尺寸严格设为 $56\times 56\text{pt}$，对比度坚实保真，配置原生语义标签与语音提示。 | ✅ 通畅 |
| **原则五：统一中文规范** | 产物、文档、注释统一纯中文，标识符用标准英文 | 全套 Spec、Plan、注释与文案严格遵循纯中文规范。 | ✅ 通畅 |
| **原则七：依赖使用与引入** | 严禁凭空捏造 API，严禁盲目引入第三方新依赖 | 100% 使用项目已有 SDK 与 iOS 原生系统库，零新依赖引入。 | ✅ 通畅 |
| **原则八/九：日志规范** | 业务日志全中文，使用标准 Swift `Log` 工具 | 统一调用 `Log.info` / `Log.error`，严禁 `print()` 调试。 | ✅ 通畅 |
| **原则十：质量门禁** | 严禁孤岛化验证，必须全量回归与零编译警告 | 规划中包含静态分析与全量单元测试（含 `AudioTests`）回归门禁。 | ✅ 通畅 |
| **原则十二：外科手术式修改** | 极致简朴，严禁推倒重来，精准定位修改最小集 | 仅微调 `PanoramicStreamView.swift`（支持全屏背景）、修改 `ContentView.swift`、`Info.plist` 与 `project.yml` 四个文件，其他全部复用。 | ✅ 通畅 |
| **原则十三：调试与测试先行** | 编写单元测试验证业务层过滤与状态机流转 | 新增 `PilotViewModelTests` 针对双按钮启停、掉线安全重置与 130° 扇区过滤编写测试。 | ✅ 通畅 |

---

## 四、项目代码结构与变更清单 (Project Structure)

### 1. 本特性文档清单

```text
specs/003-minimal-field-pilot/
├── spec.md              # 功能需求规范书 (已就绪)
├── research.md          # Phase 0 技术调研与现有算法复用清单 (已就绪)
├── data-model.md        # Phase 1 实体与控制状态机 (已就绪)
├── quickstart.md        # Phase 1 快速验证与真机实测指南 (已就绪)
├── contracts/           # Phase 1 接口契约定义 (已就绪)
│   └── pilot_view_model_contract.md
├── plan.md              # 总体实施方案 (本文档)
└── checklists/
    └── requirements.md  # 规范质量检查表 (12/12 绿灯)
```

### 2. 源代码与工程文件改动明细 (无歧义标注)

```text
WalkMate/
├── App/
│   ├── WalkMateApp.swift                    # [现有资产/无需改动] 应用程序主入口
│   ├── ContentView.swift                    # [现有核心文件/需修改] 
│   │                                        #   - 移除 ScrollView 与 SensorTelemetryCard
│   │                                        #   - 重构为 ZStack 全屏沉浸式 PanoramicStreamView(isFullScreen: true)
│   │                                        #   - 左下角放置相机连接按钮，右下角放置开始/停止感知按钮
│   │                                        #   - CameraViewModel 接入 isPerceiving 独立启停状态机与掉线安全自愈
│   │                                        #   - 接入 SpatialAudioPlayer 并实现 130° 扇区与 1m 近身过滤及首航路点导航
│   └── Views/
│       ├── PanoramicStreamView.swift        # [现有组件/需微调] 支持 isFullScreen 全屏沉浸模式，避免 2:1 画幅截断
│       └── SensorTelemetryCard.swift        # [现有组件/保留文件/主界面移除调用] 备用传感器 HUD
├── Core/
│   ├── Audio/
│   │   ├── ProceduralAudioSynthesizer.swift # [现有算法已实现/复用无需改动] 内存 DSP 纯代码声音合成器
│   │   └── SpatialAudioPlayer.swift         # [现有算法已实现/复用无需改动] 3D HRTF 双耳音频播放中枢
│   ├── Camera/
│   │   ├── CameraPipeline.swift             # [现有算法已实现/复用无需改动] Insta360 Wi-Fi 推流管道
│   │   ├── GyroDataHandler.swift            # [现有算法已实现/复用无需改动] 六轴陀螺仪解析器
│   │   └── StreamPlayerBridge.swift         # [现有算法已实现/复用无需改动] 官方播放器桥接器
│   ├── Engine/
│   │   └── SpatialPerceptionEngine.swift    # [现有算法已实现/复用无需改动] 空间感知全链路总成
│   ├── Geometry/
│   │   ├── GravityAligner.swift             # [现有算法已实现/复用无需改动] 四元数重力姿态对齐器
│   │   ├── GroundPlaneEstimator.swift       # [现有算法已实现/复用无需改动] RANSAC 动态地面拟合器
│   │   └── SphericalProjector.swift         # [现有算法已实现/复用无需改动] 1.57MB LUT 球面反投影器
│   ├── Inference/
│   │   ├── AcceleratePreprocessor.swift     # [现有算法已实现/复用无需改动] vImage+vDSP 硬件向量化预处理器
│   │   └── DAPEngine.swift                  # [现有算法已实现/复用无需改动] ANE 原生 CoreML INT8 深度推理引擎
│   ├── Perception/
│   │   ├── ObstacleDetector.swift           # [现有算法已实现/复用无需改动] 3D AABB 聚类与高程分类器
│   │   ├── ObstacleTracker.swift            # [现有算法已实现/复用无需改动] 3D MOT 多目标追踪器
│   │   └── PassageRoutePlanner.swift        # [现有算法已实现/复用无需改动] 300x300 BEV/EDT 航路点规划器
│   ├── Toolkits/
│   │   └── SpatialAudioKit.swift            # [现有算法已实现/复用无需改动] 几何到音频映射纯函数工具箱
│   └── Utils/
│       └── Log.swift                        # [现有工具/复用无需改动] 统一日志埋点工具
├── Models/
│   ├── FrameModels.swift                    # [现有模型/复用无需改动]
│   ├── PerceptionModels.swift               # [现有模型/复用无需改动]
│   ├── TelemetryModels.swift                # [现有模型/复用无需改动]
│   └── ToolModels.swift                     # [现有模型/复用无需改动]
├── Resources/
│   └── Models/
│       └── dap_256x512_int8.mlpackage       # [现有核心资产/复用无需改动] ANE 原生大模型包
├── Info.plist                               # [现有配置/需修改] 注入 UIBackgroundModes: [audio] 确保息屏运行
└── project.yml                              # [现有配置/需修改] 补齐 AudioTests target 与 scheme

Tests/
├── AppTests/
│   └── PilotViewModelTests.swift            # [新增测试文件] 验证 CameraViewModel 启停状态机、130° 扇区过滤与首航路点导引
├── AudioTests/                              # [现有测试/复用无需改动]
├── CameraTests/                             # [现有测试/复用无需改动]
├── GeometryTests/                           # [现有测试/复用无需改动]
├── InferenceTests/                          # [现有测试/复用无需改动]
├── PerceptionTests/                         # [现有测试/复用无需改动]
└── ToolkitTests/                            # [现有测试/复用无需改动]
```

---

## 五、架构与设计复杂度追踪 (Complexity Tracking)

> 经宪章质量门禁比对，本方案未引入任何越级模式，未引入任何新第三方依赖，未修改任何底层算法核心，完全符合宪章原则十二（极致简朴与外科手术式修改）。

| 违规项 | 为什么需要 | 为什么拒绝更简单方案 |
| :--- | :--- | :--- |
| *无任何宪章违规* | N/A | N/A |
