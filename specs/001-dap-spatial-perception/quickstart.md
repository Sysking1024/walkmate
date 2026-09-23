# 快速验证指南：全景空间感知与导航基础数据 API (Quickstart Guide)

**特性分支**: `001-dap-spatial-perception`  
**关联模型**: [data-model.md](./data-model.md) | [contracts/](./contracts/)  
**创建时间**: 2026-09-22（重大修订于 2026-09-23）

---

## 一、验证前置条件 (Prerequisites)

1. **硬件环境**：
   - iPhone 15 及以上机型（搭载 Apple 神经引擎 ANE，运行 iOS 17.0+）；
   - Insta360 X5 全景相机（电量充足，开启 Wi-Fi 热点）；
   - Mac 开发机（macOS Sonoma 14.0+，安装 Xcode 15.0+ 及 `xcodegen`）。
2. **模型与测试资产准备**：
   - 确保 `tmp/dap_256x512_int8.mlpackage`（319 MB）已放置在工程资源或编译路径中；
   - 确保开发机测试全景图 `tmp/pano_indoor.jpg`（已就绪），供本地单元测试与脱机全链路调试使用。

---

## 二、工程生成与测试命令 (Setup & Test Commands)

```bash
# 1. 进入工作空间根目录
cd "$(git rev-parse --show-toplevel)"

# 2. 通过 xcodegen 自动生成原生 Xcode 工程
xcodegen generate

# 3. 在开发机 Mac 上直接运行全套单元测试（基于 tmp/pano_indoor.jpg 与 iOS 模拟器脱机验证）
xcodebuild test -project WalkMate.xcodeproj \
                -scheme WalkMate \
                -destination "platform=iOS Simulator,name=iPhone 16"

# 4. 在 iOS 真实真机上构建应用
xcodebuild -project WalkMate.xcodeproj \
           -scheme WalkMate \
           -destination "generic/platform=iOS" \
           build
```

---

## 三、端到端真机与单元验证场景 (Validation Scenarios)

### 场景 1：相机连接、控制 UI 与实时流预览（【已交付基石 (Completed Baseline)】）
- **验证目的**：验证相机 Wi-Fi 通信与视频流解码基石正常运转。
- **测试步骤**：
  1. 手机 Wi-Fi 连接至 Insta360 X5 热点；
  2. 启动 WalkMate App，点击顶部的【连接设备】按钮；
  3. 观察界面渲染。
- **预期结果**：
  - 按钮状态变为【断开设备】；
  - 界面中央流畅渲染 1080P 全景实时视频流（帧率稳定在 15 FPS 以上，无黑屏与画面撕裂）；
  - 下方传感器面板实时显示三轴姿态角与加速度数值，随相机晃动平滑刷新；
  - 开启 VoiceOver，双击操作按钮与双指轻击朗读传感器面板均正常响应。

---

### 场景 2：全场景 360° 障碍物数据与目标跨帧追踪验证
- **验证目的**：验证全景 360° 各类障碍物（地面、悬挂、跌落、动态）提取精度与 Tracking ID 连续性。
- **测试步骤**：
  1. 在相机正前方 1.5 米放置椅子（地面障碍），左前 1.0 米上方设置 1.6 米悬挂标志（悬挂碰头），前方 2.5 米设向下台阶（跌落断层）；
  2. 测试者手持相机向前缓慢行走一步；
  3. 观察控制台输出的 `ObstacleData` 结构。
- **预期结果**：
  - `data.obstacles` 包含上述三处危险源；
  - 椅子分类为 `groundObstacle`，标牌分类为 `hangingHazard`，台阶分类为 `dropOffHazard`；
  - 移动过程中，椅子的 `id` 全程保持不变，相对接近速度为正值且距离数值平滑缩短；
  - 椅子滑过测试者身侧及后方时，数据持续输出且 `isRearHazard` 正确置为 true。

---

### 场景 3：连续可通行路线与路径折线点解算验证
- **验证目的**：验证自由空间 BEV 栅格中提取的航路路标点序列（Waypoints）与通道瓶颈净宽。
- **测试步骤**：
  1. 将相机置于设有 0.9 米标准开门走廊的前方 2 米处（两侧有阻挡）；
  2. 观察控制台输出的 `PassableRouteData` 数据。
- **预期结果**：
  - `data.isPathAvailable == true`；
  - `data.safeDepth >= 2.0`（安全纵深达 2 米以上）；
  - `data.recommendedHeading` 准确指向门洞中心（偏角误差 $\le 5^\circ$）；
  - `data.waypoints` 包含 4~6 个连续排列的三维折线点，在门框处的路标点 `clearanceWidth` 测量值在 $0.85\text{m} \sim 0.95\text{m}$ 之间。

---

### 场景 4：空间音频与空间几何转换工具箱纯计算测试 (`SpatialAudioKit`)
- **验证目的**：验证工具箱纯函数的精度、无状态特性以及微秒级执行耗时。
- **测试步骤**：
  1. 运行 `SpatialAudioKitTests` 单元测试套件：
     - 测试 `toClockDirection(azimuth: -30.0, distance: 1.8, elevation: -20.0)`；
     - 测试 `toSpatialAudioRenderParams(position: SIMD3(0.5, 0.0, -2.0), boundingSize: SIMD3(0.4, 0.6, 0.4))`；
     - 测试 `toStereoFallbackParams(azimuth: 45.0, distance: 1.0)`；
     - 测试 `checkClearance(heading: 0.0, userWidth: 0.6, depth: 2.0, against: testObstacles)`。
- **预期结果**：
  - 钟点点位准确输出为 `clockHour = 11`，文案包含“11点钟方向，前方1.8米，低矮地面”；
  - 空间音频声源锚点输出为 `AVAudio3DPoint(x: 0.5, y: 0.0, z: -2.0)`，衰减系数与扩展角合法；
  - 双声道声相输出 `stereoPan = 0.707`，脉冲间隔在 100~800ms 内；
  - 碰撞冲突探测耗时 $< 0.1\text{ms}$，各测试用例 100% 通过且无任何 `AVAudioSession` 调用。

---

### 场景 5：全链路端到端处理延迟与 ANE 吞吐基准压测
- **验证目的**：验证全链路端到端处理耗时满足 $\le 130\text{ ms}$（$\ge 8\text{ FPS}$）实时避障红线。
- **测试步骤**：
  1. 开启持续视频推流运行 100 帧；
  2. 统计预处理、ANE 推理、几何解算、路线提取与结果广播的单帧耗时分布。
- **预期结果**：
  - Accelerate 向量化预处理耗时 $\le 12\text{ms}$；
  - ANE CoreML 硬件推理耗时 $\le 100\text{ms}$；
  - 几何反投影、地面拟合、路线提取与 MOT 追踪耗时 $\le 8\text{ms}$；
  - **总单帧端到端耗时稳定在 $121\text{ms} \pm 5\text{ms}$（约 $8.2\text{ FPS}$）**；
  - 运行时物理内存稳定在 $140\text{MB}$ 左右，无内存泄漏与句柄堆积。
