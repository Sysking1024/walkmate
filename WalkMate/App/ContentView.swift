//
//  ContentView.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-22.
//

import Combine
import SwiftUI
import UIKit

/// 主视图模型：桥接底层相机管道事件与 SwiftUI 响应式状态
public final class CameraViewModel: ObservableObject, CameraPipelineDelegate, SpatialPerceptionDelegate {
    
    @Published public var connectionState: CameraConnectionState = .noConnection
    @Published public var telemetry: SensorTelemetry = .offline
    @Published public var previewView: UIView?
    @Published public var latestError: String?
    
    // 空间感知数据输出快照
    @Published public var latestObstacles: ObstacleData?
    @Published public var latestRoute: PassableRouteData?
    
    // 底层相机数据管道
    public let pipeline: CameraPipelineProtocol
    // 空间感知核心引擎
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
    
    /// 触发连接/断开切换
    public func toggleConnection() {
        if connectionState == .connected || connectionState == .connecting {
            pipeline.disconnect()
        } else {
            pipeline.connect()
        }
    }
    
    // MARK: - CameraPipelineDelegate 回调
    
    public func cameraPipeline(_ pipeline: CameraPipelineProtocol, didUpdateState state: CameraConnectionState) {
        self.connectionState = state
        self.previewView = pipeline.previewView
        
        // 状态变更触发针对视障用户的屏幕朗读通知与感知引擎生命周期联动
        let announcement: String
        switch state {
        case .connected:
            announcement = "全景相机连接成功，已开启实时视频流与空间感知流水线"
            perceptionEngine?.start()
        case .connecting:
            announcement = "正在连接全景相机，请稍候"
        case .failed:
            announcement = "全景相机连接失败，请检查Wi-Fi连接"
            perceptionEngine?.stop()
        case .noConnection:
            announcement = "全景相机已断开连接"
            perceptionEngine?.stop()
        }
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }
    
    public func cameraPipeline(_ pipeline: CameraPipelineProtocol, didReceiveFrame frame: PanoramicFrame) {
        // 实时视频与姿态对齐帧驱动空间感知引擎计算流水线
        perceptionEngine?.processFrame(frame)
        // 同一帧投递到总线，供场景描述线订阅，避免两条线争抢管线代理
        FrameBus.shared.publish(frame)
    }
    
    public func cameraPipeline(_ pipeline: CameraPipelineProtocol, didUpdateTelemetry telemetry: SensorTelemetry) {
        self.telemetry = telemetry
    }
    
    public func cameraPipeline(_ pipeline: CameraPipelineProtocol, didEncounterError error: Error) {
        self.latestError = error.localizedDescription
        UIAccessibility.post(notification: .announcement, argument: "相机管道遇到错误：\(error.localizedDescription)")
    }
    
    // MARK: - SpatialPerceptionDelegate 回调
    
    public func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didProduceObstacles data: ObstacleData) {
        self.latestObstacles = data
    }
    
    public func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didProducePassableRoute data: PassableRouteData) {
        self.latestRoute = data
    }
    
    public func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didEncounterError error: Error) {
        Log.error("空间感知引擎异常: \(error.localizedDescription)", category: .perception)
    }
}

/// 主控制界面
public struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 全景实时流渲染监控区
                    PanoramicStreamView(
                        previewView: viewModel.previewView,
                        isConnected: viewModel.connectionState == .connected
                    )
                    
                    // 设备连接主控制按钮（触控尺寸严格 >= 48x48pt，对比度 >= 4.5:1）
                    Button(action: {
                        viewModel.toggleConnection()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: buttonIconName)
                                .font(.system(size: 20, weight: .bold))
                            Text(buttonTitle)
                                .font(.system(size: 18, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52) // 严格大于 48 像素无障碍规范
                        .background(buttonBackgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: buttonBackgroundColor.opacity(0.3), radius: 6, y: 3)
                    }
                    .accessibilityLabel(buttonTitle)
                    .accessibilityHint(viewModel.connectionState == .connected ? "点击将安全关闭实时推流并断开相机连接" : "点击将发起与 Insta360 全景相机的 Wi-Fi 通信连接")
                    
                    // 六轴传感器遥测数据 HUD
                    SensorTelemetryCard(telemetry: viewModel.telemetry)
                    
                    // 空间感知数据 HUD 卡片 (当相机处于连接推流状态时呈现)
                    if viewModel.connectionState == .connected {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .foregroundColor(.green)
                                Text("全向空间感知状态")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Spacer()
                                Text(viewModel.latestObstacles != nil ? "实时解算中" : "就绪")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            HStack(spacing: 20) {
                                VStack(alignment: .leading) {
                                    Text("检出障碍物")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Text("\(viewModel.latestObstacles?.obstacles.count ?? 0) 个")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                                
                                Divider().frame(height: 30)
                                
                                VStack(alignment: .leading) {
                                    Text("通行状态")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Text(viewModel.latestRoute?.isPathAvailable == true ? "畅通" : "受阻")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(viewModel.latestRoute?.isPathAvailable == true ? .green : .orange)
                                }
                                
                                Divider().frame(height: 30)
                                
                                VStack(alignment: .leading) {
                                    Text("安全纵深")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Text(String(format: "%.1f m", viewModel.latestRoute?.safeDepth ?? 0.0))
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(red: 0.14, green: 0.14, blue: 0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("空间感知指标：检出障碍物 \(viewModel.latestObstacles?.obstacles.count ?? 0) 个，通行状态 \(viewModel.latestRoute?.isPathAvailable == true ? "畅通" : "受阻")，安全纵深 \(String(format: "%.1f", viewModel.latestRoute?.safeDepth ?? 0.0)) 米")
                    }
                    
                    // 异常提示条 (若存在)
                    if let error = viewModel.latestError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.footnote)
                                .foregroundColor(.red)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(20)
            }
            .background(Color(red: 0.07, green: 0.07, blue: 0.08).ignoresSafeArea()) // 全局深黑背景
            .navigationTitle("WalkMate 空间感知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(red: 0.07, green: 0.07, blue: 0.08), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
    
    // 按钮标题
    private var buttonTitle: String {
        switch viewModel.connectionState {
        case .connected:
            return "断开相机连接"
        case .connecting:
            return "正在连接中..."
        case .failed:
            return "连接失败 (点击重试)"
        case .noConnection:
            return "连接全景相机"
        }
    }
    
    // 按钮图标
    private var buttonIconName: String {
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
    
    // 按钮背景色
    private var buttonBackgroundColor: Color {
        switch viewModel.connectionState {
        case .connected:
            return Color(red: 0.85, green: 0.25, blue: 0.2) // 沉稳红色
        case .connecting:
            return Color(red: 0.85, green: 0.55, blue: 0.1) // 琥珀橙色
        case .failed:
            return Color(red: 0.75, green: 0.2, blue: 0.2)  // 警告红
        case .noConnection:
            return Color(red: 0.15, green: 0.45, blue: 0.9) // 标准无障碍高对比度蓝
        }
    }
}
