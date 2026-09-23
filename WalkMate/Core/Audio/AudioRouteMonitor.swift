import AVFoundation
import Foundation
import Observation

/// 避障提示的方式
enum ObstacleAlertMode: String, CaseIterable {
    /// 戴耳机用空间音频，外放用语音
    case auto
    /// 始终用空间音频（金属双音、领路脚步声）
    case headphones
    /// 始终用语音播报方位与距离
    case speaker

    var title: String {
        switch self {
        case .auto: return "自动"
        case .headphones: return "耳机空间音频"
        case .speaker: return "外放语音"
        }
    }

    /// 实际生效的方式
    enum Resolved { case headphones, speaker }
}

/// 监听音频输出线路，判断当前是不是戴着耳机
@MainActor
@Observable
final class AudioRouteMonitor {

    static let shared = AudioRouteMonitor()

    private(set) var hasHeadphones = false

    private init() {
        refresh()
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        let headphonePorts: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP]
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let detected = outputs.contains { headphonePorts.contains($0.portType) }
        if detected != hasHeadphones {
            hasHeadphones = detected
            Log.info("音频输出线路变化：\(detected ? "耳机" : "外放")（\(outputs.map(\.portName).joined(separator: ","))）", category: .audio)
        }
    }

    /// 按设置与当前线路决定用哪种提示
    func resolve(_ mode: ObstacleAlertMode) -> ObstacleAlertMode.Resolved {
        switch mode {
        case .headphones: return .headphones
        case .speaker: return .speaker
        case .auto: return hasHeadphones ? .headphones : .speaker
        }
    }
}
