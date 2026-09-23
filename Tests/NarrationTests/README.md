# 场景描述线验证脚本

当前以独立脚本形式运行，尚未接入 XCTest 目标（待 `project.yml` 增加测试 target 后迁移）。

运行方式（在仓库根目录）：

```bash
cat WalkMate/Models/NarrationModels.swift \
    WalkMate/Core/Narration/SubtitleComposer.swift \
    Tests/NarrationTests/SubtitleComposerChecks.swift > /tmp/check.swift && swift /tmp/check.swift
```

覆盖用例：短句时长钳制、标点切分、乱序输入、时间重叠消解、越界裁剪、
空输入、超长句均衡切分、孤儿片段吸收、真实模型输出的字幕条数控制。

## 其他脚本

| 脚本 | 拼接的源文件 |
|---|---|
| `NarrationClampChecks.swift` | `Core/Utils/Log.swift`、`Models/NarrationModels.swift`、`Models/ConversationModels.swift`、`Core/Narration/SceneNarrator.swift`、`Core/Narration/QwenSceneNarrator.swift` |
| `CompanionConversationChecks.swift` | `Models/ConversationModels.swift`、`Core/Conversation/CompanionConversation.swift` |
| `StandstillDetectorChecks.swift` | `Core/Conversation/StandstillDetector.swift` |
