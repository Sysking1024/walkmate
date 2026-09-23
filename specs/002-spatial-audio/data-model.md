# 数据模型与实体规约：002-spatial-audio 空间音频播放器

**特性分支**：`002-spatial-audio`  
**创建日期**：2026-09-23  
**状态**：已完成 (Completed)

---

## 一、实体定义

### 1. SpatialAudioTarget（声源空间目标）
表示当前在三维空间中被激活并追踪的发声声源目标状态。

- **字段说明**：
  - `position: SIMD3<Float>`：三维物理相对坐标（米），严格遵循 iOS 空间音频右手坐标系（+X 为右, -X 为左, +Y 为上, -Z 为前向, +Z 为后方）；
  - `audio3DPoint: AVAudio3DPoint`：通过复用 `SpatialAudioKit` 直接映射后的原生音频坐标（X: position.x, Y: position.y, Z: position.z）；
  - `distance: Float`：目标距使用者的直线物理距离（米）；
  - `updatedAt: TimeInterval`：最近一次更新的时间戳（毫秒）；
  - `isActive: Bool`：当前目标是否处于发声激活状态。
- **生命周期与状态转移**：
  - `nil` $\to$ 有效坐标：激活声源，更新 `AVAudioPlayerNode.position`，启动发声；
  - 坐标更新：平滑滑动声源空间位置，不中断当前播放周期；
  - 有效坐标 $\to$ `nil`：停止发声，释放发声通道。

---

### 2. SynthesizedSoundType（纯代码合成音效类型枚举）
表示系统通过数学算法合成的不同语义音效。

- **枚举项**：
  - `metallicImpact`：金属敲击声（避障警示专用）；
    - 采样率：44,100 Hz，单声道 Float32；
    - 采样长度：4,410 个点（0.1 秒）；
    - 物理参数：基频 800Hz，3组非谐波共鸣，快速指数衰减。
  - `footstep`：轻快踏地声（路径导引专用）；
    - 采样率：44,100 Hz，单声道 Float32；
    - 采样长度：3,528 个点（0.08 秒）；
    - 物理参数：120Hz 下降滑频冲击波，叠加轻微带通摩擦噪声。
  - `rewardChime`：上行和弦音（康复达标激励专用）；
    - 采样率：44,100 Hz，单声道 Float32；
    - 采样长度：17,640 个点（0.4 秒）；
    - 物理参数：C5-E5-G5-C6 错开 30ms 的琶音叠加，八音盒共鸣包络。

---

### 3. ObstacleAlertState（障碍物双音发声状态机实体）
管理“固定 800ms 播放 2 次后自动静音”的原子状态，防止高频重复调用打断或爆音。

- **状态枚举（AlertPhase）**：
  - `idle`：空闲状态，未发声；
  - `firstPing`：正在播放第 1 声金属撞击音；
  - `waitingInterval`：等待 800ms 间隔；
  - `secondPing`：正在播放第 2 声金属撞击音；
  - `completed`：双响播放结束，静音等待业务层下一轮触发。
- **防重入约束**：
  - 在 `firstPing`、`waitingInterval` 或 `secondPing` 期间再次调用 `setObstacleTarget`，状态机不重置计时，仅实时更新三维声源坐标（平滑声源移动）。

---

## 二、复用现有实体与数据流向

本特性直接使用并消费项目中已有的数据结构，杜绝数据冗余：

1. **`SIMD3<Float>`**（标准向量类型）：直接作为 `setObstacleTarget` 与 `setNavigationTarget` 的入参类型。
2. **`AVAudio3DPoint`**（原生音频结构）：由 `SpatialAudioKit` 的既有算法负责转换。
3. **`ObstacleItem.position`**：由业务层直接从现有障碍物对象中提取，无需播放器介入。
4. **`RouteWaypoint.position`**：由业务层直接从现有导航航路点中提取，无需播放器介入。
