import SwiftUI
import UIKit

/// 训练页的高分辨率全景预览宿主。
///
/// 相机 SDK 只把拼接结果画到预览视图里，集锦就是从这个视图录下来的；视图有多大，成片就有多清楚。
/// 屏幕上那条 2:1 的全景只有几百像素宽，剪成竖屏再放大会糊。这里把预览视图按 4 倍尺寸布局，
/// 再用缩放变换缩回屏幕大小显示：SDK 按大尺寸渲染，录制读到的是大图，肉眼看到的还是原来的卡片。
struct PanoramaPreviewHost: UIViewRepresentable {
    let previewView: UIView
    /// 渲染尺寸相对显示尺寸的倍数
    static let renderScale: CGFloat = 4

    func makeUIView(context: Context) -> HostView {
        let host = HostView()
        host.backgroundColor = .black
        host.clipsToBounds = true
        host.attach(previewView)
        return host
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        if uiView.preview !== previewView { uiView.attach(previewView) }
    }

    final class HostView: UIView {
        private(set) weak var preview: UIView?

        func attach(_ view: UIView) {
            preview?.removeFromSuperview()
            preview = view
            view.autoresizingMask = []
            addSubview(view)
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let preview, bounds.width > 0, bounds.height > 0 else { return }
            let scale = PanoramaPreviewHost.renderScale
            // 先按大尺寸布局，再整体缩小；transform 不影响它自己坐标系里的 bounds，录制按 bounds 截图
            preview.transform = .identity
            preview.bounds = CGRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale)
            preview.center = CGPoint(x: bounds.midX, y: bounds.midY)
            preview.transform = CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)
        }
    }
}
