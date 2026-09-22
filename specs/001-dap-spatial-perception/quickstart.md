# 快速验证指南：基于 DAP 的全景空间感知与避障系统 (Quickstart Guide)

**特性分支**: `001-dap-spatial-perception`  
**关联模型**: [data-model.md](./data-model.md) | [contracts/](./contracts/)  
**创建时间**: 2026-09-22  

---

## 一、验证前置条件 (Prerequisites)

1. **硬件环境**：
   - iPhone 15 及以上机型（搭载 Apple 神经引擎 ANE，运行 iOS 17.0+）；
   - Insta360 X5 全景相机（电量充足，开启 Wi-Fi 热点）；
   - Mac 开发机（macOS Sonoma 14.0+，安装 Xcode 15.0+ 及 `xcodegen`）。
2. **模型资产准备**：
   - 确保 `dap_256x512_int8.mlpackage`（319 MB）已放置在工程资源目录中。

---

## 二、工程生成与构建命令 (Setup Commands)

```bash
# 1. 进入工作空间根目录
cd "$(git rev-parse --show-toplevel)"

# 2. 通过 xcodegen 自动生成原生 Xcode 工程
xcodegen generate

# 3. 在真机上编译构建应用
xcodebuild -project WalkMate.xcodeproj \
           -scheme WalkMate \
           -destination "generic/platform=iOS" \
           build
```

---

## 三、端到端真机验证场景 (Validation Scenarios)

### 场景 1：相机连接、控制 UI 与实时流预览验证
- **测试步骤**：
  1. 手机 Wi-Fi 连接至 Insta360 X5 热点；
  2. 启动 WalkMate App，点击顶部的【连接设备】按钮；
  3. 观察界面渲染。
- **预期结果**：
  - 按钮状态变为【断开设备】；
  - 界面中央开始流畅渲染 1080P 全景实时视频流（帧率稳定在 15 FPS 以上，无黑屏与画面撕裂）；
  - 下方传感器面板实时显示三轴姿态角与加速度数值，随相机晃动实时平滑刷新；
  - 开启 VoiceOver，双击操作按钮与双指轻击朗读传感器面板均正常响应。

---

### 场景 2：安全通行走廊识别验证（开门测试）
- **测试步骤**：
  1. 将相机正对 2 米外一扇开启的 0.9 米室内门；
  2. 观察控制台输出的 `SpatialPerceptionResult.corridor` 数据。
- **预期结果**：
  - `isPassable == true`；
  - `recommendedSteeringAngle` 偏差在 $\pm 5^\circ$ 以内；
  - `clearanceWidth` 测量值在 $0.85\text{m} \sim 0.95\text{m}$ 之间；
  - `targetAnchor` 准确指向门洞中心三维坐标。

---

### 场景 3：前向生理视角 Top 3 障碍物检测验证
- **测试步骤**：
  1. 在正前方 1.5 米放置一把椅子，在左前方 50 度 1.0 米放置立柱；
  2. 观察 `SpatialPerceptionResult.obstacles` 数组。
- **预期结果**：
  - 输出恰好包含该两处障碍物，数量 $\le 3$；
  - 立柱被识别为左侧威胁（$X \approx -0.8\text{m}$）；
  - 行人向相机走来时，其 `approachRate` 为正值且被动态提升为 Top 1。

---

### 场景 4：动态后退与倒车雷达模式验证
- **测试步骤**：
  1. 在身后 1 米处放置一张矮凳或站立在下行台阶前 1.5 米处；
  2. 测试者起步向后退一步。
- **预期结果**：
  - 200 毫秒内（2 帧内），`result.motionState` 变为 `.backward`；
  - 障碍物检测自动切换为后方视角，输出后方矮凳坐标（$Z > 0$ 且 `isRearHazard == true`）；
  - 若后方有台阶，触发 `DropOffHazardEvent` 紧急告警（`isRearHazard == true`）。

---

### 场景 5：全链路端到端延迟压测验证
- **测试步骤**：
  1. 运行持续推流测试 60 秒；
  2. 查看真机日志统计的各阶段耗时。
- **预期结果**：
  - Accelerate 预处理耗时 $\le 12\text{ms}$；
  - ANE CoreML 硬件推理耗时 $\le 100\text{ms}$；
  - 几何解算与走廊规划耗时 $\le 8\text{ms}$；
  - **总单帧端到端延迟严格控制在 130 毫秒以内（稳定 $\approx 8\text{ FPS}$）**。
