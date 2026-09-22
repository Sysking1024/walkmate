# 接口契约：相机流与传感器管道协议 (Camera Pipeline Contract)

**特性分支**: `001-dap-spatial-perception`  
**关联模型**: [data-model.md](../data-model.md)  
**创建时间**: 2026-09-22  

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

## 三、时序与生命周期行为

1. **连接建立流程**：
   - 调用 `connect()`；
   - 触发 `didUpdateState(.connecting)`；
   - 调用 `INSCameraManager.socket().setup()`；
   - 成功握手后，触发 `didUpdateState(.connected)`；
   - 创建 `INSCameraSessionPlayer`，设置硬件解码并开始推流；
   - 挂载 `INSCameraSessionGyroDelegate` 接收传感器数据。
2. **实时数据输出流程**：
   - 每收到一帧解码后的画面与时间戳匹配的 IMU 数据，打包为 `PanoramicFrame` 并调用 `didReceiveFrame(frame)`；
   - 以约 10Hz 频率聚合推流状态与姿态角度（推流帧率 fps 采用 1 秒滑动窗口均值计算），调用 `didUpdateTelemetry(telemetry)` 供 UI 刷新。
3. **断开与异常处理**：
   - 调用 `disconnect()`：停止播放器，关闭 Socket 连接，触发 `didUpdateState(.noConnection)`；
   - 意外断线：若收到相机掉线通知，在 1 秒内触发 `didUpdateState(.failed)` 并启动退避重连。
