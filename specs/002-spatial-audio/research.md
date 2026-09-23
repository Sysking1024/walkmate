# 技术调研报告：002-spatial-audio 空间音频播放器

**特性分支**：`002-spatial-audio`  
**创建日期**：2026-09-23  
**状态**：已完成 (Completed)

---

## 调研决策 1：iOS 原生 3D 音频图架构选型

### 决策结果
采用 iOS 原生 `AVAudioEngine` 配合 `AVAudioEnvironmentNode` 的 HRTF（头部相关传输函数）双耳立体声渲染架构，完全不引入任何第三方音频库。

### 决策依据与原理
1. **原生系统级支持与超低延迟**：
   - `AVAudioEngine` 是苹果官方推荐的底层模块化音频图系统，直接对接 CoreAudio，调度开销在亚毫秒级（< 1ms）。
   - `AVAudioEnvironmentNode` 原生内置硬件级 3D 混音算法，仅需设置 `renderingAlgorithm = .HRTFHQ`，即可对任意普通立体声耳机（有线、蓝牙、AirPods）呈现真实的三维空间定位（区分左、右、前、后、上、下与纵深距离）。
2. **三维声源与听者配置**：
   - 视障使用者位于声场原点：`listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)`，初始朝向为正前向（-Z 轴）。
   - 挂载独立的 `AVAudioPlayerNode`：
     - 障碍物节点（`obstacleNode`）：负责播放金属撞击警示音，动态绑定障碍物空间三维坐标；
     - 导航导向节点（`navigationNode`）：负责播放自然步速脚步声，动态绑定安全航路点空间三维坐标；
     - 康复激励节点（`rewardNode`）：负责播放上行和弦激励音，置于声场正中立体声开阔呈现。

### 被否决的备选方案
- **备选方案 A：第三方游戏音频引擎（FMOD / Wwise / OpenAL）**：
  - 否决原因：包体积大（增加数十 MB），集成复杂度高，引入外部 C/C++ 动态库与黑客松极速交付理念背道而驰。
- **备选方案 B：简单双声道左右声道 Pan 衰减**：
  - 否决原因：普通立体声 Pan 只能区分“左右”，完全无法区分“前方”与“后方”，更无法表达“高度”和“逼近纵深”，不能满足视障盲行的空间定位需求。

---

## 调研决策 2：纯代码参数化音频合成（Procedural Audio Synthesis）

### 决策结果
全套音效（金属撞击音、脚步踏地音、康复激励和弦音）在应用启动时，由纯数学 DSP 算法在内存中直接生成为标准的 `AVAudioPCMBuffer`（44.1kHz, 单声道 Float32），零外部音频素材文件。

### 各音效物理声学建模参数
1. **金属撞击警示音（Metallic Impact）**：
   - 采样时长：0.1 秒（4410 个采样点，内存占用约 17 KB）。
   - 物理构成：
     - 前 3ms 施加汉宁窗加权的白噪声突发冲击（White Noise Burst），模拟硬物接触金属表面的瞬时碰撞；
     - 叠加 4 组非谐波金属共鸣正弦波（基频 $f_0 = 800\text{Hz}$，配合 $1130\text{Hz}, 1720\text{Hz}, 2800\text{Hz}$）；
     - 各分量乘以快速指数衰减包络 $e^{-t / 0.045}$。
   - 听感：清脆、干脆、坚硬的金属碰击声（“当”）。
2. **自然步速脚步音（Footstep）**：
   - 采样时长：0.08 秒（3528 个采样点，内存占用约 14 KB）。
   - 物理构成：
     - 触地低频冲击层（Heel Impact）：起始 120Hz 迅速滑落至 70Hz 的阻尼低频正弦波，包络衰减 $e^{-t / 0.02}$；
     - 表面碎擦层（Friction Texture）：经过 1.5kHz ~ 3kHz 带通滤波的微弱噪声，包络衰减 $e^{-t / 0.03}$。
   - 听感：真实自然的鞋底轻踏硬地面声（“嗒”）。
3. **康复达标激励和弦音（Reward Chime）**：
   - 采样时长：0.4 秒（17640 个采样点，内存占用约 69 KB）。
   - 物理构成：
     - 温暖上行大三和弦琶音：C5 (523.25Hz) $\to$ E5 (659.25Hz) $\to$ G5 (783.99Hz) $\to$ C6 (1046.50Hz)；
     - 4 个音符依次错开 30ms 触发，每个音符叠加八音盒微弱二次谐波并平滑指数衰减。
   - 听感：温润、明亮、开阔、充满成就感的高亮上行和弦（“叮-铃-啷~”）。

### 性能与安全评估
- 内存开销：三个音效合计仅约 **100 KB**。
- 计算耗时：纯 Swift 循环浮点运算，生成全部三个音效耗时 **< 0.5 毫秒**。
- 零依赖优势：杜绝了工程中找不到 `.wav` 文件的崩溃风险。

---

## 调研决策 3：项目现有资产与算法复用矩阵 (Zero-Duplication Inventory)

明确梳理现有模块，坚决避免重复造轮子：

1. **现有算法与资产（100% 完全复用，无需做任何代码修改）**：
   - **`WalkMate/Core/Toolkits/SpatialAudioKit.swift`**：
     - 已经完整实现了 `toSpatialAudioRenderParams(position:boundingSize:)` 方法，直接将相对三维坐标 $(x, y, z)$ 转换为 `AVAudio3DPoint`、距离衰减系数及扩展角；
     - 已经完整实现了 `toStereoFallbackParams` 与 `toClockDirection`；
     - **规划结论**：新音频播放器直接调用 `SpatialAudioKit` 的既有算法，禁止重写坐标转换逻辑。
   - **`WalkMate/Core/Perception/ObstacleDetector.swift`**：
     - 已输出包含真实空间坐标 `position` 的 `ObstacleItem`，无需修改。
   - **`WalkMate/Core/Perception/PassageRoutePlanner.swift`**：
     - 已输出包含有序航路点 `waypoints` 的 `PassableRouteData`，无需修改。
   - **`WalkMate/Core/Engine/SpatialPerceptionEngine.swift`**：
     - 全链路感知总成，已提供异步流与代理分发，无需修改。

2. **新规划创建的模块（增量极简实现）**：
   - **`WalkMate/Core/Audio/ProceduralAudioSynthesizer.swift`**：
     - 纯数学音频合成器工具类，无状态纯函数生成金属、脚步、奖励和弦三种标准 PCM Buffer。
   - **`WalkMate/Core/Audio/SpatialAudioPlayer.swift`**：
     - 空间音频播放服务单例，管理 `AVAudioEngine` 生命周期、双音确认避障逻辑、步频导航调度与康复奖励音触发。
   - **`Tests/AudioTests/`**：
     - 空间音频播放器与合成器的单元测试套件，在无物理声卡的测试环境下验证坐标映射、状态机流转与防重入机制。
