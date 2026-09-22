//
//  StreamPlayerBridge.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-22.
//

// 视频流帧提取与硬件解码桥接器
// 架构：先启动 INSCameraMediaSession（建立相机推流管道），再启动 INSCameraSessionPlayer（解码与渲染）
// 这与官方 SDK Sample RecordViewController 保持一致

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
    
    /// 外部注入的陀螺仪代理（由 CameraPipeline 将 GyroDataHandler 注入 player.gyroDelegate）
    var gyroDelegate: INSCameraSessionGyroDelegate? { get set }
    
    /// 配置并启动流播放器
    /// - Parameters:
    ///   - videoEncode: 相机实际推流编码格式 (H.264 / H.265)
    ///   - resolution: 期望视频分辨率
    ///   - completion: 启动结果回调
    func startRunning(videoEncode: INSVideoEncode, resolution: INSVideoResolution, completion: @escaping (Error?) -> Void)
    
    /// 停止流播放器并释放资源
    func stopRunning(completion: ((Error?) -> Void)?)
}

/// 基于 Insta360 官方 INSCameraSessionPlayer 实现的视频解码与渲染桥接器
/// 负责 X5 的 H.265 硬件解码、V6 标定参数绑定与 CVPixelBuffer 帧提取
/// 必须先运行 INSCameraMediaSession 才能调用 INSCameraSessionPlayer.startRunning
public final class StreamPlayerBridge: NSObject, StreamPlayerBridgeProtocol {
    
    // 官方媒体会话（负责建立相机推流管道）
    private let mediaSession = INSCameraMediaSession()
    
    // 官方会话播放器实例（负责解码与渲染）
    private var player: INSCameraSessionPlayer?
    
    // 帧回调闭包
    public var onFrameDecoded: ((CVPixelBuffer, Int64) -> Void)?
    
    // 错误回调闭包
    public var onError: ((Error) -> Void)?
    
    // 外部注入的陀螺仪代理
    public var gyroDelegate: INSCameraSessionGyroDelegate?
    
    // 是否正在推流播放
    public var isRunning: Bool {
        return player?.isRunning() ?? false
    }
    
    // 提供给 SwiftUI 渲染的画面视图
    public var previewView: UIView? {
        return player?.renderView
    }
    
    public override init() {
        super.init()
    }
    
    deinit {
        // 析构时安全停止 mediaSession
        player?.stopRunning()
        mediaSession.stopRunning { _ in }
    }
    
    /// 配置并启动播放器（先启动 mediaSession，再启动 player）
    public func startRunning(videoEncode: INSVideoEncode, resolution: INSVideoResolution, completion: @escaping (Error?) -> Void) {
        // 停止旧 player（若有）
        if let existingPlayer = player, existingPlayer.isRunning() {
            existingPlayer.stopRunning()
        }
        
        // 停止旧 mediaSession（若有）
        if mediaSession.running {
            mediaSession.stopRunning { [weak self] _ in
                self?.startMediaSessionThenPlayer(videoEncode: videoEncode, resolution: resolution, completion: completion)
            }
        } else {
            startMediaSessionThenPlayer(videoEncode: videoEncode, resolution: resolution, completion: completion)
        }
    }
    
