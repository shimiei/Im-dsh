"""生成 IMDSH 的 App 图标（液态玻璃风格）。

设计：深蓝径向底 + 一块半透明玻璃板 + 终端提示符 `>_` 字形，
颜色与 dsh-webim / DeepSeek 的品牌蓝一致。纯几何绘制，不依赖字体。
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "ios", "src", "Resources", "Icons"))
SIZE = 1024
ACCENT = (77, 107, 254)        # #4D6BFE
DEEP = (10, 16, 38)            # 深处底色
LIGHT = (140, 168, 255)


def radial_background(size: int) -> Image.Image:
    """从左上高光到深蓝的径向渐变。"""
    img = Image.new("RGB", (size, size), DEEP)
    px = img.load()
    cx, cy = size * 0.34, size * 0.28
    max_d = math.hypot(size, size) * 0.95
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - cx, y - cy) / max_d
            t = min(1.0, d) ** 0.85
            # 三段插值：高光 -> 品牌蓝 -> 深底
            if t < 0.45:
                k = t / 0.45
                r = _lerp(LIGHT[0], ACCENT[0], k)
                g = _lerp(LIGHT[1], ACCENT[1], k)
                b = _lerp(LIGHT[2], ACCENT[2], k)
            else:
                k = (t - 0.45) / 0.55
                r = _lerp(ACCENT[0], DEEP[0], k)
                g = _lerp(ACCENT[1], DEEP[1], k)
                b = _lerp(ACCENT[2], DEEP[2], k)
            px[x, y] = (int(r), int(g), int(b))
    return img


def _lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def gradient_alpha(size: int, top: int, bottom: int) -> Image.Image:
    """竖向 alpha 渐变，用于玻璃板的反光。"""
    img = Image.new("L", (size, size), 0)
    px = img.load()
    for y in range(size):
        t = y / max(1, size - 1)
        px_v = int(_lerp(top, bottom, t))
        for x in range(size):
            px[x, y] = px_v
    return img


def rounded_line(draw: ImageDraw.ImageDraw, p0, p1, width: int, fill):
    """带圆头的粗线段。"""
    draw.line([p0, p1], fill=fill, width=width)
    for p in (p0, p1):
        r = width / 2
        draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=fill)


def build() -> Image.Image:
    base = radial_background(SIZE).convert("RGBA")

    # 斜向玻璃反光
    sheen = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    sd.polygon([(0, SIZE * 0.62), (SIZE, SIZE * 0.10), (SIZE, SIZE * 0.34), (0, SIZE * 0.86)],
               fill=(255, 255, 255, 16))
    sheen = sheen.filter(ImageFilter.GaussianBlur(SIZE * 0.02))
    base = Image.alpha_composite(base, sheen)

    # 玻璃板
    plate_size = int(SIZE * 0.68)
    plate = Image.new("RGBA", (plate_size, plate_size), (0, 0, 0, 0))
    pd = ImageDraw.Draw(plate)
    radius = int(plate_size * 0.30)
    pd.rounded_rectangle([0, 0, plate_size - 1, plate_size - 1], radius=radius,
                         fill=(255, 255, 255, 26))
    # 顶部更亮的高光
    gloss = gradient_alpha(plate_size, 46, 6)
    gloss_layer = Image.new("RGBA", (plate_size, plate_size), (255, 255, 255, 255))
    plate = Image.composite(Image.alpha_composite(
        plate, Image.new("RGBA", (plate_size, plate_size), (255, 255, 255, 0))), plate, Image.new("L", (plate_size, plate_size), 255))
    pd = ImageDraw.Draw(plate)
    pd.rounded_rectangle([0, 0, plate_size - 1, plate_size - 1], radius=radius,
                         outline=(255, 255, 255, 92), width=max(2, SIZE // 220))

    plate_mask = Image.new("L", (plate_size, plate_size), 0)
    ImageDraw.Draw(plate_mask).rounded_rectangle([0, 0, plate_size - 1, plate_size - 1],
                                                 radius=radius, fill=255)
    gloss_rgba = Image.new("RGBA", (plate_size, plate_size), (255, 255, 255, 255))
    gloss_rgba.putalpha(gloss)
    plate = Image.composite(Image.alpha_composite(plate, gloss_rgba), plate, plate_mask)

    # 画 `>_`
    glyph = Image.new("RGBA", (plate_size, plate_size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glyph)
    stroke = max(6, int(plate_size * 0.085))
    cx, cy = plate_size * 0.5, plate_size * 0.5
    span = plate_size * 0.22
    # `>`
    rounded_line(gd, (cx - span * 1.05, cy - span * 0.92), (cx + span * 0.34, cy), stroke,
                 (255, 255, 255, 238))
    rounded_line(gd, (cx + span * 0.34, cy), (cx - span * 1.05, cy + span * 0.92), stroke,
                 (255, 255, 255, 238))
    # `_`
    rounded_line(gd, (cx + span * 0.62, cy + span * 0.92), (cx + span * 1.42, cy + span * 0.92),
                 stroke, (255, 255, 255, 205))

    # 柔和投影，让玻璃板浮起来（直接画在整幅画布上，避免模糊裁切出方角）
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sh = ImageDraw.Draw(shadow)
    shadow_pos = ((SIZE - plate_size) // 2, int((SIZE - plate_size) / 2 + SIZE * 0.018))
    sh.rounded_rectangle([shadow_pos[0], shadow_pos[1],
                          shadow_pos[0] + plate_size - 1, shadow_pos[1] + plate_size - 1],
                         radius=radius, fill=(2, 8, 24, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(SIZE * 0.035))
    base = Image.alpha_composite(base, shadow)

    plate = Image.alpha_composite(plate, glyph)
    base.alpha_composite(plate, dest=((SIZE - plate_size) // 2, (SIZE - plate_size) // 2))

    # 极轻微暗角
    vignette = Image.new("L", (SIZE, SIZE), 0)
    vd = ImageDraw.Draw(vignette)
    vd.ellipse([-SIZE * 0.2, -SIZE * 0.2, SIZE * 1.2, SIZE * 1.2], fill=255)
    vignette = vignette.filter(ImageFilter.GaussianBlur(SIZE * 0.18))
    dark = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 70))
    base = Image.composite(base, Image.alpha_composite(base, dark), vignette)

    return base.convert("RGB")


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    master = build()
    master.save(os.path.join(OUT, "AppIcon-1024.png"))

    # iOS 需要的尺寸（iPhone / iPad 全量，iPadOS 26 仍会读这些键）
    targets = {
        "AppIcon-60@2x.png": 120,
        "AppIcon-60@3x.png": 180,
        "AppIcon-76@1x.png": 76,
        "AppIcon-76@2x.png": 152,
        "AppIcon-83.5@2x.png": 167,
        "AppIcon-20@2x.png": 40,
        "AppIcon-20@3x.png": 60,
        "AppIcon-29@2x.png": 58,
        "AppIcon-29@3x.png": 87,
        "AppIcon-40@2x.png": 80,
        "AppIcon-40@3x.png": 120,
    }
    for name, px in targets.items():
        master.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
    print("icons written to", OUT)


if __name__ == "__main__":
    main()
