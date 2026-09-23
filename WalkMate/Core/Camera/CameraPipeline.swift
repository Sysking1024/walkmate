//
//  CameraPipeline.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-22.
//

import CoreVideo
import Foundation
import INSCameraSDK
import INSCameraServiceSDK
import UIKit

/// 相机事件与数据监听代理
public protocol CameraPipelineDelegate: AnyObject {
    /// 连接状态变更回调
    func cameraPipeline(_ pipeline: CameraPipelineProtocol, didUpdateState state: CameraConnectionState)
    
    /// 实时全景视频帧与传感器姿态严格对齐到达回调
    func cameraPipeline(_ pipeline: CameraPipelineProtocol, didReceiveFrame frame: PanoramicFrame)
    
    /// 传感器遥测指标更新回调 (供 UI HUD 被动刷新)
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
    
    /// 画面渲染预览视图
    var previewView: UIView? { get }
    
    /// 启动连接并开启预览推流
    func connect()
    
    /// 断开连接并释放硬件资源
    func disconnect()
}

/// 相机连接、生命周期管理与数据流管道实现
/// 负责基于 INSCameraManager.socket() 建立 Wi-Fi 连接，动态协商 X5 编码，驱动视频流与 IMU 时间戳匹配
public final class CameraPipeline: NSObject, CameraPipelineProtocol {
    
    // 代理监听者
    public weak var delegate: CameraPipelineDelegate?
    
