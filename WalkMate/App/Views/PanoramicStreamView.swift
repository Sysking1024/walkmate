//
//  PanoramicStreamView.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-22.
//

import SwiftUI
import UIKit

/// 将底层相机播放器视图 (UIView) 桥接至 SwiftUI 的包装视图
public struct CameraPreviewRepresentable: UIViewRepresentable {
    public let previewView: UIView?
    
    public init(previewView: UIView?) {
        self.previewView = previewView
    }
    
    public func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        if let preview = previewView {
            preview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(preview)
            NSLayoutConstraint.activate([
                preview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                preview.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                preview.topAnchor.constraint(equalTo: container.topAnchor),
                preview.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }
        return container
    }
    
    public func updateUIView(_ uiView: UIView, context: Context) {
        // 若容器内尚未挂载 previewView 则进行挂载
        if let preview = previewView, !uiView.subviews.contains(preview) {
            uiView.subviews.forEach { $0.removeFromSuperview() }
            preview.translatesAutoresizingMaskIntoConstraints = false
            uiView.addSubview(preview)
            NSLayoutConstraint.activate([
                preview.leadingAnchor.constraint(equalTo: uiView.leadingAnchor),
                preview.trailingAnchor.constraint(equalTo: uiView.trailingAnchor),
                preview.topAnchor.constraint(equalTo: uiView.topAnchor),
                preview.bottomAnchor.constraint(equalTo: uiView.bottomAnchor)
            ])
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
            
            if isConnected, previewView != nil {
                CameraPreviewRepresentable(previewView: previewView)
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
