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
public final class CameraViewModel: ObservableObject, CameraPipelineDelegate {
    
    @Published public var connectionState: CameraConnectionState = .noConnection
    @Published public var telemetry: SensorTelemetry = .offline
    @Published public var previewView: UIView?
    @Published public var latestError: String?
    
    // 底层相机数据管道
    public let pipeline: CameraPipelineProtocol
    
    public init(pipeline: CameraPipelineProtocol = CameraPipeline()) {
        self.pipeline = pipeline
        self.pipeline.delegate = self
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
        
        // 状态变更触发针对视障用户的屏幕朗读通知
        let announcement: String
        switch state {
        case .connected:
            announcement = "全景相机连接成功，已开启实时视频流与传感器同步"
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
        // 首期仅用于驱动界面画面渲染；后续将直接接入深度模型
    }
    
    public func cameraPipeline(_ pipeline: CameraPipelineProtocol, didUpdateTelemetry telemetry: SensorTelemetry) {
        self.telemetry = telemetry
    }
    
    public func cameraPipeline(_ pipeline: CameraPipelineProtocol, didEncounterError error: Error) {
        self.latestError = error.localizedDescription
        UIAccessibility.post(notification: .announcement, argument: "相机管道遇到错误：\(error.localizedDescription)")
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
