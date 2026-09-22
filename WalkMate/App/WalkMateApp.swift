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
            ContentView()
        }
    }
}
