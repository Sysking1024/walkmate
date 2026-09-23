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
public final class CameraViewModel: ObservableObject, CameraPipelineDelegate, SpatialPerceptionDelegate, PerceptionDataCollectorDelegate {
    
    // MARK: - 响应式状态 (Published Properties)
    
    @Published public var connectionState: CameraConnectionState = .noConnection
    @Published public var isPerceiving: Bool = false
    @Published public var previewView: UIView?
    @Published public var latestError: String?
    
    // 空间感知数据输出快照 (保留供无障碍与调试观测)
    @Published public var latestObstacles: ObstacleData?
    @Published public var latestRoute: PassableRouteData?
    
    // 实测多模态数据采集响应式状态
    @Published public var collectorState: CollectorState = .idle
    @Published public var recordingDuration: Double = 0
    @Published public var isRecording: Bool = false
    @Published public var finishedSessionMetadata: SessionMetadata?
    @Published public var showRecordingFinishedNotice: Bool = false
    
    /// 感知主控按钮是否可用（仅当相机连接成功后方可点击）
    public var isPerceptionEnabled: Bool {
        return connectionState == .connected
    }
    
    // MARK: - 底层组件依赖
    
    public let pipeline: CameraPipelineProtocol
    public var perceptionEngine: SpatialPerceptionEngineProtocol?
    public let audioPlayer: SpatialAudioPlayerProtocol
    public let collector: PerceptionDataCollectorProtocol
    
    public init(
        pipeline: CameraPipelineProtocol = CameraPipeline(),
        perceptionEngine: SpatialPerceptionEngineProtocol? = nil,
        audioPlayer: SpatialAudioPlayerProtocol = SpatialAudioPlayer.shared,
        collector: PerceptionDataCollectorProtocol = PerceptionDataCollector.shared
    ) {
        self.pipeline = pipeline
        self.audioPlayer = audioPlayer
        self.collector = collector
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
        self.collector.delegate = self
        self.bindEngineCollectorHooks()
    }
    
    // MARK: - 引擎数据采集钩子绑定
    
    private func bindEngineCollectorHooks() {
        perceptionEngine?.onFrameProcessed = { [weak self] frame, depthMatrix, groundPlane, cameraHeight, rawObstacles, routeData, latencyMs in
            guard let self = self, self.isRecording else { return }
            
            // 业务层前向 130° 扇区与 1 米近身危险过滤
            let forwardNearObstacles = rawObstacles.filter { abs($0.azimuth) <= 65.0 && $0.distance <= 1.0 }
            let nearestHazard = forwardNearObstacles.min(by: { $0.distance < $1.distance })
            let activeObstacle = nearestHazard?.position
            let activeNav = routeData?.waypoints.first?.position
            
            self.collector.recordFrame(
                frame: frame,
                depthMatrix: depthMatrix,
                groundPlane: groundPlane,
                cameraHeight: cameraHeight,
                rawObstacles: rawObstacles,
                hazardObstacles: forwardNearObstacles,
                routeData: routeData,
                activeObstacleTarget: activeObstacle,
                activeNavigationTarget: activeNav,
                latencyMs: latencyMs
            )
        }
    }
    
    // MARK: - 用户交互指令 (Actions)
    
