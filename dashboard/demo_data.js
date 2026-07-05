var SKILL_CATALOG = [
  {
    skill: "deep-research",
    category: "Research",
    zh_desc: "多 Agent 深度研究流水线，覆盖问题定义、资料检索、事实核查、综合分析和研究报告。",
    english_desc: "Multi-agent deep research workflow for source gathering, fact checking, synthesis, and report writing.",
    triggers: ["deep research", "market scan", "evidence-backed answer"],
    source_path: "demo://skills/deep-research/SKILL.md"
  },
  {
    skill: "tdd",
    category: "Engineering",
    zh_desc: "测试驱动开发流程，先写失败测试，再实现功能，最后重构并验证。",
    english_desc: "Test-driven development workflow with red-green-refactor discipline.",
    triggers: ["TDD", "write tests first", "red green refactor"],
    source_path: "demo://skills/tdd/SKILL.md"
  },
  {
    skill: "find-skills",
    category: "Integration",
    zh_desc: "帮助发现、选择和安装合适的 Agent 技能，适合用户问“有没有技能能做某事”的场景。",
    english_desc: "Find and recommend relevant agent skills for a user's task.",
    triggers: ["find skill", "install skill", "what skill can"],
    source_path: "demo://skills/find-skills/SKILL.md"
  },
  {
    skill: "remember",
    category: "Memory",
    zh_desc: "把重要洞察、决定或经验保存到记忆系统，方便未来检索和复用。",
    english_desc: "Save durable project observations and decisions into memory.",
    triggers: ["remember this", "save to memory", "note this"],
    source_path: "demo://skills/remember/SKILL.md"
  },
  {
    skill: "video-edit",
    category: "Media",
    zh_desc: "用 FFmpeg 本地剪辑视频，包括裁剪、合并、变速、字幕、压缩和格式转换。",
    english_desc: "Local video editing workflow powered by FFmpeg.",
    triggers: ["trim video", "merge clips", "add subtitles"],
    source_path: "demo://skills/video-edit/SKILL.md"
  },
  {
    skill: "threejs-animation",
    category: "Visual",
    zh_desc: "Three.js 动画指南，包括关键帧、骨骼动画、morph target 和动画混合。",
    english_desc: "Three.js animation patterns for keyframes, rigs, morph targets, and mixers.",
    triggers: ["three.js animation", "3D interaction", "animated scene"],
    source_path: "demo://skills/threejs-animation/SKILL.md"
  },
  {
    skill: "web-design-guidelines",
    category: "Visual",
    zh_desc: "审查 Web UI 质量，检查可访问性、布局、交互、响应式和设计规范。",
    english_desc: "Review web UI implementation against design and accessibility guidelines.",
    triggers: ["review UI", "frontend polish", "responsive check"],
    source_path: "demo://skills/web-design-guidelines/SKILL.md"
  },
  {
    skill: "to-issues",
    category: "Engineering",
    zh_desc: "把计划、规格或 PRD 拆成可独立领取的 issue，强调可验证的垂直切片。",
    english_desc: "Break plans or PRDs into independent, verifiable implementation issues.",
    triggers: ["split into issues", "implementation plan", "project backlog"],
    source_path: "demo://skills/to-issues/SKILL.md"
  }
];

var SKILL_DATA = [
  { skill: "deep-research", count: 18, dedup_count: 18, raw_count: 31, desc: SKILL_CATALOG[0].english_desc, category: "Research", zh_desc: SKILL_CATALOG[0].zh_desc },
  { skill: "tdd", count: 14, dedup_count: 14, raw_count: 22, desc: SKILL_CATALOG[1].english_desc, category: "Engineering", zh_desc: SKILL_CATALOG[1].zh_desc },
  { skill: "find-skills", count: 11, dedup_count: 11, raw_count: 19, desc: SKILL_CATALOG[2].english_desc, category: "Integration", zh_desc: SKILL_CATALOG[2].zh_desc },
  { skill: "remember", count: 8, dedup_count: 8, raw_count: 10, desc: SKILL_CATALOG[3].english_desc, category: "Memory", zh_desc: SKILL_CATALOG[3].zh_desc },
  { skill: "video-edit", count: 7, dedup_count: 7, raw_count: 12, desc: SKILL_CATALOG[4].english_desc, category: "Media", zh_desc: SKILL_CATALOG[4].zh_desc },
  { skill: "threejs-animation", count: 6, dedup_count: 6, raw_count: 9, desc: SKILL_CATALOG[5].english_desc, category: "Visual", zh_desc: SKILL_CATALOG[5].zh_desc },
  { skill: "web-design-guidelines", count: 5, dedup_count: 5, raw_count: 8, desc: SKILL_CATALOG[6].english_desc, category: "Visual", zh_desc: SKILL_CATALOG[6].zh_desc },
  { skill: "to-issues", count: 3, dedup_count: 3, raw_count: 5, desc: SKILL_CATALOG[7].english_desc, category: "Engineering", zh_desc: SKILL_CATALOG[7].zh_desc }
];

var SKILL_LOG = [
  { skill: "deep-research", tool: "Codex", time: "2026-07-05T09:02:10+08:00", session: "demo-session-research-001", dedup: true, dedup_key: "Codex|demo-session-research-001|deep-research|14860110" },
  { skill: "deep-research", tool: "Codex", time: "2026-07-05T09:02:42+08:00", session: "demo-session-research-001", dedup: false, dedup_key: "Codex|demo-session-research-001|deep-research|14860110" },
  { skill: "find-skills", tool: "Codex", time: "2026-07-05T09:04:18+08:00", session: "demo-session-research-001", dedup: true, dedup_key: "Codex|demo-session-research-001|find-skills|14860112" },
  { skill: "remember", tool: "Codex", time: "2026-07-05T09:07:31+08:00", session: "demo-session-research-001", dedup: true, dedup_key: "Codex|demo-session-research-001|remember|14860113" },
  { skill: "tdd", tool: "ClaudeCode", time: "2026-07-05T10:14:05+08:00", session: "demo-session-engineering-002", dedup: true, dedup_key: "ClaudeCode|demo-session-engineering-002|tdd|14860147" },
  { skill: "tdd", tool: "ClaudeCode", time: "2026-07-05T10:14:53+08:00", session: "demo-session-engineering-002", dedup: false, dedup_key: "ClaudeCode|demo-session-engineering-002|tdd|14860147" },
  { skill: "to-issues", tool: "ClaudeCode", time: "2026-07-05T10:22:11+08:00", session: "demo-session-engineering-002", dedup: true, dedup_key: "ClaudeCode|demo-session-engineering-002|to-issues|14860151" },
  { skill: "web-design-guidelines", tool: "Antigravity", time: "2026-07-05T14:18:20+08:00", session: "demo-session-design-003", dedup: true, dedup_key: "Antigravity|demo-session-design-003|web-design-guidelines|14860270" },
  { skill: "threejs-animation", tool: "Antigravity", time: "2026-07-05T14:25:46+08:00", session: "demo-session-design-003", dedup: true, dedup_key: "Antigravity|demo-session-design-003|threejs-animation|14860273" },
  { skill: "video-edit", tool: "Antigravity", time: "2026-07-05T15:03:12+08:00", session: "demo-session-media-004", dedup: true, dedup_key: "Antigravity|demo-session-media-004|video-edit|14860291" }
];

var GENERATED_AT = "Demo data";
var DEDUP_WINDOW_MINUTES = 2;
var DETECTED_TOOLS = ["Codex", "ClaudeCode", "Antigravity"];
