//
//  StreamPlayerBridge.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-22.
//

import CoreVideo
import Foundation
import INSCameraSDK
import INSCoreMedia
import UIKit

/// 视频流帧提取与硬件解码桥接器协议
public protocol StreamPlayerBridgeProtocol: AnyObject {
    /// 视频帧到达回调闭包 (CVPixelBuffer, 毫秒时间戳)
    var onFrameDecoded: ((CVPixelBuffer, Int64) -> Void)? { get set }
    
    /// 播放器错误回调
    var onError: ((Error) -> Void)? { get set }
    
    /// 获取用于 UI 渲染的实时画面视图
    var previewView: UIView? { get }
    
    /// 播放器是否正在运行
    var isRunning: Bool { get }
    
    /// 外部注入的陀螺仪代理（绑定至 player.gyroDelegate）
    var gyroDelegate: INSCameraSessionGyroDelegate? { get set }
    
    /// 配置并启动流播放器
    /// - Parameters:
    ///   - videoEncode: 相机实际推流编码格式 (H.264 / H.265)
    ///   - resolution: 期望视频分辨率
    ///   - completion: 启动结果回调
    func startRunning(videoEncode: INSVideoEncode, resolution: INSVideoResolution, completion: @escaping (Error?) -> Void)
    
    /// 配置并启动流播放器（含裁剪参数）
    func startRunning(videoEncode: INSVideoEncode, resolution: INSVideoResolution, windowCropInfo: INSWindowCropInfo?, completion: @escaping (Error?) -> Void)
    
    /// 停止流播放器并释放资源
    func stopRunning(completion: ((Error?) -> Void)?)
}

public extension StreamPlayerBridgeProtocol {
    func startRunning(videoEncode: INSVideoEncode, resolution: INSVideoResolution, completion: @escaping (Error?) -> Void) {
        startRunning(videoEncode: videoEncode, resolution: resolution, windowCropInfo: nil, completion: completion)
    }
}

/// 基于 Insta360 官方 INSCameraSessionPlayer 实现的视频解码与渲染桥接器
/// 负责 X5 的 H.265 硬件解码、球面动态拼接渲染与 CVPixelBuffer 帧提取
/// 严格采用官方 Sample (RecordViewController) 架构：持单例 Player，杜绝底层 session 重入冲突
public final class StreamPlayerBridge: NSObject, StreamPlayerBridgeProtocol {
    
    // 官方会话播放器实例（单例持久持有，杜绝重复创建导致的底层 _renderSession 冲突）
    public let player: INSCameraSessionPlayer

    /// 预览渲染模式。训练页录集锦时切成 .planeStitch（拼好的等矩形全景），其余时候保持球面
    public static var preferredDisplayType: INSDisplayType = .sphereStitch
    
    // 帧回调闭包
    public var onFrameDecoded: ((CVPixelBuffer, Int64) -> Void)?
    
    // 错误回调闭包
    public var onError: ((Error) -> Void)?
    
    // 窗口裁剪信息缓存（用于实时球面几何计算与拼接）
    public var windowCropInfo: INSWindowCropInfo?
    
    // 外部注入的陀螺仪代理
    public var gyroDelegate: INSCameraSessionGyroDelegate? {
        didSet {
            player.gyroDelegate = gyroDelegate
        }
    }
    
    // 是否正在推流播放
    public var isRunning: Bool {
        return player.isRunning()
    }
    
    // 提供给 SwiftUI 渲染的画面视图
    public var previewView: UIView? {
        return player.renderView
    }
    
    public override init() {
        let sessionPlayer = INSCameraSessionPlayer()
        self.player = sessionPlayer
        super.init()
        
        sessionPlayer.delegate = self
        sessionPlayer.dataSource = self
        sessionPlayer.needCameraPreviewStreamAutoRotate = true
        sessionPlayer.render.renderModelType.displayType = Self.preferredDisplayType
    }
    
    deinit {
        player.stopRunning()
    }
    
    /// 启动播放器推流
    public func startRunning(
        videoEncode: INSVideoEncode,
        resolution: INSVideoResolution,
        windowCropInfo: INSWindowCropInfo?,
        completion: @escaping (Error?) -> Void
    ) {
        self.windowCropInfo = windowCropInfo
        self.player.videoStreamEncode = videoEncode
        self.player.expectedVideoResolution = resolution
        
        Log.info("配置 INSCameraSessionPlayer，编码: \(videoEncode.rawValue)，分辨率宽: \(resolution.width) 高: \(resolution.height)", category: .camera)
        
        // 若当前已在运行，先停止旧 session 再启动
        if player.isRunning() {
            Log.info("播放器已处于运行中，先停止旧推流再重新启动...", category: .camera)
            player.stopRunning { [weak self] _ in
                self?.doStartPlayer(completion: completion)
            }
        } else {
            doStartPlayer(completion: completion)
        }
    }
    
    private func doStartPlayer(completion: @escaping (Error?) -> Void) {
        Log.info("开始调用 INSCameraSessionPlayer.startRunning...", category: .camera)
        player.startRunning { error in
            if let error = error {
                Log.error("INSCameraSessionPlayer.startRunning 失败", error: error, category: .camera)
                completion(error)
            } else {
                Log.info("INSCameraSessionPlayer.startRunning 成功，请求首帧 I-Frame...", category: .camera)
                INSCameraManager.shared().commandManager.requestIFrame { reqError in
                    if let reqError = reqError {
                        Log.warning("requestIFrame 失败（非致命）: \(reqError.localizedDescription)", category: .camera)
                    }
                }
                completion(nil)
            }
        }
    }
    