    // 当前相机连接状态
    public private(set) var currentState: CameraConnectionState = .noConnection {
        didSet {
            if oldValue != currentState {
                Log.info("相机连接状态变更: \(oldValue.rawValue) -> \(currentState.rawValue)", category: .camera)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.cameraPipeline(self, didUpdateState: self.currentState)
                }
            }
        }
    }
    
    // 视频流播放器桥接器
    public let playerBridge: StreamPlayerBridgeProtocol
    
    // 六轴传感器处理器
    public let gyroHandler: GyroDataHandlerProtocol
    
    // 提供给外部 UI 渲染全景实时画面的视图
    public var previewView: UIView? {
        return playerBridge.previewView
    }
    
    // 遥测数据分发定时器 (约 10Hz)
    private var telemetryTimer: Timer?
    
    // 帧率滑动窗口计算器
    private var frameCount: Int = 0
    private var lastFpsCalculationTime: TimeInterval = 0
    private var currentFps: Float = 0.0
    
    /// 构造函数，支持依赖注入以利于脱机测试
    public init(
        playerBridge: StreamPlayerBridgeProtocol = StreamPlayerBridge(),
        gyroHandler: GyroDataHandlerProtocol = GyroDataHandler()
    ) {
        self.playerBridge = playerBridge
        self.gyroHandler = gyroHandler
        super.init()
        
        setupBridgeCallbacks()
        setupNotificationsAndKVO()
    }
    
    deinit {
        stopTelemetryTimer()
        NotificationCenter.default.removeObserver(self)
        INSCameraManager.socket().removeObserver(self, forKeyPath: #keyPath(INSCameraManager.cameraState))
    }
    
    /// 建立桥接器内部回调
    private func setupBridgeCallbacks() {
        // 将陀螺仪处理器注入播放器桥接器，使 player.gyroDelegate 指向 GyroDataHandler
        playerBridge.gyroDelegate = gyroHandler as? INSCameraSessionGyroDelegate
        
        // 视频帧解码到达
        playerBridge.onFrameDecoded = { [weak self] pixelBuffer, ptsMs in
            self?.handleDecodedFrame(pixelBuffer: pixelBuffer, timestampMs: ptsMs)
        }
        
        // 播放器异常
        playerBridge.onError = { [weak self] error in
            guard let self = self else { return }
            Log.error("播放器抛出异常", error: error, category: .camera)
            DispatchQueue.main.async {
                self.delegate?.cameraPipeline(self, didEncounterError: error)
            }
        }
    }
    
    /// 监听系统通知与 KVO 状态变化
    private func setupNotificationsAndKVO() {
        // 开启官方自动重连
        INSCameraManager.socket().autoReconnect = true
        
        // 监听相机状态 KVO
        INSCameraManager.socket().addObserver(
            self,
            forKeyPath: #keyPath(INSCameraManager.cameraState),
            options: [.new],
            context: nil
        )
        
        // 监听断开与重连通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCameraDidDisconnect),
            name: .INSCameraDidDisconnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCameraConnectionError),
            name: .INSCameraConnectionError,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCameraDidReconnect),
            name: .INSCameraDidReconnect,
            object: nil
        )
    }
    
    // 推流协商并发保护锁
    private var isNegotiatingStream: Bool = false
    
    // MARK: - 控制接口
    
    /// 发起连接
    public func connect() {
        guard currentState != .connected && currentState != .connecting else {
            Log.info("相机当前已处于 \(currentState.rawValue)，忽略重复连接请求", category: .camera)
            return
        }
        
        Log.info("开始通过 Wi-Fi Socket 连接 Insta360 全景相机...", category: .camera)
        currentState = .connecting
        
        // 发起官方 Socket 握手
        INSCameraManager.socket().setup()
    }
    
    /// 主动断开连接
    public func disconnect() {
        Log.info("正在主动断开相机连接并释放推流资源...", category: .camera)
        stopTelemetryTimer()
        isNegotiatingStream = false
        
        playerBridge.stopRunning { _ in }
        INSCameraManager.socket().shutdown()
        
        currentState = .noConnection
        currentFps = 0.0
        frameCount = 0
    }
    
    // MARK: - 握手与推流启动
    
    /// 相机连接成功处理流程
    private func startStreamingAfterConnected() {
        guard !isNegotiatingStream else {
            Log.info("当前正在与相机协商推流，忽略重复请求", category: .camera)
            return
        }
        isNegotiatingStream = true
        currentState = .connected
        startTelemetryTimer()
        
        Log.info("关闭机内拼接，确保相机输出双鱼眼原始流...", category: .camera)
        let cameraOptions = INSCameraOptions()
        cameraOptions.enableInternalSplicing = false
        let internalSplicingType = NSNumber(value: INSCameraOptionsType.internalSplicing.rawValue)
        
        INSCameraManager.shared().commandManager.setOptions(cameraOptions, forTypes: [internalSplicingType]) { [weak self] error, _ in
            guard let self = self else { return }
            if let error = error {
                Log.warning("关闭机内拼接返回（可能未开或无需关闭）: \(error.localizedDescription)", category: .camera)
            }
            
            // 动态查询 X5 编码、分辨率与窗口裁剪参数
            let encodeType = NSNumber(value: INSCameraOptionsType.videoEncode.rawValue)
            let resType = NSNumber(value: INSCameraOptionsType.videoResolution.rawValue)
            let cropType = NSNumber(value: INSCameraOptionsType.windowCropInfo.rawValue)
            
            Log.info("正在向相机预协商推流编码格式与分辨率参数...", category: .camera)
            
            INSCameraManager.shared().commandManager.getOptionsWithTypes([encodeType, resType, cropType]) { [weak self] getErr, options, _ in
                guard let self = self else { return }
                
                var videoEncode: INSVideoEncode = .H264
                var resolution = INSVideoResolution2560x1280x30
                var windowCropInfo: INSWindowCropInfo? = nil
                
                if let options = options {
                    videoEncode = options.videoEncode
                    resolution = options.videoResolution
                    windowCropInfo = options.windowCropInfo
                    Log.info("成功获取相机配置：编码=\(videoEncode.rawValue)，分辨率=\(resolution.width)x\(resolution.height)@\(resolution.fps)fps", category: .camera)
                } else {
                    Log.warning("未能获取相机配置，降级使用默认参数", category: .camera)
                }
                
                // 启动播放器与推流
                self.playerBridge.startRunning(videoEncode: videoEncode, resolution: resolution, windowCropInfo: windowCropInfo) { [weak self] startError in
                    guard let self = self else { return }
                    self.isNegotiatingStream = false
                    
                    if let startError = startError {
                        Log.error("播放器推流启动失败", error: startError, category: .camera)
                        DispatchQueue.main.async {
                            self.delegate?.cameraPipeline(self, didEncounterError: startError)
                        }
                    } else {
                        Log.info("相机推流链路全面贯通！", category: .camera)
                    }
                }
            }
        }
    }
    
    // MARK: - 数据帧与遥测处理
    
    /// 处理解码后的视频帧
    private func handleDecodedFrame(pixelBuffer: CVPixelBuffer, timestampMs: Int64) {
        // 计算推流 FPS (1 秒滑动窗口均值)
        frameCount += 1
        let now = Date().timeIntervalSince1970
        if now - lastFpsCalculationTime >= 1.0 {
            currentFps = Float(frameCount) / Float(now - lastFpsCalculationTime)
            frameCount = 0
            lastFpsCalculationTime = now
        }
        
        // 从陀螺仪缓冲池按时间戳获取匹配的姿态与加速度
        let attitude = gyroHandler.attitude(at: timestampMs)
        
        // 组装标准 PanoramicFrame 交付下游
        let panoramicFrame = PanoramicFrame(
            pixelBuffer: pixelBuffer,
            timestampMs: timestampMs,
            orientation: attitude.orientation,
            acceleration: attitude.acceleration
        )
        
        delegate?.cameraPipeline(self, didReceiveFrame: panoramicFrame)
    }
    
    /// 启动遥测定时器 (以 10Hz 聚合姿态分发给 UI)
    private func startTelemetryTimer() {
        stopTelemetryTimer()
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.dispatchTelemetry()
        }
    }
    
    /// 停止遥测定时器
    private func stopTelemetryTimer() {
        telemetryTimer?.invalidate()
        telemetryTimer = nil
    }
    
    /// 聚合当前姿态并广播遥测数据
    private func dispatchTelemetry() {
        let euler = gyroHandler.currentEulerAngles
        let accel = gyroHandler.currentAcceleration
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        
        let telemetry = SensorTelemetry(
            connectionState: currentState,
            fps: currentFps,
            pitch: euler.pitch,
            roll: euler.roll,
            yaw: euler.yaw,
            acceleration: accel,
            timestampMs: timestamp
        )
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.cameraPipeline(self, didUpdateTelemetry: telemetry)
        }
    }
    
    // MARK: - 通知与 KVO 回调
    
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(INSCameraManager.cameraState) {
            let state = INSCameraManager.socket().cameraState
            Log.debug("收到 INSCameraManager.socket().cameraState KVO 通知: \(state.rawValue)", category: .camera)
            switch state {
            case .connected:
                if currentState != .connected {
                    startStreamingAfterConnected()
                }
            case .connectFailed:
                currentState = .failed
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    let err = NSError(
                        domain: "world.accera.walkmate.camera",
                        code: -101,
                        userInfo: [NSLocalizedDescriptionKey: "相机连接失败，请检查手机是否已连接相机Wi-Fi热点"]
                    )
                    self.delegate?.cameraPipeline(self, didEncounterError: err)
                }
            case .noConnection:
                if currentState == .connected {
                    currentState = .noConnection
                }
            default:
                break
            }
        }
    }
    
    @objc private func handleCameraDidDisconnect(_ notification: Notification) {
        Log.warning("收到 INSCameraDidDisconnect 断开通知", category: .camera)
        currentState = .noConnection
        stopTelemetryTimer()
    }
    
    @objc private func handleCameraConnectionError(_ notification: Notification) {
        Log.error("收到 INSCameraConnectionError 错误通知", category: .camera)
        currentState = .failed
        stopTelemetryTimer()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let err = NSError(
                domain: "world.accera.walkmate.camera",
                code: -100,
                userInfo: [NSLocalizedDescriptionKey: "相机通信链路异常，请确认手机已加入相机Wi-Fi且无其他设备占用"]
            )
            self.delegate?.cameraPipeline(self, didEncounterError: err)
        }
    }
    
    @objc private func handleCameraDidReconnect(_ notification: Notification) {
        Log.info("收到 INSCameraDidReconnect 自动重连通知", category: .camera)
        startStreamingAfterConnected()
    }
}
