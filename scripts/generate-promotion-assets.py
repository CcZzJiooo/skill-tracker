from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "promotion" / "assets"
OUT.mkdir(parents=True, exist_ok=True)


FONT_CANDIDATES = [
    Path(r"C:\Windows\Fonts\msyh.ttc"),
    Path(r"C:\Windows\Fonts\simhei.ttf"),
    Path(r"C:\Windows\Fonts\simsun.ttc"),
    Path(r"C:\Windows\Fonts\arial.ttf"),
]


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    if bold:
        for path in [Path(r"C:\Windows\Fonts\msyhbd.ttc"), Path(r"C:\Windows\Fonts\simhei.ttf")]:
            if path.exists():
                return ImageFont.truetype(str(path), size)
    for path in FONT_CANDIDATES:
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def wrap_text(draw: ImageDraw.ImageDraw, text: str, fnt: ImageFont.FreeTypeFont, max_width: int):
    lines = []
    for paragraph in text.split("\n"):
        current = ""
        for char in paragraph:
            candidate = current + char
            if draw.textbbox((0, 0), candidate, font=fnt)[2] <= max_width:
                current = candidate
            else:
                if current:
                    lines.append(current)
                current = char
        if current:
            lines.append(current)
    return lines


def rounded_rect(draw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def make_asset(filename, size, platform, headline, subtitle, bullets, tag):
    w, h = size
    img = Image.new("RGB", size, "#f3efe3")
    draw = ImageDraw.Draw(img)

    # Quiet grid background.
    grid = "#e2dccd"
    for x in range(0, w, 48):
        draw.line([(x, 0), (x, h)], fill=grid, width=1)
    for y in range(0, h, 48):
        draw.line([(0, y), (w, y)], fill=grid, width=1)

    margin = max(42, int(w * 0.055))
    panel = (margin, margin, w - margin, h - margin)
    rounded_rect(draw, panel, 28, "#fbfaf5", "#d5cdbc", 2)

    accent = "#577d17"
    accent2 = "#b68b00"
    cyan = "#008878"
    ink = "#171713"
    muted = "#686254"

    mark = (panel[0] + 34, panel[1] + 34, panel[0] + 92, panel[1] + 92)
    rounded_rect(draw, mark, 14, accent)
    draw.polygon([(mark[0], mark[3]), (mark[2], mark[1]), (mark[2], mark[3])], fill=accent2)

    brand_size = min(max(30, int(w * 0.028)), 48)
    platform_size = min(max(16, int(w * 0.014)), 24)
    draw.text((mark[2] + 18, mark[1] - 2), "Skill Tracker", font=font(brand_size, True), fill=ink)
    draw.text((mark[2] + 20, mark[1] + brand_size + 4), platform, font=font(platform_size), fill=muted)

    badge_text = tag
    badge_font = font(max(16, int(w * 0.016)), True)
    badge_w = draw.textbbox((0, 0), badge_text, font=badge_font)[2] + 34
    badge = (panel[2] - badge_w - 34, panel[1] + 38, panel[2] - 34, panel[1] + 80)
    rounded_rect(draw, badge, 14, "#e8efdc", "#9bb36f", 1)
    draw.text((badge[0] + 17, badge[1] + 8), badge_text, font=badge_font, fill=accent)

    if h < 700:
        title_size = min(max(34, int(w * 0.038)), 50)
        sub_size = min(max(18, int(w * 0.019)), 25)
        bullet_size = min(max(17, int(w * 0.017)), 23)
        card_h = 48
        row_step = 62
    else:
        title_size = min(max(38, int(w * 0.042)), 76)
        sub_size = min(max(20, int(w * 0.02)), 38)
        bullet_size = min(max(18, int(w * 0.018)), 34)
        card_h = 60
        row_step = 76
    title_font = font(title_size, True)
    sub_font = font(sub_size)
    bullet_font = font(bullet_size)

    title_y = panel[1] + 128
    max_text_width = panel[2] - panel[0] - 68
    for line in wrap_text(draw, headline, title_font, max_text_width):
        draw.text((panel[0] + 34, title_y), line, font=title_font, fill=ink)
        title_y += int(title_font.size * 1.18)

    sub_y = title_y + 18
    for line in wrap_text(draw, subtitle, sub_font, max_text_width):
        draw.text((panel[0] + 36, sub_y), line, font=sub_font, fill=muted)
        sub_y += int(sub_font.size * 1.45)

    footer_y = panel[3] - 58
    bullet_y = min(sub_y + 24, footer_y - row_step * 2 - 18)
    col_gap = 22
    col_w = (max_text_width - col_gap) // 2
    for i, item in enumerate(bullets[:4]):
        col = i % 2
        row = i // 2
        x = panel[0] + 36 + col * (col_w + col_gap)
        y = bullet_y + row * row_step
        rounded_rect(draw, (x, y, x + col_w, y + card_h), 16, "#f0ecdf", "#d5cdbc", 1)
        dot_y = y + card_h // 2 - 7
        draw.ellipse((x + 18, dot_y, x + 32, dot_y + 14), fill=cyan)
        for line in wrap_text(draw, item, bullet_font, col_w - 64)[:2]:
            draw.text((x + 44, y + max(8, (card_h - bullet_font.size) // 2 - 2)), line, font=bullet_font, fill=ink)
            y += int(bullet_font.size * 1.25)

    footer = "github.com/CcZzJiooo/skill-tracker"
    footer_font = font(max(17, int(w * 0.016)), True)
    footer_font = font(min(max(16, int(w * 0.015)), 28), True)
    draw.text((panel[0] + 36, footer_y), footer, font=footer_font, fill=accent)
    status = "local-first / MIT / Windows"
    status_w = draw.textbbox((0, 0), status, font=footer_font)[2]
    draw.text((panel[2] - status_w - 36, footer_y), status, font=footer_font, fill=muted)

    img.save(OUT / filename, quality=95)


ASSETS = [
    ("csdn-cover.png", (1200, 628), "CSDN 首图", "把 AI Agent 的 skill 调用变成可视化仪表盘", "本地扫描 Codex / Claude Code / Cursor / Windsurf 等会话日志，看到哪些 SKILL.md 被真正调用。", ["技能热度与调用日志", "中文技能字典", "重复 skill 治理", "GitHub 雷达"], "开源工具"),
    ("juejin-cover.png", (1200, 628), "掘金首图", "开源一个 AI 编程技能观测工具", "面向开发者的 local-first dashboard：统计、翻译、查重、矩阵和 GitHub 发现。", ["零后端，静态打开", "自然语言搜索", "治理行动方案", "可导出报告"], "AI Coding"),
    ("oschina-cover.png", (1200, 628), "OSCHINA 首图", "Skill Tracker：本地优先的 AI Agent skills observability", "让隐藏在 Agent 日志里的技能调用、重叠和缺失说明变得可检查。", ["MIT 开源", "隐私本地优先", "多工具日志扫描", "治理报告导出"], "Open Source"),
    ("zhihu-cover.png", (1200, 675), "知乎封面", "为什么 AI 编程工具需要 skill 可观测性？", "当工具越来越会调用 skills，用户也需要知道它到底调用了什么、为什么重复、哪里缺说明。", ["看见调用链路", "理解每个 skill", "治理重复能力", "降低黑箱感"], "问题驱动"),
    ("v2ex-cover.png", (1200, 628), "V2EX 配图", "分享一个本地 AI skills 调用可视化小工具", "没有服务端，没有账号系统，跑完脚本直接打开静态 dashboard。", ["PowerShell 采集", "HTML Dashboard", "本地数据", "GitHub 开源"], "Show HN"),
    ("segmentfault-cover.png", (1200, 628), "SegmentFault 首图", "从日志到治理：AI Agent skill 调用可视化实践", "用一个轻量项目，把 skill usage、中文描述和重复治理串成完整链路。", ["日志解析", "去重统计", "健康评分", "Issue 草稿"], "实践教程"),
    ("xiaoheihe-cover.png", (1200, 675), "小黑盒配图", "我做了个 AI 编程技能雷达", "像看战绩一样看 AI 工具到底用了哪些技能：热度、重复、中文说明和开源搜索。", ["工具使用战绩", "技能图谱", "一键本地打开", "适合折腾党"], "效率工具"),
    ("bilibili-cover.png", (1920, 1080), "B 站封面", "5 分钟看懂 AI Agent 技能调用", "Skill Tracker 演示：采集本地日志、打开 dashboard、查 skill、看矩阵、找重复。", ["演示流程", "开源项目", "中文界面", "可本地运行"], "视频封面"),
    ("xiaohongshu-cover.png", (1242, 1660), "小红书封面", "AI 编程工具到底调用了什么？", "一个本地可视化 dashboard：把 skills 调用、中文说明和重复治理都摆到明面上。", ["不用上传日志", "双击运行", "中文可读", "开源免费"], "图文笔记"),
    ("gitee-gitcode-cover.png", (1200, 628), "Gitee / GitCode 配图", "给国内用户准备的 Skill Tracker 镜像说明", "GitHub 已开源，国内镜像用于更快访问、下载和协作。", ["仓库镜像", "Release ZIP", "中文 README", "Issue 同步"], "国内镜像"),
]


def main():
    for asset in ASSETS:
        make_asset(*asset)
    print(f"Generated {len(ASSETS)} assets in {OUT}")


if __name__ == "__main__":
    main()
