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
public final class StreamPlayerBridge: NSObject, StreamPlayerBridgeProtocol {
    
    // 官方会话播放器实例
    private var player: INSCameraSessionPlayer?
    
    // 帧回调闭包
    public var onFrameDecoded: ((CVPixelBuffer, Int64) -> Void)?
    
    // 错误回调闭包
    public var onError: ((Error) -> Void)?
    
    // 是否正在推流播放
    public var isRunning: Bool {
        return player?.running ?? false
    }
    
    // 提供给 SwiftUI 渲染的画面视图
    public var previewView: UIView? {
        return player?.renderView
    }
    
    public override init() {
        super.init()
    }
    
    /// 配置并启动播放器
    public func startRunning(videoEncode: INSVideoEncode, resolution: INSVideoResolution, completion: @escaping (Error?) -> Void) {
        // 先确保旧播放器停止
        if let existingPlayer = player, existingPlayer.running {
            existingPlayer.stopRunning { [weak self] _ in
                self?.initAndStartPlayer(videoEncode: videoEncode, resolution: resolution, completion: completion)
            }
        } else {
            initAndStartPlayer(videoEncode: videoEncode, resolution: resolution, completion: completion)
        }
    }
    
    /// 初始化播放器属性并启动硬件解码
    private func initAndStartPlayer(videoEncode: INSVideoEncode, resolution: INSVideoResolution, completion: @escaping (Error?) -> Void) {
        Log.info("开始初始化 INSCameraSessionPlayer，编码: \(videoEncode.rawValue)，分辨率宽: \(resolution.width) 高: \(resolution.height)", category: .camera)
        
        let newPlayer = INSCameraSessionPlayer()
        newPlayer.delegate = self
        newPlayer.dataSource = self
        newPlayer.needCameraPreviewStreamAutoRotate = true
        newPlayer.videoStreamEncode = videoEncode
        newPlayer.expectedVideoResolution = resolution
        newPlayer.render.renderModelType.displayType = .sphereStitch
        
        self.player = newPlayer
        
        newPlayer.startRunning { error in
            if let error = error {
                Log.error("INSCameraSessionPlayer 启动失败", error: error, category: .camera)
                completion(error)
            } else {
                Log.info("INSCameraSessionPlayer 启动成功，开始硬件推流", category: .camera)
                completion(nil)
            }
        }
    }
    
    /// 停止播放器并清理
    public func stopRunning(completion: ((Error?) -> Void)?) {
        guard let player = self.player, player.running else {
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
