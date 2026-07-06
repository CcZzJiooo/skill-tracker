# Skill Tracker 全平台传播文案

项目链接统一使用：

`https://github.com/CcZzJiooo/skill-tracker`

Release 下载页：

`https://github.com/CcZzJiooo/skill-tracker/releases`

## CSDN

配图：`docs/promotion/assets/csdn-cover.png`

标题：

```text
开源一个本地 AI Agent skill 调用可视化工具：Skill Tracker
```

摘要：

```text
Skill Tracker 可以扫描本机 AI 编程工具会话日志，把 Codex、Claude Code、Cursor、Windsurf 等工具调用过的 SKILL.md 可视化出来，并提供中文技能字典、重复 skill 治理、GitHub 雷达和可导出行动方案。
```

正文：

```markdown
最近我在整理 AI 编程工具里的 skills / plugins / prompts，发现一个问题：工具越来越会自动调用能力，但用户其实很难知道它到底调用了什么。

所以我做了一个本地优先的小工具：Skill Tracker。

它做的事情很直接：

- 扫描本机 AI coding-agent 的会话日志
- 识别哪些 `SKILL.md` 被调用
- 生成一个静态 dashboard
- 展示技能热度、调用日志、工具矩阵和治理风险
- 给每个 skill 维护中文功能说明
- 检测重复/重叠 skills，并导出治理行动方案
- 内置 GitHub 雷达，可以按中文意图搜索相关开源项目

项目不需要后端，也不上传日志。普通用户下载 Release ZIP 后解压，双击 `run.bat` 就可以打开；开发者也可以直接 clone 后运行。

GitHub:

https://github.com/CcZzJiooo/skill-tracker

适合这些场景：

- 你装了很多 AI agent skills，但不知道哪些真的在用
- 你想把英文 skill 说明整理成中文
- 你怀疑本地有重复 skills，想做清理
- 你想比较 Codex / Claude Code / Cursor / Windsurf 等工具的 skill 使用差异
- 你想把本地治理结果导出为 GitHub issue 草稿

目前支持 Windows，本地静态 dashboard，MIT License。

欢迎试用、提 issue、提 PR。
```

标签：

```text
AI Agent, Codex, Claude Code, Cursor, 开源项目, 可视化, 本地工具, GitHub
```

## 掘金

配图：`docs/promotion/assets/juejin-cover.png`

标题：

```text
我做了一个 AI 编程技能调用可视化工具：Skill Tracker
```

正文：

```markdown
现在很多 AI 编程工具都开始支持 skills / plugins / prompts，但有一个很现实的问题：

> 它到底调用了哪些 skill？哪些重复？哪些说明缺失？这些能力有没有被真正用起来？

我做了一个本地优先的开源工具：Skill Tracker。

它会扫描本机 AI coding-agent 的日志，把隐藏在会话里的 `SKILL.md` 调用可视化出来。

核心功能：

- skill 调用统计和调用日志
- 中文 skill 字典
- 中文自然语言意图搜索
- 重复 skill 检测
- skill x 工具矩阵
- 治理行动方案导出
- GitHub 雷达：按关键词或中文需求找相关开源项目

它不是云服务，不需要账号，不上传日志。采集脚本跑完后会生成本地 dashboard，直接浏览器打开。

项目地址：

https://github.com/CcZzJiooo/skill-tracker

如果你也在折腾 Codex / Claude Code / Cursor / Windsurf / Antigravity / Gemini CLI 这一类工具，欢迎试试。
```

标签：

```text
AI, Agent, 开源, 前端, 效率工具, Codex, Claude Code
```

## OSCHINA

配图：`docs/promotion/assets/oschina-cover.png`

标题：

```text
Skill Tracker：本地优先的 AI Agent skills observability 工具
```

正文：

```markdown
Skill Tracker 是一个开源的本地 AI Agent skill 调用观测工具。

它扫描本机 AI 编程工具会话日志，检测 `SKILL.md` 使用情况，并生成静态 dashboard，用于查看：

- 哪些 skill 被调用
- 哪些工具调用最多
- 哪些 skill 缺少中文说明
- 哪些 skill 功能重叠
- 哪些治理项需要处理
- 哪些相关开源项目可以参考

目前覆盖方向：

- Codex
- Claude Code
- Cursor
- Windsurf
- Antigravity
- Continue
- Gemini CLI

项目特点：

- local-first，无服务端
- Windows portable ZIP
- MIT License
- 中文技能字典
- 重复 skill 治理
- 匿名报告导出

GitHub:

https://github.com/CcZzJiooo/skill-tracker

欢迎开源社区试用、反馈和贡献。
```

