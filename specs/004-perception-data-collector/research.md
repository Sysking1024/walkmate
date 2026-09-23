# 技术选型与可行性研究报告：空间感知实测多模态数据采集与离线回放系统 (004-perception-data-collector)

**特性分支**: `004-perception-data-collector`  
**创建日期**: 2026-09-23  
**状态**: 已完成 (Completed)

---

## 一、 核心痛点与现有算法资产审计

在实测中，视障测试者频繁听到障碍物金属敲击声、几乎听不到航路点脚步声，并伴随大量“前方受阻，无有效可行航路点”日志。经深度链路审计：
1. **既有无需重写的核心算法资产**：
   - `DAPEngine`（$256 \times 512$ 深度估计，已在 iOS 真机加载 `.mlmodelc` 验证通过）。
   - `SphericalProjector`（球面反投影为三维点云）。
   - `GravityAligner`（四元数/重力向量对齐）。
   - `GroundPlaneEstimator`（RANSAC 地面平面拟合）。
   - `ObstacleDetector`（三维聚类与障碍物检测）。
   - `PassageRoutePlanner`（300x300 BEV 栅格化、EDT 距离场变换与 A* 通行路径规划）。
2. **核心缺失与调试瓶颈**：
   - 算法流程完全闭环，但由于缺乏现场的“全景图像 + 深度图 + IMU 姿态 + 地面拟合系数 $(A, B, C, D)$ + 航路点结果”的时序真值数据包，无法单步断点观察是地面误检为障碍物，还是通道门限过严。
   - 现有的 `Log` 模块仅记录纯文本，无法进行离线点云重现与算法回归测试。

---

## 二、 关键技术选型与架构决策

### 决策 1：多模态数据分级采集与存储格式

- **选定方案**：**分级异构存储（结构化遥测 JSONL + 二进制深度/JPEG视觉帧）**
- **技术设计**：
  1. **高频时序遥测流（10~30Hz）**：采用行式 JSON（JSON Lines / `.jsonl`）顺序追加。每一行是一个独立的 `FrameTelemetryRecord`（包含微秒时间戳、IMU 姿态角、地面方程、相机高度、检测到的障碍物列表、安全深度与航路点）。
     - *优点*：流式落盘无需持有全量对象在内存；若遇到强退断电，已写入的每一行均完好无损，杜绝非法 JSON 结构崩溃。
  2. **低频关键帧视觉快照（1~2Hz）**：
     - 全景帧：按 1~2Hz 将 CVPixelBuffer 编码为 JPEG（压缩质量 0.75，分辨率可根据性能自适应），写入 `frames/<timestamp>.jpg`。
     - 深度图：将 $256 \times 512$ 的 Float 矩阵压缩为二进制文件或 16 位灰度 PNG，写入 `depths/<timestamp>.bin`。
- **放弃方案**：
  - *全量 MP4 视频录制 + SRT 字幕*：虽然视觉直观，但全景鱼眼视频硬件编码会与相机推流解码抢占 VideoToolbox 硬件资源，且时间戳无法与点云微秒对齐。
  - *每秒 30fps 全量图片写盘*：每分钟产生约 1800 张大图，闪存 I/O 吞吐极易引起主线程掉帧与严重发热。

---

### 决策 2：零拷贝异步写盘与环形缓冲管道（避免 I/O 阻塞）

- **选定方案**：**专用串行 Utility 调度队列 + 固定容量环形缓冲区（Ring Buffer）**
- **技术设计**：
  - 创建专用的 `DispatchQueue(label: "world.accera.walkmate.collector.io", qos: .utility)`。
  - 模型推理线程在产出数据后，仅在内存中执行浅拷贝（或保留引用），非阻塞投递到写盘队列。
  - 若遇磁盘瞬时写入拥塞，遥测数据通过环形缓冲区缓冲；若发生溢出则优先丢弃图像帧，绝对确保时序遥测与感知主链路不掉帧、不降频。
- **放弃方案**：
  - *主线程或感知回调直接写文件*：会导致视频流画面卡顿，音频调度延迟抖动。

---

### 决策 3：会话归档与文件分享机制（利用既有库零新依赖）

- **选定方案**：**利用工程既有 `SSZipArchive.xcframework` 打包 + iOS 原生 `UIActivityViewController`**
- **技术设计**：
  - 项目已在 `WalkMate/Frameworks/SSZipArchive.xcframework` 集成了久经考验的 Zip 压缩库，且在 `project.yml` 中已建立链接。
  - 直接调用 `SSZipArchive.createZipFile(atPath: zipPath, withContentsOfDirectory: sessionDir)` 执行后台异步压缩。
  - 压缩完成后，调用标准 `UIActivityViewController(activityItems: [zipURL], applicationActivities: nil)`。
  - 支持系统级 **AirDrop（隔空投送）**、存储到“文件”App 或通过即时通讯软件发送，无需配置任何第三方 SDK。
- **宪章符合度**：严格遵循宪章原则七（严禁盲目引入新依赖，优先使用项目现有库）。

---

### 决策 4：开发机端离线回放套件设计（XCTest 原生仿真）

- **选定方案**：**工程内置 XCTest 回放测试驱动（`PerceptionReplayTests`）**
- **技术设计**：
  - 开发者通过 AirDrop 获取 `session_YYYYMMDD_HHmmss.zip` 并解压后，测试套件读取 `metadata.json` 与 `telemetry.jsonl`，以及对应时间戳的图像与深度图。
  - 构造 `MockCameraPipeline` 模拟真实时间戳推送帧，直接灌入现有的 `GroundPlaneEstimator`、`ObstacleDetector` 与 `PassageRoutePlanner`。
  - 支持单步断点逐帧调试，输出每一步的中间变量。
  - 自动化统计并打印当前参数下的航路点生成率（Passable Rate）与障碍物平均距离，用于量化评估参数优化效果。
- **放弃方案**：
  - *独立 macOS GUI 工具*：虽然体验更佳，但维护两个 App 的构建配置成本高，不符合宪章“极致简朴与外科手术式修改”原则。XCTest 零额外维护成本且可直接接入 CI。

---

## 三、 研究结论与后续行动

所有技术未知项已完全澄清并与宪章规范对齐：
1. 采样与存储采用“10~30Hz 遥测流 + 1~2Hz 抽样视觉图”的分级模型；
2. 会话打包完全复用既有的 `SSZipArchive`，零新外部依赖；
3. UI 入口采用替换升级主界面右上角按钮为多功能复合入口；
4. 离线回放以 XCTest 原生套件交付。

已具备推进 Phase 1 数据模型（`data-model.md`）与接口契约（`contracts/`）制定的全部前置条件。
