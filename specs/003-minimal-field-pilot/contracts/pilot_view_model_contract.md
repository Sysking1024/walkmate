# 接口契约：极简实测 ViewModel 接口规范 (Pilot ViewModel Contract)

**特性分支**: `003-minimal-field-pilot`  
**关联文件**: `WalkMate/App/ContentView.swift`（`CameraViewModel`）  
**状态**: Approved

---

## 接口定义

```swift
import Combine
import SwiftUI
import UIKit

/// 极简真机实测视图模型契约
public protocol CameraViewModelProtocol: ObservableObject, CameraPipelineDelegate, SpatialPerceptionDelegate {
    
    // MARK: - 响应式状态 (Published Properties)
    
    /// 相机连接状态（决定左下角按钮与右下角使能）
    var connectionState: CameraConnectionState { get }
    
    /// 感知流水线与空间音频是否正在运行（决定右下角按钮文案与颜色）
    var isPerceiving: Bool { get }
    
    /// 全屏渲染视图引用
    var previewView: UIView? { get }
    
    /// 最新错误提示信息（可选）
    var latestError: String? { get }
    
    // MARK: - 用户交互控制指令 (Actions)
    
    /// 左下角按钮触发：切换相机连接与断开
    func toggleConnection()
    
    /// 右下角按钮触发：切换感知大模型与空间音频的开始/停止
    func togglePerception()
}
```

---

## 行为与副作用契约 (Behavior & Side Effect Contracts)

### 1. `toggleConnection()`

```swift
func toggleConnection()
```
- **前置条件**：用户轻击左下角“连接相机 / 断开相机”按钮。
- **行为规范**：
  - 若 `connectionState == .connected || connectionState == .connecting`：
    - 若 `isPerceiving == true`，先自动调用 `stopPerception()`；
    - 调用 `pipeline.disconnect()`；
    - `connectionState` 变为 `.noConnection`。
  - 否则（处于 `.noConnection` 或 `.failed`）：
    - 调用 `pipeline.connect()`；
    - `connectionState` 变为 `.connecting`。

---

### 2. `togglePerception()`

```swift
func togglePerception()
```
- **前置条件**：用户轻击右下角“开始感知 / 停止感知”按钮，且 `connectionState == .connected`。
- **行为规范**：
  - 若 `isPerceiving == false`：
    - 赋值 `isPerceiving = true`；
    - 启动底层音频图：`try? SpatialAudioPlayer.shared.start()`；
    - 启动感知引擎：`perceptionEngine?.start()`；
    - 发出系统 VoiceOver 朗读通知：“已开启空间感知与音频导航”。
  - 若 `isPerceiving == true`：
    - 赋值 `isPerceiving = false`；
    - 重置音频播放器并立即静音：`SpatialAudioPlayer.shared.reset()`；
    - 停止感知引擎内部状态：`perceptionEngine?.stop()`；
    - 发出系统 VoiceOver 朗读通知：“已停止空间感知”。

---

---

### 3. `cameraPipeline(_:didUpdateState:)`

```swift
func cameraPipeline(_ pipeline: CameraPipelineProtocol, didUpdateState state: CameraConnectionState)
```
- **行为规范**：
  - 更新 `connectionState = state` 与 `previewView = pipeline.previewView`；
  - **掉线安全自愈**：若 `state == .failed || state == .noConnection`：
    - 若此时 `isPerceiving == true`，**必须自动重置感知与音频**：设置 `isPerceiving = false`，调用 `SpatialAudioPlayer.shared.reset()` 立即恢复静音，调用 `perceptionEngine?.stop()`；
  - 发送对应的无障碍 VoiceOver 语音播报（连接成功、连接中、连接失败、断开连接）。

---

### 4. `cameraPipeline(_:didReceiveFrame:)`

```swift
func cameraPipeline(_ pipeline: CameraPipelineProtocol, didReceiveFrame frame: PanoramicFrame)
```
- **行为规范**：
  - **关键门禁**：仅当 `isPerceiving == true` 时，才执行 `perceptionEngine?.processFrame(frame)`；
  - 若 `isPerceiving == false`，直接忽略该帧。保证相机全屏预览持续流畅的同时，零 CPU/ANE 额外计算开销。

---

### 5. `perceptionEngine(_:didProduceObstacles:)`

```swift
func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didProduceObstacles data: ObstacleData)
```
- **行为规范**：
  - **关键门禁**：`guard isPerceiving else { return }`（彻底杜绝停止感知后后台上一帧异步结果唤醒音频）；
  - 执行业务层过滤：
    1. 角度范围：$|\text{azimuth}| \le 65.0^\circ$（前向 $130^\circ$ 扇区）；
    2. 距离范围：$\text{distance} \le 1.0\text{m}$（注：贴身 $< 0.3\text{m}$ 盲区已由底层 `ObstacleDetector` 锁定在 0.3m，此处直接取物理距离）；
    3. 取距离最近的一个：`.min(by: { $0.distance < $1.distance })`；
  - 若存在目标，调用 `SpatialAudioPlayer.shared.setObstacleTarget(position: nearestHazard.position)`；
  - 若无目标，调用 `SpatialAudioPlayer.shared.setObstacleTarget(position: nil)`（立即静音）。

---

### 6. `perceptionEngine(_:didProducePassableRoute:)`

```swift
func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didProducePassableRoute data: PassableRouteData)
```
- **行为规范**：
  - **关键门禁**：`guard isPerceiving else { return }`（彻底杜绝停止感知后后台上一帧异步结果唤醒音频）；
  - 提取首个航路点：`let target = data.waypoints.first?.position`；
  - 调用 `SpatialAudioPlayer.shared.setNavigationTarget(position: target)`（驱动 1.1s 自然步频领路脚步声，若路线为空则传 `nil` 静音）。

