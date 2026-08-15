# Skill Tracker 开源增长与功能审计

审计日期：2026-08-15

## 先说结论

当前最影响项目增长的不是再增加一个 dashboard 卡片，而是“公开版本落后于代码版本”和“新用户无法形成贡献/反馈闭环”。本地 `main` 已经包含 v0.3/v0.4 相关修复，但 GitHub Releases 页面当前仍显示 v0.2.2；公开仓库的 Issues 也显示为关闭创建。新访客因此很难判断当前版本、如何反馈问题，以及项目是否仍在维护。

优先级应当是：

1. 发布一个真实可下载的 v0.4.0，并让 README、Release、截图和运行命令完全一致。
2. 打开 Issues，补齐 adapter / bug / feature 三类模板，建立“发现问题 → 反馈 → 修复”的入口。
3. 做一个真正有区分度的 MVP：Skill Health / Outcome 视图，而不是继续增加静态统计卡片。
4. 再扩展跨平台 CLI、匿名样本导入和团队对比，扩大可使用人群。

## 当前版本审计

### 已经具备的能力

- Windows 一键启动、后台 watcher、手动同步和本地静态 dashboard。
- Codex、Claude Code、Antigravity、Cursor 等多种本地日志来源检测。
- 技能调用时间线、热度、去重、技能目录、中文摘要、重复/冲突治理。
- 匿名导出、GitHub 雷达、桌面快捷方式和便携包验证脚本。
- 已有 ROADMAP、贡献指南、行为准则、许可证、引用文件和 Issue 模板。

### 当前可验证的发布缺口

- GitHub Releases 公开最新版本仍为 v0.2.2，而仓库当前代码已明显超出该版本。
- README 已按 v0.4.0 写发布命令，但 GitHub Release 页面没有对应的 v0.4.0 下载包。
- 公开 Issues 当前没有开放的用户反馈入口。
- 文档中的能力描述很多，但缺少一条 60 秒内完成的“安装 → 看到真实数据 → 导出匿名报告”的演示路径。
- 项目核心数据来自不同 AI 工具的私有日志，首次运行可能没有数据；目前需要更突出地解释“没有命中”和“采集失败”的区别。

## 功能路线：按价值排序

### P0：发布与信任（立刻做）

这部分不属于炫技功能，却最可能提高转化率。

- 发布 v0.4.0 Windows portable ZIP 和 SHA256SUMS。
- README 顶部增加：当前版本、平台支持、30 秒 GIF、真实数据/演示数据区别、隐私承诺。
- 打开 Issues，并保留现有三类模板；新增“新工具适配器”入口的可复制诊断命令。
- 加入 GitHub Actions：PowerShell 回归测试、便携包构建、hash 生成、Release artifact 上传。
- 增加 `SUPPORT.md` 中的诊断包流程：只导出 tool_report、版本、错误摘要和匿名统计，不要求用户上传原始日志。

验收标准：一个第一次访问仓库的人，不看源码也能在 60 秒内知道下载哪个文件、如何启动、数据是否上传、出问题去哪里反馈。

### P1：核心差异化 MVP——Skill Health / Outcome

现在项目回答的是“哪些 skill 被读取过”，但用户真正想知道的是“哪些 skill 值得保留、是否有效”。建议新增：

- 每个 skill 的使用次数、最近使用、覆盖工具数、重复读取率。
- 低信号标记：长期未使用、重复率过高、说明缺失、多个 skill 触发同一意图。
- 任务结果关联：从本地会话中识别完成/失败/中断信号，显示“使用后完成率”时明确标注为启发式推断。
- “建议保留 / 合并 / 重写 / 观察”四种治理建议，并支持导出 Markdown 报告。
- 可解释证据：每条建议都显示来源文件、时间范围和触发规则。

这会把项目从“技能统计看板”推进到“技能维护工具”，也是比普通 token/cost dashboard 更容易形成记忆点的功能。

### P1：可移植性与导入

- 提供 `skill-tracker collect`、`skill-tracker open`、`skill-tracker export` 三个 CLI 子命令。
- 把 collector 的核心逻辑从 PowerShell 入口逐步抽成跨平台运行层，Windows 继续保留便携启动器。
- 支持导入匿名 JSON 报告，让没有本地日志、Linux/macOS 用户也能展示数据。
- 增加 JSON Schema 和 schema version，避免不同版本 dashboard 读取旧报告时静默出错。

### P2：生态能力

- Adapter SDK：新工具只需声明日志路径、时间字段、skill 命中规则和测试 fixture。
- MCP 只读接口：让 Codex/Claude 直接查询“我最常用的 skill”“这个 skill 是否重复”。
- 社区匿名 benchmark：只上传聚合统计，不上传技能名、路径、session 或原文。
- GitHub Action：在 PR 中检查新增/修改的 `SKILL.md` 是否有描述、触发条件、冲突或重复风险。
- 团队模式：以导入匿名报告的方式比较工具覆盖率和技能健康度，不上传原始会话。

## 暂时不要优先做的事

- 不要先做在线 SaaS 或账号系统：它会削弱当前最清晰的 local-first 隐私定位。
- 不要继续堆更多榜单和装饰性卡片：当前 dashboard 已有足够多的统计入口。
- 不要为了支持工具数量而复制粘贴解析器：先做 adapter contract 和 fixture，降低维护成本。
- 不要把启发式的“任务成功率”包装成精确因果结论，必须展示证据和不确定性。

## 建议的三个近期 Issue

1. `release: publish v0.4.0 portable package and align public docs`
2. `feat: add explainable skill health and outcome report`
3. `feat: add cross-platform CLI and anonymous report import`

## 建议的 v0.4.0 发布检查表

- [ ] GitHub Release 与仓库版本、README 命令、CITATION.cff 完全一致。
- [ ] Windows portable ZIP 可在无开发环境机器上启动。
- [ ] 首次运行无标准 skill 目录时仍显示真实且明确的空扫描结果。
- [ ] 真实日志扫描、空扫描、watcher、缓存、日期范围和页面加载回归通过。
- [ ] README GIF/截图与当前页面一致。
- [ ] Issues 开放，至少有 bug、feature、tool adapter 三个入口。
- [ ] Release 附带 SHA256SUMS，并说明生成数据不会进入发布包。

