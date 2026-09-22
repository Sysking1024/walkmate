//
//  SensorTelemetryCard.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-22.
//

import SwiftUI

/// 六轴传感器遥测数据 HUD 卡片视图
/// 严格遵循宪章原则四（绝对无障碍适配）及 4.c 项合并与阻断规则：
/// 1. 将整张卡片封装为独立语义容器 `.accessibilityElement(children: .combine)`；
/// 2. 使用中文逗号平铺拼接所有度量文本，彻底杜绝读屏焦点碎片化与高频聚焦噪点；
/// 3. 前景色与卡片深色背景对比度严格大于 4.5:1；
/// 4. 仅供被动读屏轻击聚焦查询，严禁向 VoiceOver 发送任何高频主动通知扰民。
public struct SensorTelemetryCard: View {
    public let telemetry: SensorTelemetry
    
    public init(telemetry: SensorTelemetry) {
        self.telemetry = telemetry
    }
    
    // 合并后的平铺中文朗读文本
    private var combinedAccessibilityLabel: String {
        "传感器遥测面板，连接状态：\(telemetry.connectionState.rawValue)，实时推流帧率：\(String(format: "%.1f", telemetry.fps))帧每秒，姿态角：俯仰\(String(format: "%.1f", telemetry.pitch))度，翻滚\(String(format: "%.1f", telemetry.roll))度，偏航\(String(format: "%.1f", telemetry.yaw))度，线性加速度：X轴\(String(format: "%.2f", telemetry.acceleration.x))，Y轴\(String(format: "%.2f", telemetry.acceleration.y))，Z轴\(String(format: "%.2f", telemetry.acceleration.z))米每二次方秒。"
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("遥测监控", systemImage: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text(telemetry.connectionState.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .clipShape(Capsule())
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // 实时指标展示格
            VStack(spacing: 8) {
                HStack {
                    Text("推流帧率:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(white: 0.85)) // 对比度 > 4.5:1
                    Spacer()
                    Text(String(format: "%.1f FPS", telemetry.fps))
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                
                HStack {
                    Text("姿态角 (P / R / Y):")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(white: 0.85))
                    Spacer()
                    Text(String(format: "%.1f° / %.1f° / %.1f°", telemetry.pitch, telemetry.roll, telemetry.yaw))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }
                
                HStack {
                    Text("线性加速度:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(white: 0.85))
                    Spacer()
                    Text(String(format: "(%.2f, %.2f, %.2f) m/s²", telemetry.acceleration.x, telemetry.acceleration.y, telemetry.acceleration.z))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(16)
        .background(Color(red: 0.12, green: 0.13, blue: 0.15)) // 深灰背景，对比度坚实保真
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        // 核心无障碍边界阻断与平铺朗读配置
        .accessibilityElement(children: .combine)
        .accessibilityLabel(combinedAccessibilityLabel)
        .accessibilityHint("双击可重新检查当前相机姿态与推流度量")
    }
    
    // 状态标签配色
    private var statusColor: Color {
        switch telemetry.connectionState {
        case .connected:
            return Color.green
        case .connecting:
            return Color.orange
        case .failed:
            return Color.red
        case .noConnection:
            return Color.gray
        }
    }
}
