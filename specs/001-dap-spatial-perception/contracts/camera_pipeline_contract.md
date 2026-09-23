# 接口契约：相机流与传感器管道协议 (Camera Pipeline Contract)

**特性分支**: `001-dap-spatial-perception`  
**关联模型**: [data-model.md](../data-model.md)  
**创建时间**: 2026-09-22  

> [!NOTE]
> **交付状态说明**：本契约及其对应的代码实现（`CameraPipeline.swift`、`StreamPlayerBridge.swift`、`GyroDataHandler.swift`）**已经完全开发完毕并通过真机联调验证**，属于**已完成的系统基石（Completed Baseline）**。本规范予以完整保留，对外协议保持绝对稳定，供下游空间感知流水线直接挂载消费。

---

## 一、模块职责

`CameraPipeline` 负责全面管理与 Insta360 全景相机的通信生命周期，拉取 1080P 实时视频流，解码为 `CVPixelBuffer`，接收六轴 IMU 姿态并实现时间戳同步，最后向感知流水线输送 `PanoramicFrame`。

---

## 二、公开协议定义 (Swift Protocol)

```swift
import CoreVideo
import Foundation

/// 相机事件与数据监听代理
public protocol CameraPipelineDelegate: AnyObject {
    /// 连接状态变更回调
    func cameraPipeline(_ pipeline: CameraPipelineProtocol, didUpdateState state: CameraConnectionState)
    
    /// 实时视频帧与传感器姿态同步到达回调
    func cameraPipeline(_ pipeline: CameraPipelineProtocol, didReceiveFrame frame: PanoramicFrame)
    
    /// 传感器遥测指标更新回调 (供 UI HUD 刷新)
    func cameraPipeline(_ pipeline: CameraPipelineProtocol, didUpdateTelemetry telemetry: SensorTelemetry)
    
    /// 发生异常错误回调
    func cameraPipeline(_ pipeline: CameraPipelineProtocol, didEncounterError error: Error)
}

/// 相机管道控制接口
public protocol CameraPipelineProtocol: AnyObject {
    /// 代理监听
    var delegate: CameraPipelineDelegate? { get set }
    
    /// 当前连接状态
    var currentState: CameraConnectionState { get }
    
    /// 启动连接并开启预览流
    func connect()
    
    /// 断开连接并释放硬件资源
    func disconnect()
}
```

---

## 三、时序与生命周期行为 (适配 X5 硬件与官方 SDK)

1. **连接建立与参数预协商流程**：
   - 调用 `connect()`；
   - 触发 `didUpdateState(.connecting)`；
   - 调用 `INSCameraManager.socket().setup()` 发起 Wi-Fi Socket 连接；
   - 监听 KVO `#keyPath(INSCameraManager.cameraState)` 与通知 `.INSCameraDidConnect`；
   - 握手成功后，触发 `didUpdateState(.connected)`；
   - **X5 关键参数预协商与播放器配置**：
     - 调用 `INSCameraManager.shared().commandManager.getOptionsWithTypes([videoEncode, videoResolution])` 获取相机实际编码格式与分辨率（X5 默认为 H.265）；
     - 创建 `INSCameraSessionPlayer`，显式设置 `player.videoStreamEncode = options.videoEncode` 与 `player.expectedVideoResolution = options.videoResolution`，杜绝因编码格式不匹配（以默认 H.264 解 H.265 流）导致的黑屏故障；
     - 挂载 `player.dataSource = self`，实现 `INSCameraSessionPlayerDataSource` 的 `updateOffsetToPlayer(_:)` 方法，优先返回 `settings.mediaOffsetV6`（X5 专有标定参数，旧版 `mediaOffset` 为空），避免无标定参数导致拼接错误；
     - 挂载 `player.delegate = self`，实现 `INSCameraSessionPlayerDelegate` 的 `playerPrepared(_:sampleGroup:)`，通过 `sampleGroup.getPlayerImage().pixelBuffer` 提取 1080P/全景原生 `CVPixelBuffer` 与 `pts_ms` 毫秒时间戳；
     - 挂载 `player.gyroDelegate = self`，实现 `INSCameraSessionGyroDelegate` 的 `onParsedGyroData(_:timestampMs:)`，接收并解析 `INSGyroRawItem`（包含 `timestamp`、`accelX/Y/Z` 加速度与 `rotX/Y/Z` 角速度）；
     - 调用 `player.startRunning { error in ... }` 启动播放器与硬件推流。
2. **实时数据输出流程**：
   - 每收到一帧解码后的画面与时间戳匹配的 IMU 数据，打包为 `PanoramicFrame` 并调用 `didReceiveFrame(frame)` 输送给下游深度推理与几何模块；
   - 以约 10Hz 频率聚合推流状态与姿态角度（推流帧率 fps 采用 1 秒滑动窗口均值计算），调用 `didUpdateTelemetry(telemetry)` 供 UI HUD 刷新。
3. **断开与异常处理**：
   - 调用 `disconnect()`：停止播放器 `player.stopRunning()`，关闭 Socket 连接 `INSCameraManager.socket().shutdown()`，触发 `didUpdateState(.noConnection)`；
   - 意外断线：监听 `.INSCameraDidDisconnect` 与 `.INSCameraConnectionError`，在 1 秒内触发 `didUpdateState(.failed)` 并启动自动重连机制。