    /// 触发实测数据采集的启停控制
    public func toggleRecording() {
        if isRecording {
            collector.stopRecording { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let metadata):
                        self?.finishedSessionMetadata = metadata
                        self?.showRecordingFinishedNotice = true
                        UIAccessibility.post(notification: .announcement, argument: "实测数据采集完成，已保存至本地沙盒，可打开数据面板导出")
                    case .failure(let error):
                        self?.latestError = "停止录制异常: \(error.localizedDescription)"
                        Log.error("停止录制异常: \(error.localizedDescription)", category: .perception)
                    }
                }
            }
        } else {
            do {
                try collector.startRecording()
                UIAccessibility.post(notification: .announcement, argument: "已开始采集实测数据")
            } catch {
                self.latestError = error.localizedDescription
                Log.error("启动实测数据采集失败: \(error.localizedDescription)", category: .perception)
                UIAccessibility.post(notification: .announcement, argument: "无法开启采集：\(error.localizedDescription)")
            }
        }
    }
    
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
    
    /// 启动空间感知与 3D 空间音频
    public func startPerception() {
        guard !isPerceiving else { return }
        isPerceiving = true
        do {
            try audioPlayer.start()
            // 关键体验闭环：启动成功后立即播发一次即时声学确认音，确保视障测试者即刻获得听觉反馈
            audioPlayer.playRewardSound()
        } catch {
            Log.error("空间音频启动失败: \(error.localizedDescription)", category: .audio)
            self.latestError = "音频启动失败: \(error.localizedDescription)"
        }
        
        // 容错自愈：若冷启动阶段感知引擎因资源加载延迟等原因未就绪，在此自动进行二次懒加载重试
        if perceptionEngine == nil {
            do {
                let engine = try SpatialPerceptionEngine()
                engine.delegate = self
                self.perceptionEngine = engine
                Log.info("空间感知引擎延迟初始化成功", category: .perception)
            } catch {
                Log.error("空间感知引擎延迟初始化失败: \(error.localizedDescription)", category: .perception)
                self.latestError = "感知引擎加载失败: \(error.localizedDescription)"
            }
        }
        
        perceptionEngine?.start()
        Log.info("已开启空间感知流水线与 3D 空间音频导航", category: .perception)
        UIAccessibility.post(notification: .announcement, argument: "已开启空间感知与音频导航")
    }
    
    /// 停止空间感知并使空间音频立即静音
    public func stopPerception() {
        guard isPerceiving else { return }
        isPerceiving = false
        audioPlayer.reset()
        perceptionEngine?.stop()
        Log.info("已停止空间感知流水线，空间音频已恢复静音", category: .perception)
        UIAccessibility.post(notification: .announcement, argument: "已停止空间感知")
    }
    
    // MARK: - CameraPipelineDelegate 回调
    
    public func cameraPipeline(_ pipeline: CameraPipelineProtocol, didUpdateState state: CameraConnectionState) {
        self.connectionState = state
        self.previewView = pipeline.previewView
        Log.info("相机连接状态变更: \(state.rawValue)", category: .camera)
        
        // 掉线安全自愈：相机异常断开或连接失败时，若正在录制立即安全停止，若感知正在运行则强制安全停止并静音
        if state == .failed || state == .noConnection {
            if isRecording {
                collector.stopRecording(completion: nil)
            }
            if isPerceiving {
                stopPerception()
            } else {
                perceptionEngine?.stop()
            }
        }
        
        // 连接成功时自动清除历史错误提示条
        if state == .connected {
            self.latestError = nil
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
    
    private var receivedFrameCounter: Int = 0
    public func cameraPipeline(_ pipeline: CameraPipelineProtocol, didReceiveFrame frame: PanoramicFrame) {
        // 关键门禁：仅当感知处于开启状态时，才将视频帧送入模型流水线
        guard isPerceiving else { return }
        receivedFrameCounter += 1
        if receivedFrameCounter % 30 == 1 {
            Log.info("全景视频帧持续送入模型推理流水线 (累计已投递: \(receivedFrameCounter) 帧)", category: .perception)
        }
        perceptionEngine?.processFrame(frame)
        // 同一帧投递到总线，供场景描述线订阅，避免两条线争抢管线代理
        FrameBus.shared.publish(frame)
    }
    
    public func cameraPipeline(_ pipeline: CameraPipelineProtocol, didUpdateTelemetry telemetry: SensorTelemetry) {
        // 维持遥测静默接收（主界面不再渲染冗余 HUD）
    }
    
    public func cameraPipeline(_ pipeline: CameraPipelineProtocol, didEncounterError error: Error) {
        self.latestError = error.localizedDescription
        Log.error("相机管道异常: \(error.localizedDescription)", error: error, category: .camera)
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
        if let hazard = nearestHazard {
            Log.info("检出前向贴身障碍物: 距离=\(String(format: "%.2f", hazard.distance))m 偏角=\(String(format: "%.1f", hazard.azimuth))° 坐标=\(hazard.position)", category: .perception)
        }
        audioPlayer.setObstacleTarget(position: nearestHazard?.position)
    }
    
    public func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didProducePassableRoute data: PassableRouteData) {
        // 关键门禁：杜绝停止感知后后台上一帧异步飞行结果唤醒音频
        guard isPerceiving else { return }
        self.latestRoute = data
        
        // 导航首点指引：仅提取第 1 个航路点三维相对坐标驱动自然步频领路脚步声 (FR-009)
        let firstWaypoint = data.waypoints.first?.position
        if let wp = firstWaypoint {
            Log.info("检出可行路线首航路点: \(wp), 深度=\(String(format: "%.1f", data.safeDepth))m, 偏角=\(String(format: "%.1f", data.recommendedHeading))°", category: .perception)
        } else {
            Log.warning("前方受阻，无有效可行航路点", category: .perception)
        }
        audioPlayer.setNavigationTarget(position: firstWaypoint)
    }
    
    public func perceptionEngine(_ engine: SpatialPerceptionEngineProtocol, didEncounterError error: Error) {
        Log.error("空间感知引擎异常: \(error.localizedDescription)", category: .perception)
    }
    
    // MARK: - PerceptionDataCollectorDelegate 回调
    
    public func collector(_ collector: PerceptionDataCollectorProtocol, didChangeState state: CollectorState) {
        DispatchQueue.main.async {
            self.collectorState = state
            self.isRecording = (state == .recording)
        }
    }
    
    public func collector(_ collector: PerceptionDataCollectorProtocol, didUpdateDuration seconds: Double) {
        DispatchQueue.main.async {
            self.recordingDuration = seconds
        }
    }
    
    public func collector(_ collector: PerceptionDataCollectorProtocol, didEncounterError error: Error) {
        DispatchQueue.main.async {
            self.latestError = error.localizedDescription
            UIAccessibility.post(notification: .announcement, argument: "数据采集提示：\(error.localizedDescription)")
        }
    }
}

