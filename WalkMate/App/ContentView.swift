//
//  ContentView.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-22.
//

import Combine
import SwiftUI
import UIKit

//
//  ContentView.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-22（修订于 2026-09-23）.
//

import Combine
import SwiftUI
import UIKit

/// 主视图模型：桥接底层相机管道事件与 SwiftUI 响应式状态，实现启停解耦与业务层前向避障导引
public final class CameraViewModel: ObservableObject, CameraPipelineDelegate, SpatialPerceptionDelegate {
    
    // MARK: - 响应式状态 (Published Properties)
    
    @Published public var connectionState: CameraConnectionState = .noConnection
    @Published public var isPerceiving: Bool = false
    @Published public var previewView: UIView?
    @Published public var latestError: String?
    
    // 空间感知数据输出快照 (保留供无障碍与调试观测)
    @Published public var latestObstacles: ObstacleData?
    @Published public var latestRoute: PassableRouteData?
    
    /// 感知主控按钮是否可用（仅当相机连接成功后方可点击）
    public var isPerceptionEnabled: Bool {
        return connectionState == .connected
    }
    
    // MARK: - 底层组件依赖
    
    public let pipeline: CameraPipelineProtocol
    public let perceptionEngine: SpatialPerceptionEngineProtocol?
    
    public init(
        pipeline: CameraPipelineProtocol = CameraPipeline(),
        perceptionEngine: SpatialPerceptionEngineProtocol? = nil
    ) {
        self.pipeline = pipeline
        if let engine = perceptionEngine {
            self.perceptionEngine = engine
        } else {
            do {
                self.perceptionEngine = try SpatialPerceptionEngine()
            } catch {
                Log.error("空间感知引擎初始化失败: \(error.localizedDescription)", category: .perception)
                self.perceptionEngine = nil
            }
        }
        
        self.pipeline.delegate = self
        self.perceptionEngine?.delegate = self
    }
    
    // MARK: - 用户交互指令 (Actions)
    
    /// 触发相机连接/断开切换
    public func toggleConnection() {
        if connectionState == .connected || connectionState == .connecting {
            if isPerceiving {
                stopPerception()
            }
            pipeline.disconnect()
        } else {
            pipeline.connect()
        }
    }
    
    /// 触发大模型空间感知与空间音频的开启/停止
    public func togglePerception() {
        guard connectionState == .connected else { return }
        if isPerceiving {
            stopPerception()
        } else {
            startPerception()
        }
    }
    
    /// 启动空间感知与 3D HRTF 空间音频
    public func startPerception() {
        guard !isPerceiving else { return }
        isPerceiving = true
        try? SpatialAudioPlayer.shared.start()
        perceptionEngine?.start()
        Log.info("已开启空间感知流水线与 3D 空间音频导航", category: .perception)
        UIAccessibility.post(notification: .announcement, argument: "已开启空间感知与音频导航")
    }
    
    /// 停止空间感知并使空间音频立即静音
    public func stopPerception() {
        guard isPerceiving else { return }
        isPerceiving = false
        SpatialAudioPlayer.shared.reset()
        perceptionEngine?.stop()
        Log.info("已停止空间感知流水线，空间音频已恢复静音", category: .perception)
        UIAccessibility.post(notification: .announcement, argument: "已停止空间感知")
    }
    
    // MARK: - CameraPipelineDelegate 回调
    
    public func cameraPipeline(_ pipeline: CameraPipelineProtocol, didUpdateState state: CameraConnectionState) {
        self.connectionState = state
        self.previewView = pipeline.previewView
        
        // 掉线安全自愈：相机异常断开或连接失败时，若感知正在运行则强制安全停止并静音
        if state == .failed || state == .noConnection {
            if isPerceiving {
                stopPerception()
            } else {
                perceptionEngine?.stop()
            }
        }
        
        // 状态变更触发针对视障用户的屏幕朗读通知
        let announcement: String
        switch state {
        case .connected:
            announcement = "全景相机连接成功"
        case .connecting:
            announcement = "正在连接全景相机，请稍候"
        case .failed:
            announcement = "全景相机连接失败，请检查Wi-Fi连接"
        case .noConnection:
            announcement = "全景相机已断开连接"
        }
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }
    
    public func cameraPipeline(_ pipeline: CameraPipelineProtocol, didReceiveFrame frame: PanoramicFrame) {
        // 关键门禁：仅当感知处于开启状态时，才将视频帧送入模型流水线
        guard isPerceiving else { return }
        perceptionEngine?.processFrame(frame)
    }
    
    public func cameraPipeline(_ pipeline: CameraPipelineProtocol, didUpdateTelemetry telemetry: SensorTelemetry) {
        // 维持遥测静默接收（主界面不再渲染冗余 HUD）
    }
    
    public func cameraPipeline(_ pipeline: CameraPipelineProtocol, didEncounterError error: Error) {
        self.latestError = error.localizedDescription
        UIAccessibility.post(notification: .announcement, argument: "相机管道遇到错误：\(error.localizedDescription)")
    }
    
    // MARK: - SpatialPerceptionDelegate 回调
    
