//
//  WalkMateApp.swift
//  WalkMate
//
//  Created by Antigravity on 2026-09-22.
//

import SwiftUI

/// WalkMate 应用程序主入口
@main
struct WalkMateApp: App {
    
    init() {
        Log.info("WalkMate 应用程序启动初始化完成", category: .general)
    }
    
    var body: some Scene {
        WindowGroup {
            // 临时导航：出行（相机与空间感知）为首屏，训练记录（场景描述与短片）为第二页。
            // 待 UI 设计稿确定整体导航结构后替换。
            TabView {
                ContentView()
                    .tabItem { Label("出行", systemImage: "figure.walk") }
                NarrationHomeView()
                    .tabItem { Label("训练记录", systemImage: "list.bullet.rectangle") }
            }
        }
    }
}
