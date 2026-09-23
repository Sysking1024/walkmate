//
//  SpatialAudioPlayer.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-23.
//

import AVFoundation
import Foundation
import simd

// MARK: - 空间音频播放器接口协议
public protocol SpatialAudioPlayerProtocol: AnyObject, Sendable {
    func start() throws
    func stop()
    var isRunning: Bool { get }
    func setObstacleTarget(position: SIMD3<Float>?)
    func setNavigationTarget(position: SIMD3<Float>?)
    func playRewardSound()
    func reset()
}