    public func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didProduceObstacles data: ObstacleData) {
        // 关键门禁：杜绝停止感知后后台上一帧异步飞行结果唤醒音频
        guard isPerceiving else { return }
        self.latestObstacles = data
        
        // 业务层前向 130° 扇区 (|azimuth| <= 65°) 与 1 米近身双重过滤 (FR-008)
        let forwardNearObstacles = data.obstacles.filter { obstacle in
            abs(obstacle.azimuth) <= 65.0 && obstacle.distance <= 1.0
        }
        
        // 提取其中距离最近的一个危险障碍物
        let nearestHazard = forwardNearObstacles.min(by: { $0.distance < $1.distance })
        SpatialAudioPlayer.shared.setObstacleTarget(position: nearestHazard?.position)
    }
    
    public func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didProducePassableRoute data: PassableRouteData) {
        // 关键门禁：杜绝停止感知后后台上一帧异步飞行结果唤醒音频
        guard isPerceiving else { return }
        self.latestRoute = data
        
        // 导航首点指引：仅提取第 1 个航路点三维相对坐标驱动自然步频领路脚步声 (FR-009)
        let firstWaypoint = data.waypoints.first?.position
        SpatialAudioPlayer.shared.setNavigationTarget(position: firstWaypoint)
    }
    
    public func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didEncounterError error: Error) {
        Log.error("空间感知引擎异常: \(error.localizedDescription)", category: .perception)
    }
}

/// 极简真机实测主界面 (Minimal Field Pilot)
public struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // 1. 全屏沉浸式全景推流预览背景 (FR-001 / SC-001)
            PanoramicStreamView(
                previewView: viewModel.previewView,
                isConnected: viewModel.connectionState == .connected,
                isFullScreen: true
            )
            .ignoresSafeArea()
            
            // 2. 界面顶部异常提示条 (若存在)
            if let error = viewModel.latestError {
                VStack {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.top, 16)
                    
                    Spacer()
                }
            }
            
            // 3. 界面底部极简双按钮主控区域 (FR-003 / FR-004 / FR-005)
            VStack {
                Spacer()
                
                HStack(spacing: 20) {
                    // 左下角：相机连接/断开按钮
                    Button(action: {
                        viewModel.toggleConnection()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: connectionButtonIcon)
                                .font(.system(size: 20, weight: .bold))
                            Text(connectionButtonTitle)
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(minWidth: 120, minHeight: 56) // 触控靶心 >= 56pt，远超 48pt 底线
                        .background(connectionButtonColor)
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.4), radius: 6, y: 3)
                    }
                    .accessibilityLabel("相机连接控制，当前状态：\(connectionButtonTitle)")
                    .accessibilityHint(viewModel.connectionState == .connected ? "双击断开全景相机连接" : "双击发起与全景相机的 Wi-Fi 通信连接")
                    
                    Spacer()
                    
                    // 右下角：感知大模型与 3D 空间音频启停主控按钮
                    Button(action: {
                        viewModel.togglePerception()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: perceptionButtonIcon)
                                .font(.system(size: 20, weight: .bold))
                            Text(perceptionButtonTitle)
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(minWidth: 120, minHeight: 56) // 触控靶心 >= 56pt
                        .background(perceptionButtonColor)
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.4), radius: 6, y: 3)
                    }
                    .disabled(!viewModel.isPerceptionEnabled)
                    .accessibilityLabel("空间感知与音频导航主控，当前状态：\(perceptionButtonTitle)")
                    .accessibilityHint(viewModel.isPerceptionEnabled ? (viewModel.isPerceiving ? "双击停止大模型感知并静音" : "双击启动大模型感知与空间音频领路") : "相机未连接，当前不可用")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }
    
    // MARK: - 相机连接按钮视觉计算属性
    
    private var connectionButtonTitle: String {
        switch viewModel.connectionState {
        case .connected:
            return "断开"
        case .connecting:
            return "连接中"
        case .failed:
            return "重试"
        case .noConnection:
            return "连接相机"
        }
    }
    
    private var connectionButtonIcon: String {
        switch viewModel.connectionState {
        case .connected:
            return "bolt.horizontal.slash.fill"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .failed:
            return "arrow.clockwise"
        case .noConnection:
            return "wifi"
        }
    }
    
    private var connectionButtonColor: Color {
        switch viewModel.connectionState {
        case .connected:
            return Color(red: 0.85, green: 0.25, blue: 0.2) // 醒目红
        case .connecting:
            return Color(red: 0.85, green: 0.55, blue: 0.1) // 琥珀橙
        case .failed:
            return Color(red: 0.75, green: 0.2, blue: 0.2)  // 警告红
        case .noConnection:
            return Color(red: 0.15, green: 0.45, blue: 0.9) // 高对比度无障碍深蓝
        }
    }
    
    // MARK: - 感知启停按钮视觉计算属性
    
    private var perceptionButtonTitle: String {
        return viewModel.isPerceiving ? "停止感知" : "开始感知"
    }
    
    private var perceptionButtonIcon: String {
        return viewModel.isPerceiving ? "stop.fill" : "play.fill"
    }
    
    private var perceptionButtonColor: Color {
        guard viewModel.isPerceptionEnabled else {
            return Color.gray.opacity(0.4) // 禁用灰色
        }
        return viewModel.isPerceiving ? Color(red: 0.85, green: 0.25, blue: 0.2) : Color(red: 0.15, green: 0.65, blue: 0.35) // 运行红 / 启动绿
    }
}

