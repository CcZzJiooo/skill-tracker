# v0.4.0 修复清单

## 已完成

- [x] 修复 Antigravity 新版 Windows 安装目录识别。
- [x] 兼容 `Antigravity IDE.exe`、`antigravity-ide` 和带空格进程名。
- [x] 保留旧版 `Antigravity\Antigravity.exe` 兼容性。
- [x] 工具未安装时不扫描遗留日志，避免误报和无效扫描。
- [x] 工具重新安装后，在下一次 collector 刷新时自动恢复扫描。
- [x] 桌面快捷方式与主页“同步”都通过异步 watcher 触发刷新，不再把历史扫描阻塞在启动界面。
- [x] 增加持久化文件缓存；只重新解析新增或变更的日志文件，并保留动态技能的 `SKILL.md` 来源。
- [x] 识别 Antigravity 脑内 transcript 中的真实 `created_at` 日期。
- [x] 回填 8 月 1、2、4 日可验证的真实 skill 调用，并核对 8 月 3 日没有符合规则的 skill 调用。
- [x] 增加带空格安装路径的自动回归测试。
- [x] 补充本次根因、边界和部署后验证文档。

## 本次验证

- [x] `scripts/test-collector-antigravity-layout.ps1`
- [x] 全部 20 个 `test-*` 回归测试（20/20 通过）
- [x] `scripts/verify-collector.ps1 -SkipCollect`
- [x] 真实机器重新采集后检查 `dashboard/tool_report.js`
- [x] 真实机器重新采集后检查 `dashboard/skill_log.js` 的日期分布
- [x] 浏览器打开主页并确认 Antigravity 徽章，以及真实存在的 8 月 1、2、4、5 日记录；8 月 3 日没有伪造记录。

本次真实采集证据：2026-08-05 12:52:38 生成，507 条原始记录、328 条去重记录；
调用日志覆盖到 2026-08-05。Trae 的所有残留日志源均为 `installed=false`、
`detected=false`、`files_scanned=0`，因此不会再次被误扫。

## 交付后手工步骤

1. 关闭旧的 dashboard 窗口或 watcher。
2. 双击桌面快捷方式重新启动。
3. 打开主页后点击一次“同步”，等待异步刷新完成。
4. 检查“调用日志”显示 2026/08/01、08/02、08/04 和 08/05；08/03 只有发生真实 skill 调用时才应出现。
5. 检查工具栏出现 Antigravity，并确认统计数字大于零。

## 证据边界

collector 只能记录本地日志中可识别为真实 skill 调用、且能由本机
`SKILL.md` 验证的记录。只打开 IDE、普通对话、阅读普通文件，或日志已
被工具清理的活动，不会被伪造成 skill 调用。