标签：

```text
开源软件, AI Agent, Codex, Claude Code, 本地优先, 可视化
```

## 知乎

配图：`docs/promotion/assets/zhihu-cover.png`

标题：

```text
为什么 AI 编程工具需要“skill 可观测性”？我做了一个开源小工具
```

正文：

```markdown
我最近在整理自己的 AI 编程环境时发现一个问题：

AI 工具越来越像一个会自动调度能力的系统，但用户对这些能力的实际使用情况几乎没有感知。

比如：

- 它到底调用了哪些 skill？
- 同一个任务是不是反复调用了重复能力？
- 本地装的一堆 skill 哪些从来没用过？
- 英文说明太多，中文用户怎么快速理解？
- 不同工具之间，比如 Codex / Claude Code / Cursor，调用偏好有什么差异？

为了解决这个问题，我做了一个本地优先的开源工具：Skill Tracker。

它扫描本机 AI coding-agent 会话日志，把 `SKILL.md` 调用可视化成 dashboard。你可以看到 skill 热度、调用日志、中文说明覆盖率、重复风险、工具矩阵，还可以导出治理计划。

它不是云平台，不上传日志，也不需要注册账号。普通用户下载 ZIP 后双击 `run.bat` 就能打开。

项目地址：

https://github.com/CcZzJiooo/skill-tracker

我觉得“AI Agent 可观测性”以后会变得越来越重要。模型能力本身是一层，工具调用、技能调用、上下文治理又是另一层。Skill Tracker 目前做的是一个很轻量的本地版本，希望能给同样折腾 AI 编程工作流的人一点帮助。
```

标签：

```text
人工智能, AI 编程, 开源项目, Cursor, Claude Code, Codex
```

## V2EX

配图：`docs/promotion/assets/v2ex-cover.png`

节点建议：

```text
share / programming / ai
```

标题：

```text
分享一个本地 AI skills 调用可视化工具：Skill Tracker
```

正文：

```markdown
最近在整理自己本地的 AI coding-agent skills，做了一个小工具：Skill Tracker。

它扫描本机日志，识别 `SKILL.md` 调用，然后生成静态 dashboard。主要看这些东西：

- 哪些 skill 被调用
- 调用次数和去重次数
- 每个 skill 的中文说明
- 重复/重叠 skill
- 不同工具的 skill 使用矩阵
- GitHub 上相关开源项目

项目不需要服务端，也不上传日志。Windows 下可以下载 Release ZIP 后双击 `run.bat`。

GitHub:
https://github.com/CcZzJiooo/skill-tracker

目前主要是给 Codex / Claude Code / Cursor / Windsurf 这类工具用户用的。欢迎提建议。
```

## SegmentFault

配图：`docs/promotion/assets/segmentfault-cover.png`

标题：

```text
从日志到治理：用 Skill Tracker 可视化 AI Agent skill 调用
```

正文：

```markdown
AI 编程工具的能力调用正在变复杂，但日志里的 skill 调用通常不可见。

Skill Tracker 提供了一个本地优先的处理链路：

1. 扫描本机 AI coding-agent 日志
2. 识别 `SKILL.md` 调用
3. 去重统计调用量
4. 维护中文 skill 字典
5. 检测重复和重叠能力
6. 生成治理行动方案
7. 导出匿名报告或 GitHub issue 草稿

这个项目的重点不是“再做一个聊天工具”，而是做 AI Agent workflow 的可观测性和治理。

GitHub:

https://github.com/CcZzJiooo/skill-tracker

适合正在管理本地 skills、prompts、plugins 或多工具 AI 编程环境的开发者。
```

标签：

```text
AI, 开源, 可观测性, 前端, PowerShell, GitHub
```

## Gitee / GitCode 镜像说明

配图：`docs/promotion/assets/gitee-gitcode-cover.png`

标题：

```text
Skill Tracker 国内镜像：本地 AI Agent skill 调用可视化工具
```

正文：

