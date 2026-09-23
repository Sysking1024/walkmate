# 伴行 WalkMate

面向后天失明人群的渐进式独立出行康复训练应用。Insta360 X5 全景相机当眼睛，手机端做避障、场景描述与对谈，训练结束自动剪出带语音与字幕的集锦，分享到康复社群。

影石 Insta360 黑客松参赛作品，2026 年 9 月，南京。

## 功能

- **渐进式训练**：室内适应 → 半开放环境（小区路线）→ 户外独立出行，按训练记录解锁
- **避障**：影石开源 DAP 全景深度估计（Core ML 端侧推理）→ 前向扇区障碍与可通行路线 → 3D 空间音频提示
- **AI 伙伴**：驻足 5 秒或说「walkmate」唤起，通义千问 Qwen3-VL 看图描述周围，Qwen3-TTS 朗读，可口头追问
- **集锦**：对谈期间录下拼接后的全景预览，训练结束按时刻剪成竖屏短片（字幕、配音、配乐）
- **社群**：好友成就、无障碍探店（评分、路线、高德步行导航、邀请好友）、大家的旅程
- **无障碍**：VoiceOver 全覆盖、大触控目标、动态字号、徽章专属旋律

## 仓库结构

```
WalkMate/               iOS 应用（SwiftUI，iOS 17+）
  App/                  入口与相机主视图（队友的出行页）
  Core/Camera           Insta360 SDK 连接、推流、帧总线
  Core/Inference        DAP 深度估计
  Core/Perception       空间感知（障碍、路线）
  Core/Audio            空间音频与程序化提示音
  Core/Collector        感知数据采集与离线回放
  Core/Narration        场景描述（Qwen3-VL）、语音合成、字幕
  Core/Conversation     驻足检测、对谈状态机、语音指令
  Core/Recording        预览录制、短片合成、集锦生成
  Core/Community        店铺评分、社群动态
  Core/Training         训练记录与档位解锁
  Core/Backend          后端客户端（离线优先）
  Core/Settings         偏好、无障碍反馈
  Core/Badges           徽章旋律
  Features/             各页面（首页、训练、社群、个人、路线、成长）
  Resources/            设计资源、演示视频、徽章音频、Secrets.plist
backend/                Python 标准库 + SQLite 的社群后端
Tests/                  各模块单元测试；NarrationTests 为脚本化检查
specs/                  各特性的需求、方案与任务拆解
```

## 评委安装指南（打包版）

打包提交的压缩包里已经带好下面这些不入库的文件，解压后直接按「真机运行」操作即可：

- `WalkMate/Frameworks/`：Insta360 iOS SDK（v1.10.4）
- `WalkMate/Resources/Secrets.plist`：百炼凭据与后端地址
- `WalkMate/Resources/Models/dap_256x512_int8.mlpackage`：深度估计模型

需要的外部条件：一台 Insta360 X5（手机连它的 Wi-Fi 热点）、手机有蜂窝网络（场景描述、语音识别、社群同步走网络）、iOS 17 以上的 iPhone。没有相机也能体验除训练画面之外的全部功能，社群数据在后端不可达时自动用内置数据。

## 环境准备

1. **Xcode**：Xcode 27 beta，真机运行（Insta360 SDK 没有模拟器切片）
2. **Insta360 SDK**：把 SDK 的 `Frameworks` 目录链接到 `WalkMate/Frameworks`（已在 `.gitignore` 里）
   ```bash
   ln -s /path/to/iOS_v1.10.4/INSCameraSDKSample-bluetooth/Frameworks WalkMate/Frameworks
   ```
3. **密钥**：复制 `WalkMate/Resources/Secrets.example.plist` 为 `Secrets.plist`，填入
   - `QwenAPIKey`、`QwenBaseURL`、`QwenDashScopeURL`：阿里云百炼凭据
   - `BackendBaseURL`：社群后端地址（本机调试用局域网 IP）
4. **深度模型**：`dap_256x512_int8.mlpackage` 放到 `WalkMate/Resources/Models/`（不入库，找队友要）
5. **生成工程**：
   ```bash
   cd WalkMate && xcodegen generate
   ```

## 真机运行

用 Xcode 打开 `WalkMate/WalkMate.xcodeproj`，选真机运行。用自己的开发者账号时在命令行覆盖签名，不改 `project.yml`：

```bash
xcodebuild -project WalkMate/WalkMate.xcodeproj -scheme WalkMate \
  -destination "id=<设备 UDID>" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<团队 ID> PRODUCT_BUNDLE_IDENTIFIER=<自己的 Bundle ID> build
```

手机先连相机 Wi-Fi 热点，再在训练页点「连接相机」。场景描述与语音识别走蜂窝网络。

## 后端

```bash
python3 backend/server.py --port 8080 --db backend/walkmate.db
```

零依赖，首次启动自动建表并写入种子数据。接口见 `backend/README.md`。iOS 端离线优先：本地先生效，后端可达时补发。

## 测试

```bash
# Xcode 单元测试（相机、感知、音频、回放等）
xcodebuild test -project WalkMate/WalkMate.xcodeproj -scheme WalkMate -destination "id=<设备 UDID>"

# 描述与对谈的脚本化检查（无需工程）
cat WalkMate/Core/Conversation/VoiceIntent.swift Tests/NarrationTests/VoiceIntentChecks.swift | xcrun swift -
```

## 训练中的语音指令

| 说什么 | 效果 |
|---|---|
| walkmate，说说周围 | 立刻描述周围 |
| walkmate，左手边是什么 | 先描述，再回答这个问题 |
| 好 / 不用（伙伴问「要我说说这儿吗」时） | 答应 / 拒绝 |
| 任何问题（描述完 15 秒内） | 追问 |
| 够了 / 停 | 结束这轮 |

## 约定

- 注释、日志、提交信息用中文；日志走 `Log.info(_:category:)`，不用 `print`
- 触控目标不小于 48 点；卡片合并为一个读屏元素
- 密钥只放 `Secrets.plist`，不入库