    /// 第一步：启动 INSCameraMediaSession
    private func startMediaSessionThenPlayer(videoEncode: INSVideoEncode, resolution: INSVideoResolution, completion: @escaping (Error?) -> Void) {
        Log.info("第一步：配置并启动 INSCameraMediaSession 推流管道，编码=\(videoEncode.rawValue)，分辨率=\(resolution.width)x\(resolution.height)", category: .camera)
        
        // 配置推流参数（与官方 Sample updateConfiguration() 对应）
        mediaSession.expectedVideoResolution = resolution
        mediaSession.videoStreamEncode = videoEncode
        // X5 双目全景：使用主码流（Main Stream）作为预览（对应 INSPreviewStreamTypeMain = 0）
        mediaSession.previewStreamType = INSPreviewStreamType(rawValue: 0)!
        
        // 启动 mediaSession
        mediaSession.startRunning { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                Log.error("INSCameraMediaSession 启动失败", error: error, category: .camera)
                completion(error)
                return
            }
            
            Log.info("INSCameraMediaSession 启动成功，开始初始化解码播放器", category: .camera)
            // 第二步：mediaSession 就绪后，再启动 player
            self.initAndStartPlayer(videoEncode: videoEncode, resolution: resolution, completion: completion)
        }
    }
    
    /// 第二步：初始化播放器属性并启动硬件解码
    private func initAndStartPlayer(videoEncode: INSVideoEncode, resolution: INSVideoResolution, completion: @escaping (Error?) -> Void) {
        Log.info("第二步：初始化 INSCameraSessionPlayer，编码=\(videoEncode.rawValue)", category: .camera)
        
        let newPlayer = INSCameraSessionPlayer()
        newPlayer.delegate = self
        newPlayer.dataSource = self
        // gyroDelegate 由外部注入（由 CameraPipeline 绑定 GyroDataHandler）
        if let gyroDelegate = gyroDelegate {
            newPlayer.gyroDelegate = gyroDelegate
        }
        newPlayer.needCameraPreviewStreamAutoRotate = true
        newPlayer.videoStreamEncode = videoEncode
        newPlayer.expectedVideoResolution = resolution
        
        // 配置全景球形拼接渲染模式
        newPlayer.render.renderModelType.displayType = .sphereStitch
        newPlayer.render.renderModelType.imageLayout = .horizontalMerged
        newPlayer.render.renderModelType.cameraType = INSCameraManager.shared().currentCamera?.cameraType ?? ""
        
        self.player = newPlayer
        
        // 启动播放器（此时 mediaSession 已在运行，player 能正常接收推流）
        newPlayer.startRunning { error in
            if let error = error {
                Log.error("INSCameraSessionPlayer 启动失败", error: error, category: .camera)
                completion(error)
            } else {
                Log.info("INSCameraSessionPlayer 启动成功，全景画面推流链路贯通！", category: .camera)
                // 启动后主动请求 IFrame 防止首帧等待过长
                INSCameraManager.shared().commandManager.requestIFrame { iFrameErr in
                    if let iFrameErr = iFrameErr {
                        Log.warning("requestIFrame 请求失败（非致命）: \(iFrameErr.localizedDescription)", category: .camera)
                    }
                }
                completion(nil)
            }
        }
    }
    
    /// 停止播放器与媒体会话并清理
    public func stopRunning(completion: ((Error?) -> Void)?) {
        Log.info("正在停止 INSCameraSessionPlayer 与 INSCameraMediaSession...", category: .camera)
        
        // 先停止播放器
        player?.stopRunning()
        
        // 再停止 mediaSession
        mediaSession.stopRunning { error in
            if let error = error {
                Log.error("停止 INSCameraMediaSession 出现异常", error: error, category: .camera)
            } else {
                Log.info("INSCameraMediaSession 已安全停止", category: .camera)
            }
            completion?(error)
        }
    }
}

// MARK: - INSCameraSessionPlayerDelegate 视频帧回调
extension StreamPlayerBridge: INSCameraSessionPlayerDelegate {
    
    /// 解码完成第一帧画面
    public func playerDidSetup(_ player: INSCameraSessionPlayer) {
        Log.info("INSCameraSessionPlayer 走完初始化流程，首帧已就绪", category: .camera)
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
    
    /// 为全景播放器提供精确拼接 Offset（X5 专有 mediaOffsetV6）
    public func updateOffset(to player: INSCameraSessionPlayer) -> String? {
        let settings = INSCameraManager.shared().currentCamera?.settings
        if let v6 = settings?.mediaOffsetV6, !v6.isEmpty {
            return v6
        }
        return settings?.mediaOffset
    }
}