```markdown
这是 Skill Tracker 的国内访问镜像说明。

主仓库：

https://github.com/CcZzJiooo/skill-tracker

Skill Tracker 是一个本地优先的 AI Agent skill 调用可视化工具，用于扫描本机 AI 编程工具日志，生成静态 dashboard，展示：

- skill 调用统计
- 中文技能字典
- 重复 skill 治理
- 工具矩阵
- GitHub 雷达
- 匿名报告导出

如果 GitHub 访问较慢，可以使用国内镜像下载源码；Release ZIP 仍建议以 GitHub Release 为准。
```

## 小黑盒

配图：`docs/promotion/assets/xiaoheihe-cover.png`

标题：

```text
我做了个 AI 编程技能雷达，能看 AI 工具到底用了哪些能力
```

正文：

```markdown
最近折腾 AI 编程工具时，发现一个很像“战绩面板”的需求：

AI 工具到底用了哪些技能？哪些技能一直在触发？哪些重复？哪些根本没人用？

于是做了一个开源小工具：Skill Tracker。

它可以把 Codex、Claude Code、Cursor、Windsurf 这类工具的本地日志扫一遍，然后生成一个 dashboard：

- 看 skill 调用热度
- 看中文技能说明
- 查重复 skill
- 看不同工具偏好
- 搜 GitHub 上类似项目
- 导出治理计划

项目不上传你的日志，都是本地跑。Windows 用户下载 ZIP，解压后双击 `run.bat` 就能试。

GitHub:

https://github.com/CcZzJiooo/skill-tracker

适合喜欢折腾 AI 工具、效率工作流、开源项目的人。
```

标签：

```text
AI工具, 编程, 效率, 开源, GitHub, Cursor, Claude
```

## B 站

配图：`docs/promotion/assets/bilibili-cover.png`

视频标题：

```text
5 分钟看懂 AI Agent 到底调用了哪些 skill：我做了个开源可视化工具
```

视频简介：

```markdown
这期演示一个我做的开源小工具 Skill Tracker。

它可以扫描本机 AI 编程工具日志，把 Codex / Claude Code / Cursor / Windsurf 等工具调用过的 `SKILL.md` 可视化出来。

你会看到：

- skill 调用统计
- 中文技能字典
- 重复 skill 检测
- skill x 工具矩阵
- GitHub 雷达
- 本地隐私优先的运行方式

项目地址：
https://github.com/CcZzJiooo/skill-tracker

如果你也在折腾 AI 编程工具，欢迎试用和提建议。
```

脚本大纲：

```text
0:00 为什么需要 skill 可观测性
0:30 下载并运行 Skill Tracker
1:10 统计总览
1:50 技能字典和中文说明
2:30 治理洞察与重复 skill
3:15 矩阵实验室
3:50 GitHub 雷达
4:30 项目地址和贡献方式
```

标签：

```text
AI编程, 开源项目, Cursor, Claude Code, Codex, 效率工具
```

## 小红书

配图：`docs/promotion/assets/xiaohongshu-cover.png`

标题：

```text
AI 编程工具到底调用了什么？我做了个可视化面板
```

正文：

```markdown
如果你也装了很多 AI 编程工具和 skills，可能会有这个感觉：

它好像很强，但我不知道它到底调用了什么。

所以我做了一个本地小工具：Skill Tracker。

它能把 AI 工具日志里的 skill 调用变成可视化 dashboard：

- 哪些 skill 最常用
- 每个 skill 是干嘛的
- 英文说明转成中文
- 哪些能力重复
- 哪些工具更常调用某类 skill
- 还能去 GitHub 搜类似开源项目

重点是：本地运行，不上传日志。

GitHub 搜索：

Skill Tracker CcZzJiooo

项目地址：

https://github.com/CcZzJiooo/skill-tracker
```

标签：

```text
#AI编程 #开源项目 #效率工具 #Cursor #ClaudeCode #Codex #程序员工具
```

## GitHub Release / Discussions

配图：`docs/social-preview.png`

标题：

```text
Skill Tracker v0.1.0: local-first AI skill telemetry dashboard
```

正文：

```markdown
Skill Tracker v0.1.0 is ready.

It scans local AI coding-agent session logs, detects `SKILL.md` usage, and turns skill calls into a private dashboard:

- skill usage visualization
- Chinese skill catalog
- duplicate-skill governance
- skill x tool matrix
- GitHub discovery radar
- exportable action plans
- anonymous report export

Windows users can download the portable ZIP from Releases, unzip it, and run `run.bat`.

Repository:
https://github.com/CcZzJiooo/skill-tracker
```

标签：

```text
ai-agents, codex, claude-code, cursor, local-first, observability
```