    /// 停止播放器并清理
    public func stopRunning(completion: ((Error?) -> Void)?) {
        guard player.isRunning() else {
            completion?(nil)
            return
        }
        
        Log.info("正在停止 INSCameraSessionPlayer...", category: .camera)
        player.stopRunning { error in
            if let error = error {
                Log.error("停止 INSCameraSessionPlayer 出现异常", error: error, category: .camera)
            } else {
                Log.info("INSCameraSessionPlayer 已安全停止", category: .camera)
            }
            completion?(error)
        }
    }
}

// MARK: - INSCameraSessionPlayerDelegate 视频帧回调
extension StreamPlayerBridge: INSCameraSessionPlayerDelegate {
    
    /// 解码完成第一帧画面
    public func playerDidSetup(_ player: INSCameraSessionPlayer) {
        Log.info("INSCameraSessionPlayer 首帧已就绪并开始渲染", category: .camera)
    }
    
    /// 核心视频帧渲染回调：获取解码后的 CVPixelBuffer
    public func playerPrepared(_ player: INSCameraSessionPlayer, sampleGroup: INSSampleGroup) {
        let playerImage = sampleGroup.getPlayerImage()
        let pixelBuffer = playerImage.pixelBuffer
        let ptsMs = Int64(playerImage.pts_ms)
        
        // 分发给上层管道进行时间戳对齐与深度推理
        onFrameDecoded?(pixelBuffer, ptsMs)
    }
    
    /// 播放器异常回调
    public func player(_ player: INSCameraSessionPlayer, didOccurWithError error: Error) {
        Log.error("INSCameraSessionPlayer 播放中发生错误", error: error, category: .camera)
        onError?(error)
    }
}

// MARK: - INSCameraSessionPlayerDataSource 标定参数数据源
extension StreamPlayerBridge: INSCameraSessionPlayerDataSource {
    
    /// 为全景播放器提供精确拼接 Offset（优先 X5 专有 mediaOffsetV6）
    public func updateOffset(to player: INSCameraSessionPlayer) -> String? {
        return getMediaOffset()
    }
    
    /// 配置全景拼接渲染模型参数（对齐官方 SDK RecordViewController 实现）
    public func updateRenderModelType(to player: INSCameraSessionPlayer, renderModelType: INSRenderModelType) -> INSRenderModelType {
        renderModelType.displayType = Self.preferredDisplayType
        renderModelType.imageLayout = .horizontalMerged
        renderModelType.isHalfFisheye = false
        renderModelType.isSelfieVideo = false
        renderModelType.touchMode = false
        renderModelType.opticalFlowType = .disflow
        renderModelType.isHalfFisheyeBulletTime = false
        renderModelType.contentMode = .fitScreen
        renderModelType.preferDynamicVertex = false
        renderModelType.aiFlowBottomPercision = .unknown
        renderModelType.dynamicAlphaFlag = false
        renderModelType.usingFisheyeMask = false
        
        if let windowCropInfo = self.windowCropInfo {
            renderModelType.cropInfo = INSCropInfo()
            renderModelType.cropInfo.srcWidth = Int32(windowCropInfo.srcWidth)
            renderModelType.cropInfo.srcHeight = Int32(windowCropInfo.srcHeight)
            renderModelType.cropInfo.dstWidth = Int32(windowCropInfo.dstWidth)
            renderModelType.cropInfo.dstHeight = Int32(windowCropInfo.dstHeight)
        }
        
        renderModelType.aiFlowVersion = 1
        renderModelType.expandFlowWorkRegion = true
        renderModelType.aiFlowFrameInterval = 2
        renderModelType.colorFusion = true
        renderModelType.dynamicStitchType = .dynamicVideo
        renderModelType.cameraType = INSCameraManager.shared().currentCamera?.cameraType ?? ""
        return renderModelType
    }
    
    /// 配置实时防抖与水平校准参数
    public func updateStabilizerParam(to player: INSCameraSessionPlayer) -> INSRealtimeStabilizerParam {
        let param = INSRealtimeStabilizerParam()
        if let offset = getMediaOffset() {
            param.offset = offset
        }
        param.preferredStabMode = .still
        param.maxFilterAngleDegree = 25
        param.sweepTime = 0
        param.windSize = 3
        param.fps = 30.0
        return param
    }
    
    /// 配置防抖动态参数
    public func updateStabilizerDynamicParam(to player: INSCameraSessionPlayer, dynamicParam: INSStabilizerDynamicParam) -> INSStabilizerDynamicParam {
        let param = dynamicParam
        param.onlineFilterType = .pathPlanSlidingWin
        return param
    }
    
    /// 计算精准的拼接偏移量 Offset
    private func getMediaOffset() -> String? {
        let settings = INSCameraManager.shared().currentCamera?.settings
        var mediaOffset = settings?.mediaOffsetV6 ?? settings?.mediaOffset
        
        if let offset = mediaOffset, INSLensOffset.isValidOffset(offset) {
            var converted = offset
            if let windowCropInfo = self.windowCropInfo {
                converted = INSOffsetCalculator.cropOffset(
                    converted,
                    srcWidth: Int32(windowCropInfo.srcWidth),
                    srcHeight: Int32(windowCropInfo.srcHeight),
                    dstWidth: Int32(windowCropInfo.dstWidth),
                    dstHeight: Int32(windowCropInfo.dstHeight),
                    xOffset: windowCropInfo.cropOffsetX,
                    yOffset: windowCropInfo.cropOffsetY
                )
            }
            if INSCameraManager.shared().currentCamera?.name != kInsta360CameraNameX4 {
                mediaOffset = INSOffsetCalculator.convertOffset(converted, to: .oneX3040_2_2880)
            } else {
                mediaOffset = converted
            }
        }
        return mediaOffset
    }
}
