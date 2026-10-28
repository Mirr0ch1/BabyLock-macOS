#!/usr/bin/env python3
"""Regenerate the README banners (one per supported language)."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "assets" / "icon" / "babylock-icon-1024.png"
OUT_DIR = ROOT / "assets" / "readme"

LATIN_FONT = "/usr/share/fonts/truetype/ubuntu/UbuntuSans[wdth,wght].ttf"
CJK_SC_FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
CJK_TC_FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
SYMBOL_FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

LANGUAGES = {
    "en": {
        "tagline": "A child lock for your Mac keyboard.",
        "languages": "5 languages",
        "font": LATIN_FONT,
        "cjk": False,
    },
    "zh-Hans": {
        "tagline": "给 Mac 键盘的童锁。",
        "languages": "5 种语言",
        "font": CJK_SC_FONT,
        "cjk": True,
    },
    "zh-Hant": {
        "tagline": "給 Mac 鍵盤的童鎖。",
        "languages": "5 種語言",
        "font": CJK_TC_FONT,
        "cjk": True,
    },
    "fr": {
        "tagline": "Un verrou enfant pour le clavier de votre Mac.",
        "languages": "5 langues",
        "font": LATIN_FONT,
        "cjk": False,
    },
    "ru": {
        "tagline": "Детский замок для клавиатуры Mac.",
        "languages": "5 языков",
        "font": LATIN_FONT,
        "cjk": False,
    },
}

W, H = 1600, 560


def font(path: str, size: int, bold: bool = False, cjk: bool = False) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(path, size, index=0)
    if not cjk:
        try:
            f.set_variation_by_name("Bold" if bold else "Regular")
        except Exception:
            pass
    return f


def vertical_gradient(size: tuple[int, int], top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    width, height = size
    image = Image.new("RGB", size)
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / max(height - 1, 1)
        color = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
        draw.line((0, y, width, y), fill=color)
    return image.convert("RGBA")


def chip_metrics(draw: ImageDraw.ImageDraw, x: int, y: int, text: str, f: ImageFont.FreeTypeFont) -> tuple[int, int, int, int, int]:
    pad_x, pad_y = 20, 12
    bbox = draw.textbbox((0, 0), text, font=f)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    w, h = tw + pad_x * 2, th + pad_y * 2
    return w, h, x + pad_x, y + pad_y - bbox[1], bbox[1]


def make_banner(lang: str, spec: dict) -> None:
    base = vertical_gradient((W, H), (24, 25, 29), (39, 41, 47))

    # Warm glow behind the icon.
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((20, 40, 640, 660), fill=(246, 201, 164, 34))
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    base = Image.alpha_composite(base, glow)

    # Large, faint Command glyph on the right.
    symbol_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(symbol_layer)
    sf = ImageFont.truetype(SYMBOL_FONT, 440)
    sd.text((1210, 45), "⌘", font=sf, fill=(255, 255, 255, 13))
    base = Image.alpha_composite(base, symbol_layer)

    # A few keyboard keys along the right edge.
    key_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    kd = ImageDraw.Draw(key_layer)
    keys = [
        (1360, 372, 118, 118, "⇧"),
        (1494, 372, 86, 118, "esc"),
        (1360, 506, 220, 38, "space"),
    ]
    for (x, y, w, h, label) in keys:
        kd.rounded_rectangle((x, y, x + w, y + h), radius=18, fill=(255, 255, 255, 10), outline=(255, 255, 255, 30), width=2)
        if label in ("space", "esc"):
            kf = font(LATIN_FONT, 20 if label == "space" else 26, bold=False)
        else:
            kf = ImageFont.truetype(SYMBOL_FONT, 38)
        bbox = kd.textbbox((0, 0), label, font=kf)
        kd.text((x + (w - (bbox[2] - bbox[0])) / 2, y + (h - (bbox[3] - bbox[1])) / 2 - bbox[1]), label, font=kf, fill=(255, 255, 255, 72))
    base = Image.alpha_composite(base, key_layer)

    # App icon with a soft shadow.
    icon = Image.open(ICON).convert("RGBA").resize((340, 340), Image.LANCZOS)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sh = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    sh.paste((0, 0, 0, 150), (0, 0), icon)
    shadow.paste(sh, (122, 132), sh)
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    base = Image.alpha_composite(base, shadow)
    base.paste(icon, (110, 110), icon)

    draw = ImageDraw.Draw(base)

    title_font = font(LATIN_FONT, 112, bold=True)
    tagline_font = font(spec["font"], 42 if spec["cjk"] else 36, bold=False, cjk=spec["cjk"])
    chip_font = font(spec["font"], 24 if not spec["cjk"] else 26, bold=False, cjk=spec["cjk"])
    small_font = font(LATIN_FONT, 22, bold=False)

    draw.text((520, 128), "Baby Lock", font=title_font, fill=(255, 255, 255, 246))
    draw.text((526, 278), spec["tagline"], font=tagline_font, fill=(198, 201, 208, 240))

    # Chips need their own layer: ImageDraw replaces alpha instead of blending.
    chip_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    chip_draw = ImageDraw.Draw(chip_layer)
    labels = [("macOS 13+", chip_font), ("arm64 + x86_64", chip_font), (spec["languages"], chip_font)]
    x = 526
    y = 360
    chip_texts = []
    for label, f in labels:
        w, h, tx, ty, top = chip_metrics(chip_draw, x, y, label, f)
        chip_draw.rounded_rectangle((x, y, x + w, y + h), radius=h // 2, fill=(255, 255, 255, 16), outline=(255, 255, 255, 52), width=1)
        chip_texts.append((tx, ty, label, f))
        x += w + 14
    base = Image.alpha_composite(base, chip_layer)
    draw = ImageDraw.Draw(base)
    for tx, ty, label, f in chip_texts:
        draw.text((tx, ty), label, font=f, fill=(230, 231, 235, 235))

    draw.text((526, 474), "github.com/Mirr0ch1/BabyLock-macOS", font=small_font, fill=(132, 136, 145, 220))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"banner-{lang}.png"
    base.convert("RGB").save(out, optimize=True)
    print(f"Wrote {out} ({out.stat().st_size:,} bytes)")


def main() -> None:
    for lang, spec in LANGUAGES.items():
        make_banner(lang, spec)


if __name__ == "__main__":
    main()
