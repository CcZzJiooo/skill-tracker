import os
from PIL import Image, ImageDraw

def create_skill_tracker_icon(output_path):
    sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)]
    images = []

    for width, height in sizes:
        img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)

        # Base background - rounded rectangle
        corner_radius = int(width * 0.22)
        bg_color = (13, 14, 12, 255) # Dark sleek #0d0e0c
        border_color = (185, 243, 90, 180) # Neon green border #b9f35a

        draw.rounded_rectangle(
            [(0, 0), (width - 1, height - 1)],
            radius=corner_radius,
            fill=bg_color,
            outline=border_color,
            width=max(1, int(width * 0.04))
        )

        # Polygon shapes matching favicon design
        pad = int(width * 0.2)
        w_inner = width - 2 * pad
        h_inner = height - 2 * pad

        p1 = (pad, pad)
        p2 = (pad + w_inner, pad)
        p3 = (pad + w_inner, pad + h_inner)
        p4 = (pad, pad + h_inner)

        # Accent green block
        green = (185, 243, 90, 255)
        gold = (240, 184, 90, 255)
        dark_line = (13, 14, 12, 255)

        draw.polygon([p1, p2, p4], fill=green)
        draw.polygon([p2, p3, p4], fill=gold)

        # Slash line across
        stroke_w = max(2, int(width * 0.08))
        draw.line([p4, p2], fill=dark_line, width=stroke_w)

        images.append(img)

    # Save multi-size ICO
    images[0].save(
        output_path,
        format="ICO",
        sizes=[(img.width, img.height) for img in images],
        append_images=images[1:]
    )
    print(f"Generated ICO icon: {output_path}")

if __name__ == "__main__":
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    dashboard_ico = os.path.join(repo_root, "dashboard", "favicon.ico")
    root_ico = os.path.join(repo_root, "skill-tracker.ico")

    create_skill_tracker_icon(dashboard_ico)
    create_skill_tracker_icon(root_ico)