/// 极简真机实测主界面 (Minimal Field Pilot)
public struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    @State private var showSessionSheet: Bool = false
    
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
            
            // 界面右上角：实测采集与日志管理复合控制项 (T010 / FR-001)
            VStack {
                HStack(spacing: 10) {
                    Spacer()
                    
                    // 1. 实测数据采集主控胶囊按钮 (REC / 00:00)
                    Button(action: {
                        viewModel.toggleRecording()
                    }) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(viewModel.isRecording ? Color.white : Color.red)
                                .frame(width: 10, height: 10)
                            
                            Text(viewModel.isRecording ? formattedRecordingDuration : "REC 录制")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(minWidth: 48, minHeight: 48) // 触控靶心严格 >= 48x48 像素 (宪章原则四)
                        .background(viewModel.isRecording ? Color.red.opacity(0.85) : Color.black.opacity(0.75))
                        .clipShape(Capsule())
                        .shadow(radius: 4)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(viewModel.isRecording ? "停止实测采集" : "开始实测采集")
                    .accessibilityHint(viewModel.isRecording ? "双击停止当前实测数据采集并保存到本地" : "双击启动多模态实测数据流与高保真传感器记录")
                    
                    // 2. 实测数据包与调试日志面板入口 (FR-001)
                    Button(action: {
                        showSessionSheet = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.badge.gearshape")
                                .font(.system(size: 13, weight: .bold))
                            Text("数据")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minWidth: 48, minHeight: 48) // 触控靶心严格 >= 48x48 像素
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule())
                        .shadow(radius: 4)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("实测数据包与调试日志面板")
                    .accessibilityHint("双击打开实测数据会话管理面板，支持 AirDrop 导出与日志复制")
                }
                .padding(.trailing, 16)
                .padding(.top, 16)
                Spacer()
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
        .sheet(isPresented: $showSessionSheet) {
            SessionManagementSheet()
        }
        .alert("实测采集完成", isPresented: $viewModel.showRecordingFinishedNotice) {
            Button("稍后查看", role: .cancel) {}
            Button("立即查看与导出") {
                showSessionSheet = true
            }
        } message: {
            if let meta = viewModel.finishedSessionMetadata {
                Text("会话「\(meta.sessionId)」已安全落盘。\n录制时长: \(String(format: "%.1f", meta.durationSeconds)) 秒，遥测帧数: \(meta.totalTelemetryFrames) 帧，图像快照: \(meta.totalImageSnapshots) 张。\n是否立即打开会话面板进行 AirDrop 导出？")
            } else {
                Text("本次实测会话已安全落盘，可前往数据面板查看并导出。")
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
    
    // MARK: - 录制时长格式化计算属性
    
    private var formattedRecordingDuration: String {
        let total = Int(viewModel.recordingDuration.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

/// 实时调试日志抽屉视图
public struct LogSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logs: [String] = Log.recentLogs
    @State private var isCopied: Bool = true
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部复制成功提示横幅
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("全部 \(logs.count) 条最新日志已拷贝到剪贴板，可直接粘贴！")
                        .font(.footnote)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(0.25))
                
                // 日志展示滚动区域
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            if logs.isEmpty {
                                Text("暂无日志记录")
                                    .foregroundColor(.gray)
                                    .padding(20)
                            } else {
                                ForEach(Array(logs.enumerated()), id: \.offset) { index, line in
                                    Text(line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(logColor(for: line))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(index)
                                }
                            }
                        }
                        .padding(12)
                    }
                    .background(Color(red: 0.08, green: 0.08, blue: 0.1))
                    .onAppear {
                        if !logs.isEmpty {
                            proxy.scrollTo(logs.count - 1, anchor: .bottom)
                        }
                    }
                }
                
                // 底部操作栏：再次复制与刷新
                HStack(spacing: 16) {
                    Button(action: {
                        UIPasteboard.general.string = logs.joined(separator: "\n")
                        isCopied = true
                    }) {
                        HStack {
                            Image(systemName: "doc.on.doc.fill")
                            Text("再次拷贝全部日志")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    Button(action: {
                        logs = Log.recentLogs
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.gray.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(16)
                .background(Color(red: 0.12, green: 0.12, blue: 0.14))
            }
            .navigationTitle("系统调试日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func logColor(for line: String) -> Color {
        if line.contains("ERROR") || line.contains("❌") {
            return .red
        } else if line.contains("WARNING") || line.contains("⚠️") {
            return .orange
        } else if line.contains("INFO") {
            return .white
        } else {
            return .gray
        }
    }
}

