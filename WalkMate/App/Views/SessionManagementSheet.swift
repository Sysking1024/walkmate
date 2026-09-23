//
//  SessionManagementSheet.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-23.
//

import SwiftUI
import UIKit

// MARK: - 系统原生分享控制器包装器 (用于 AirDrop 隔空投送)

/// 包装 UIActivityViewController 的 SwiftUI 视图表示层，用于支持 AirDrop 及系统分享菜单
public struct ActivityView: UIViewControllerRepresentable {
    /// 待分享的项目列表 (例如 zip 压缩包的本地沙盒 URL)
    public let activityItems: [Any]
    /// 可选的自定义活动服务
    public let applicationActivities: [UIActivity]?
    
    public init(activityItems: [Any], applicationActivities: [UIActivity]? = nil) {
        self.activityItems = activityItems
        self.applicationActivities = applicationActivities
    }
    
    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        return controller
    }
    
    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 会话管理与日志导出抽屉视图

/// 实测会话管理与 AirDrop 导出抽屉视图 (满足 FR-001, FR-006, FR-007 与宪章原则四、原则五)
public struct SessionManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    /// 会话存储管理器接口
    private let storageManager: SessionStorageManagerProtocol
    
    /// 分段标签页枚举
    public enum ManagementTab: String, CaseIterable, Identifiable {
        case sessions = "实测数据包"
        case logs = "系统调试日志"
        
        public var id: String { rawValue }
    }
    
    @State private var selectedTab: ManagementTab = .sessions
    
    // MARK: - 会话管理状态
    @State private var sessions: [SessionSummaryItem] = []
    @State private var isArchiving: Bool = false
    @State private var archivingSessionId: String? = nil
    @State private var archivingProgress: Double = 0.0
    @State private var shareZipURL: URL? = nil
    @State private var showShareSheet: Bool = false
    
    // 弹窗确认状态
    @State private var sessionToDelete: SessionSummaryItem? = nil
    @State private var showDeleteConfirmAlert: Bool = false
    @State private var showClearAllConfirmAlert: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showErrorMessageAlert: Bool = false
    
    // MARK: - 文本日志状态
    @State private var logs: [String] = []
    @State private var isLogCopied: Bool = false
    
    public init(storageManager: SessionStorageManagerProtocol = SessionStorageManager.shared) {
        self.storageManager = storageManager
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部标签分段选择器
                Picker("功能切换", selection: $selectedTab) {
                    ForEach(ManagementTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
                
                Divider()
                    .background(Color.white.opacity(0.15))
                
                // 选项卡内容展示区
                switch selectedTab {
                case .sessions:
                    sessionsContentView
                case .logs:
                    logsContentView
                }
            }
            .background(Color(red: 0.08, green: 0.08, blue: 0.1).ignoresSafeArea())
            .navigationTitle("实测数据与日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("完成")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(minWidth: 48, minHeight: 48) // 触控靶心严格 >= 48x48 像素
                    }
                    .accessibilityLabel("关闭面板")
                    .accessibilityHint("双击返回主界面")
                }
            }
            .onAppear {
                refreshSessions()
                refreshLogs()
            }
            // AirDrop 原生分享弹窗
            .sheet(isPresented: $showShareSheet) {
                if let url = shareZipURL {
                    ActivityView(activityItems: [url])
                }
            }
            // 单项删除二次确认对话框
            .alert("确认删除会话", isPresented: $showDeleteConfirmAlert) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let target = sessionToDelete {
                        executeDeleteSession(target)
                    }
                }
            } message: {
                if let target = sessionToDelete {
                    Text("确定彻底删除实测会话「\(target.sessionId)」吗？包含的所有时序遥测与图像快照将被永久清理，此操作不可撤销。")
                }
            }
            // 清空全部二次确认对话框
            .alert("确认清空全部会话", isPresented: $showClearAllConfirmAlert) {
                Button("取消", role: .cancel) {}
                Button("清空全部", role: .destructive) {
                    executeClearAllSessions()
                }
            } message: {
                Text("确定清空沙盒中全部 \(sessions.count) 个实测会话吗？所有本地数据包将被永久删除，此操作不可撤销。")
            }
            // 错误提示对话框
            .alert("操作失败", isPresented: $showErrorMessageAlert) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "发生未知错误，请重试")
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - 会话管理选项卡主视图
    
    private var sessionsContentView: some View {
        VStack(spacing: 0) {
            // 状态栏：展示会话统计与清空操作入口
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                    Text("已记录 \(sessions.count) 个会话")
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.85))
                }
                
                Spacer()
                
                if !sessions.isEmpty {
                    Button(action: {
                        showClearAllConfirmAlert = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 13))
                            Text("清空全部")
                                .font(.footnote)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.red.opacity(0.9))
                        .frame(minWidth: 48, minHeight: 48) // 触控靶心 >= 48x48 像素
                    }
                    .accessibilityLabel("清空全部历史会话")
                    .accessibilityHint("双击弹出清空所有实测采集包的确认窗口")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Color(red: 0.12, green: 0.12, blue: 0.15))
            
            // 会话列表或空状态
            if sessions.isEmpty {
                emptySessionsView
            } else {
                List {
                    ForEach(sessions) { item in
                        sessionRowView(item)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    refreshSessions()
                }
            }
        }
    }
    
    // MARK: - 单个会话信息卡片
    
    private func sessionRowView(_ item: SessionSummaryItem) -> some View {
        let isCurrentArchiving = isArchiving && archivingSessionId == item.sessionId
        
        return VStack(alignment: .leading, spacing: 10) {
            // 第一行：会话 ID 与状态徽标
            HStack {
                Image(systemName: "cube.transparent")
                    .foregroundColor(.cyan)
                    .font(.system(size: 15, weight: .bold))
                
                Text(item.sessionId)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Spacer()
                
                // 占用体积徽标
                Text(item.sizeFormatted)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.3))
                    .foregroundColor(.cyan)
                    .clipShape(Capsule())
            }
            
            // 第二行：关键指标 (时长、遥测帧数、创建时间)
            HStack(spacing: 12) {
                Label(item.durationFormatted, systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                
                Label("\(item.totalFrames) 帧", systemImage: "waveform.path.ecg")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                
                Spacer()
                
                Text(formatDate(item.createdAt))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // 第三行：操作栏 (一键 AirDrop 导出与删除)
            HStack(spacing: 12) {
                // AirDrop 导出主按钮
                Button(action: {
                    exportSession(item)
                }) {
                    HStack(spacing: 6) {
                        if isCurrentArchiving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                            Text("打包中 \(Int(archivingProgress * 100))%")
                                .font(.system(size: 13, weight: .bold))
                        } else {
                            Image(systemName: "airdrop")
                                .font(.system(size: 14, weight: .bold))
                            Text("AirDrop 导出")
                                .font(.system(size: 13, weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 48) // 触控靶心严格 >= 48x48 像素
                    .background(isCurrentArchiving ? Color.gray : Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isArchiving)
                .accessibilityLabel("AirDrop 导出会话 \(item.sessionId)")
                .accessibilityHint("双击将会话打包为 zip 并呼出系统隔空投送面板")
                
                // 单项删除按钮
                Button(action: {
                    sessionToDelete = item
                    showDeleteConfirmAlert = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.red)
                        .frame(width: 48, height: 48) // 触控靶心严格 >= 48x48 像素
                        .background(Color.red.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isArchiving)
                .accessibilityLabel("删除会话 \(item.sessionId)")
                .accessibilityHint("双击弹出删除该会话的确认对话框")
            }
        }
        .padding(14)
        .background(Color(red: 0.14, green: 0.14, blue: 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - 空会话状态视图
    
    private var emptySessionsView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "tray")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.6))
            
            Text("暂无实测采集会话")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
            
            Text("点击主界面右上角的「REC 录制」胶囊按钮\n即可在户外边走边记录全模态时序遥测与全景快照")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
                .lineSpacing(4)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
    
    // MARK: - 系统调试日志选项卡主视图 (保留原有日志功能)
    
    private var logsContentView: some View {
        VStack(spacing: 0) {
            // 复制反馈条
            if isLogCopied {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("全部 \(logs.count) 条最新日志已拷贝到系统剪贴板！")
                        .font(.footnote)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(0.25))
            }
            
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
            
            // 底部日志操作栏
            HStack(spacing: 14) {
                Button(action: {
                    UIPasteboard.general.string = logs.joined(separator: "\n")
                    isLogCopied = true
                    UIAccessibility.post(notification: .announcement, argument: "全部日志已拷贝到剪贴板")
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc.fill")
                        Text("拷贝全部文本日志")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 48) // 触控靶心 >= 48x48 像素
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("拷贝全部系统调试文本日志")
                .accessibilityHint("双击将当前所有调试日志复制到系统剪贴板")
                
                Button(action: {
                    refreshLogs()
                    UIAccessibility.post(notification: .announcement, argument: "已刷新日志列表")
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48) // 触控靶心严格 48x48 像素
                        .background(Color.gray.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("刷新日志")
                .accessibilityHint("双击重新获取最新的调试日志条目")
            }
            .padding(16)
            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
        }
    }
    
    // MARK: - 数据刷新与操作执行
    
    /// 重新加载会话摘要列表
    private func refreshSessions() {
        sessions = storageManager.listSessions()
    }
    
    /// 重新加载文本日志
    private func refreshLogs() {
        logs = Log.recentLogs
    }
    
    /// 执行 AirDrop 导出会话
    private func exportSession(_ item: SessionSummaryItem) {
        guard !isArchiving else { return }
        isArchiving = true
        archivingSessionId = item.sessionId
        archivingProgress = 0.0
        
        let manager = storageManager
        let sessionId = item.sessionId
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let zipURL = try manager.createArchive(sessionId: sessionId) { progress in
                    DispatchQueue.main.async {
                        self.archivingProgress = progress
                    }
                }
                
                DispatchQueue.main.async {
                    self.isArchiving = false
                    self.archivingSessionId = nil
                    self.shareZipURL = zipURL
                    self.showShareSheet = true
                    UIAccessibility.post(notification: .announcement, argument: "会话打包完成，已打开 AirDrop 分享面板")
                }
            } catch {
                DispatchQueue.main.async {
                    self.isArchiving = false
                    self.archivingSessionId = nil
                    self.errorMessage = "打包压缩失败: \(error.localizedDescription)"
                    self.showErrorMessageAlert = true
                    UIAccessibility.post(notification: .announcement, argument: "打包压缩失败")
                }
            }
        }
    }
    
    /// 执行删除单个会话
    private func executeDeleteSession(_ item: SessionSummaryItem) {
        do {
            try storageManager.deleteSession(sessionId: item.sessionId)
            refreshSessions()
            sessionToDelete = nil
            UIAccessibility.post(notification: .announcement, argument: "会话已删除")
        } catch {
            errorMessage = "删除会话失败: \(error.localizedDescription)"
            showErrorMessageAlert = true
        }
    }
    
    /// 执行清空全部会话
    private func executeClearAllSessions() {
        do {
            try storageManager.clearAllSessions()
            refreshSessions()
            UIAccessibility.post(notification: .announcement, argument: "全部历史会话已清空")
        } catch {
            errorMessage = "清空会话失败: \(error.localizedDescription)"
            showErrorMessageAlert = true
        }
    }
    
    // MARK: - 辅助格式化方法
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
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
