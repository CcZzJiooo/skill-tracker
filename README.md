# Skill Tracker

Skill Tracker 是一个本地优先的 AI Agent 技能调用可视化工具。它扫描 Antigravity、Codex、ClaudeCode、Cursor、Windsurf 等工具的本地会话日志，统计哪些 `SKILL.md` 被调用，并在静态 dashboard 中展示技能热度、调用日志、会话链路和中文功能说明。

![Dashboard desktop preview](docs/preview-desktop.png)

## 核心功能

- **技能调用可视化**: 展示总调用量、活跃技能、Top Skill、去重节省、Top 20 排行和完整技能表。
- **中文功能说明**: 每个 skill 都可以维护中文说明，dashboard 支持按技能名、分类和中文描述搜索。
- **去重统计口径**: 支持“去重调用”和“原始读取”两种视角，默认把同一工具、同一会话、同一 skill 在短时间内重复读取只算一次。
- **会话详情追踪**: 调用日志里的会话 ID 可以点击，查看该会话的时间范围、来源工具、去重/原始数量和技能时间线。
- **技能字典工作台**: 在 dashboard 里筛选、搜索、编辑中文说明，并导出新的 `skill_catalog.json`。
- **多工具本地扫描**: 自动检测常见 AI 编程工具的日志路径，也可以在 `config.json` 中加入自定义工具目录。
- **静态 dashboard**: 生成的数据是 JS/JSON 文件，`dashboard/index.html` 可直接打开，不需要后端服务。
- **开源演示数据**: 新 clone 的项目会先显示合成 demo 数据；运行采集后，本机真实数据会自动覆盖 demo。

## 快速开始

Windows:

```powershell
git clone https://github.com/YOUR_USERNAME/skill-tracker.git
cd skill-tracker
powershell -ExecutionPolicy Bypass -File .\collect.ps1
start .\dashboard\index.html
```

也可以直接双击 `run.bat`，它会先运行采集脚本，再打开 dashboard。

如果你还没有运行采集，dashboard 会加载 `dashboard/demo_data.js` 中的合成数据，用来展示界面和交互能力。

## 配置

编辑 `config.json`:

```json
{
  "skills_root": "",
  "output_dir": "./dashboard",
  "max_log_entries": 5000,
  "dedup_window_minutes": 2,
  "custom_tools": [
    { "name": "MyTool", "path": "C:/Users/YOU/.mytool/sessions" }
  ]
}
```

字段说明:

- `skills_root`: skill 目录。留空时会自动尝试常见本地路径。
- `output_dir`: dashboard 数据输出目录。
- `max_log_entries`: 调用日志最大输出条数。
- `dedup_window_minutes`: 去重窗口分钟数。
- `custom_tools`: 自定义工具名和日志目录。

## 生成文件

运行 `collect.ps1` 后会生成或更新:

- `dashboard/skill_data.js`: 每个 skill 的去重调用数、原始读取数、分类和中文说明。
- `dashboard/skill_log.js`: 调用明细，包括 skill、工具、时间、会话 ID 和去重 key。
- `dashboard/skill_call_stats.json`: 结构化统计数据，方便后续接入 CLI、API 或测试。
- `dashboard/skill_catalog.json`: 可编辑的 skill 元数据目录，包含中文说明、英文说明、触发词和来源路径。
- `dashboard/skill_catalog.js`: dashboard 直接加载的 catalog 数据。

这些真实采集文件默认在 `.gitignore` 中被忽略，避免把本机会话日志统计、session id、路径或私有 skill 元数据误提交到 GitHub。可提交的演示数据是 `dashboard/demo_data.js`。

## 技能字典工作台

Dashboard 的“技能字典”页用于维护每个 skill 的中文功能说明。你可以按分类、缺失说明、已编辑状态筛选，也可以搜索 skill 名称、中文说明或英文描述。

浏览器不能直接覆盖本地文件，所以工作台采用导出模式：编辑完成后点击“导出 JSON”，再用导出的文件替换 `dashboard/skill_catalog.json`。下一次运行采集脚本时，它会把 JSON 转换成 `skill_catalog.js` 给 dashboard 加载。

## 支持的工具

| Tool | Default path |
|---|---|
| Antigravity IDE | `~/.gemini/antigravity-ide/brain/` |
| ClaudeCode | `~/.claude/projects/` |
| Codex | `~/.codex/archived_sessions/` |
| Cursor | `%APPDATA%/Cursor/logs/` |
| Windsurf | `%APPDATA%/Windsurf/logs/` |

Dashboard 只会显示当前机器实际检测到的工具。

## 工作原理

AI Agent 调用 skill 时通常会读取对应的 `skills/<name>/SKILL.md`。采集脚本会扫描本地会话日志，提取 skill 名称、时间、来源工具和会话 ID，然后生成 dashboard 可直接加载的数据文件。

默认去重规则:

```text
tool + session/file + skill + time bucket
```

例如 `dedup_window_minutes = 2` 时，同一工具、同一会话、同一 skill 在 2 分钟内重复读取只算 1 次去重调用，但原始读取数仍会保留。

## 隐私

Skill Tracker 默认只读取本机日志并生成本地文件，不上传数据。开源发布前，如果你要提交截图或示例数据，建议使用匿名化样例，避免把本机会话 ID、路径或内部 skill 名称直接公开。

## 项目结构

```text
skill-tracker/
├─ collect.ps1
├─ config.json
├─ run.bat
├─ dashboard/
│  ├─ index.html
│  ├─ demo_data.js
│  ├─ skill_catalog.json
│  ├─ skill_catalog.js
│  ├─ skill_data.js
│  ├─ skill_log.js
│  ├─ skill_call_stats.json
├─ docs/
│  ├─ preview-desktop.png
│  └─ preview-mobile.png
└─ README.md
```

## 开发方向

- 增加匿名化导出，用于开源 issue、报告和团队分享。
- 增加 catalog 导入校验，防止用户导入格式错误的 `skill_catalog.json`。
- 增加趋势快照，对比不同日期的 skill 使用变化。
- 增加 CLI 包装，例如 `skill-tracker collect` 和 `skill-tracker open`。

## License

MIT
