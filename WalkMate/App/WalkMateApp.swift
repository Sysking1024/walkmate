import SwiftUI

/// 伴行 WalkMate 应用程序入口。
///
/// 当前根视图为场景描述与记录功能（Narration 线）。
/// 相机连接与空间感知界面（ContentView，任务 T016）完成后，在此处并入主导航。
@main
struct WalkMateApp: App {

    init() {
        Log.info(.ui, "应用启动完成")
    }

    var body: some Scene {
        WindowGroup {
            NarrationHomeView()
        }
    }
}
