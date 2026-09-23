# 快速验证指南：002-spatial-audio 空间音频播放器

**特性分支**：`002-spatial-audio`  
**验证目标**：验证空间音频播放器的纯代码音频合成、金属双响避障警示、自然步速脚步领路及康复和弦激励端到端正确性。

---

## 一、前置条件与依赖准备

1. **宿主环境**：macOS 运行 Xcode 16+ 与 iOS 18 模拟器（推荐 iPhone 16 模拟器 `5FFE06CA-CD1E-4B1A-9410-8C95BE0071ED`）或真实物理 iPhone。
2. **真机体验建议**：若在真机运行，佩戴普通立体声双耳耳机或 AirPods 可直接感知清晰的三维方向（左前方、右前方、纵深距离）。
3. **零外部素材依赖**：无需下载或导入任何音频资源文件，纯代码即可自给自足完成合成与播放。

---

## 二、自动化单元测试套件验证

运行针对空间音频播放器与合成器的专用单元测试：

```bash
xcodebuild test \
  -project WalkMate/WalkMate.xcodeproj \
  -scheme WalkMate \
  -only-testing:AudioTests \
  -destination 'platform=iOS Simulator,id=5FFE06CA-CD1E-4B1A-9410-8C95BE0071ED'
```

### 预期验证点与测试用例说明
1. **`testProceduralAudioSynthesizerBufferGeneration`**：
   - 验证金属音（4410采样点）、脚步音（3528采样点）、奖励和弦（17640采样点）内存 PCM 缓存正确生成；
   - 验证音频振幅范围均严格在 $[-1.0, 1.0]$ 内，无溢出与静音坏帧。
2. **`testObstacleDoublePingCadenceAndState`**：
   - 验证调用 `setObstacleTarget` 传入左侧坐标时，声源节点三维位置严格映射；
   - 验证状态机在 800ms 间隔播放第 2 声后自动转入 completed 完成态并静音；
   - 验证在播放期间重复调用不会发生打断重入或报错。
3. **`testNavigationFootstepCadence`**：
   - 验证设置导航目标后，步频定时器以约 1.1 秒的周期稳定调度脚步声节点；
   - 验证传入 `nil` 时定时器安全取消并静音。
4. **`testRewardSoundOneShotAndDuck`**：
   - 验证调用 `playRewardSound` 成功调度和弦节点发声；
   - 验证播放期间脚步声节点音量平滑压低以突出奖励和弦。

---

## 三、代码集成验证示例（Smoke Test）

在应用的 ViewController 或业务服务中直接调用验证：

```swift
import WalkMate

// 1. 获取单例并启动硬件引擎
let player = SpatialAudioPlayer.shared
try player.start()

// 2. 模拟左前方 1.5 米处检出危险障碍物 (触发 800ms 金属撞击双音)
player.setObstacleTarget(position: SIMD3<Float>(-1.0, 0.0, -1.5))

// 3. 模拟正前方 3.0 米处可行路径导引 (以 1.1 秒步频持续传出领路脚步声)
player.setNavigationTarget(position: SIMD3<Float>(0.0, -1.4, -3.0))

// 4. 模拟视障者成功避障或走完 10 米里程碑 (触发一次暖心上行大三和弦)
player.playRewardSound()

// 5. 危险解除与任务完成
player.setObstacleTarget(position: nil)
player.setNavigationTarget(position: nil)
player.stop()
```
