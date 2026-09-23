//
//  PanoramicStreamView.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-22.
//

import SwiftUI
import UIKit

/// 容器视图：确保 renderView 在 layoutSubviews 时 frame 严格与容器尺寸同步（对齐官方 SDK Demo）
public final class PreviewContainerView: UIView {
    private weak var currentPreview: UIView?
    
    public func setPreviewView(_ preview: UIView) {
        if currentPreview != preview {
            currentPreview?.removeFromSuperview()
            currentPreview = preview
            preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            preview.frame = bounds
            addSubview(preview)
        }
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        currentPreview?.frame = bounds
    }
}

/// 将底层相机播放器视图 (UIView) 桥接至 SwiftUI 的包装视图
public struct CameraPreviewRepresentable: UIViewRepresentable {
    public let previewView: UIView?
    
    public init(previewView: UIView?) {
        self.previewView = previewView
    }
    
    public func makeUIView(context: Context) -> PreviewContainerView {
        let container = PreviewContainerView()
        container.backgroundColor = .black
        if let preview = previewView {
            container.setPreviewView(preview)
        }
        return container
    }
    
    public func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        if let preview = previewView {
            uiView.setPreviewView(preview)
        }
    }
}

/// 全景视频流实时渲染视图
public struct PanoramicStreamView: View {
    public let previewView: UIView?
    public let isConnected: Bool
    
    public init(previewView: UIView?, isConnected: Bool) {
        self.previewView = previewView
        self.isConnected = isConnected
    }
    
    public var body: some View {
        ZStack {
            Color.black
            
            if isConnected, let preview = previewView {
                CameraPreviewRepresentable(previewView: preview)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.gray)
                    Text("相机未连接或未开启推流")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(2.0, contentMode: .fit) // 1080P/全景 2:1 标准画幅
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isConnected ? "全景实时画面监控区域，画面推流正常" : "全景画面监控区域，当前未连接")
    }
}
