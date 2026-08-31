#!/usr/bin/env python3
"""Generate the MAKE10 launcher icons and the Play Store assets.

Everything the store and the launcher need is derived from this one script, so
the artwork can be regenerated after a colour or wording change instead of
being re-cut by hand.

    python3 tool/branding/generate_icons.py

Writes:
  android/app/src/main/res/mipmap-*/ic_launcher.png          legacy launcher
  android/app/src/main/res/mipmap-*/ic_launcher_round.png    legacy round
  android/app/src/main/res/mipmap-*/ic_launcher_foreground.png
  android/app/src/main/res/mipmap-*/ic_launcher_background.png
  android/app/src/main/res/mipmap-*/ic_launcher_monochrome.png
  store/icon-512.png                                         Play listing icon
  store/feature-graphic-1024x500.png                         Play feature graphic
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "android/app/src/main/res"
STORE = ROOT / "store"

# The app seeds its Material theme from Colors.indigo; the icon uses the same
# family so the launcher and the first frame of the app agree.
INDIGO_LIGHT = (92, 107, 205)
INDIGO_DARK = (40, 53, 147)
AMBER = (255, 193, 7)
WHITE = (255, 255, 255)

FONT_BOLD = "/usr/share/fonts/opentype/noto/NotoSansCJK-Black.ttc"
FONT_FALLBACK = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# Launcher densities. Legacy icons are 48dp, adaptive layers are 108dp.
DENSITIES = {
    "mdpi": 1,
    "hdpi": 1.5,
    "xhdpi": 2,
    "xxhdpi": 3,
    "xxxhdpi": 4,
}


def font(size: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(FONT_BOLD, size)
    except OSError:
        return ImageFont.truetype(FONT_FALLBACK, size)


def gradient(size: int) -> Image.Image:
    """A diagonal indigo gradient, drawn at 1x1 pixels and scaled up."""
    small = Image.new("RGB", (2, 2))
    small.putpixel((0, 0), INDIGO_LIGHT)
    small.putpixel((1, 0), tuple((a + b) // 2 for a, b in zip(INDIGO_LIGHT, INDIGO_DARK)))
    small.putpixel((0, 1), tuple((a + b) // 2 for a, b in zip(INDIGO_LIGHT, INDIGO_DARK)))
    small.putpixel((1, 1), INDIGO_DARK)
    return small.resize((size, size), Image.Resampling.BICUBIC)


def draw_mark(
    img: Image.Image,
    box: tuple[float, float, float, float],
    equals_colour=AMBER,
    digits_colour=WHITE,
    shadow: bool = True,
) -> None:
    """Draw `=10` centred inside `box` (l, t, r, b), scaled to fill it.

    The equals sign carries the verb -- the icon reads as "makes 10" rather
    than as the number 10 -- so it is set in the accent colour and slightly
    smaller than the digits.
    """
    left, top, right, bottom = box
    width = right - left
    height = bottom - top

    # Size the type by measuring at a reference size and scaling once, so the
    # mark fills the box the same way at every density.
    ref = 200
    f_digits = font(ref)
    f_equals = font(int(ref * 0.72))
    d = ImageDraw.Draw(img)

    eq_box = d.textbbox((0, 0), "=", font=f_equals)
    dg_box = d.textbbox((0, 0), "10", font=f_digits)
    gap = ref * 0.10
    total_w = (eq_box[2] - eq_box[0]) + gap + (dg_box[2] - dg_box[0])
    total_h = dg_box[3] - dg_box[1]

    scale = min(width / total_w, height / total_h)
    f_digits = font(max(1, int(ref * scale)))
    f_equals = font(max(1, int(ref * 0.72 * scale)))
    gap *= scale

    eq_box = d.textbbox((0, 0), "=", font=f_equals)
    dg_box = d.textbbox((0, 0), "10", font=f_digits)
    eq_w, dg_w = eq_box[2] - eq_box[0], dg_box[2] - dg_box[0]
    dg_h = dg_box[3] - dg_box[1]

    x = left + (width - (eq_w + gap + dg_w)) / 2
    y = top + (height - dg_h) / 2

    if shadow:
        blur = Image.new("RGBA", img.size, (0, 0, 0, 0))
        bd = ImageDraw.Draw(blur)
        off = max(1, int(img.size[0] * 0.012))
        bd.text((x - eq_box[0] + off, y - dg_box[1] + off), "=", font=f_equals, fill=(0, 0, 0, 90))
        bd.text(
            (x + eq_w + gap - dg_box[0] + off, y - dg_box[1] + off),
            "10",
            font=f_digits,
            fill=(0, 0, 0, 90),
        )
        blur = blur.filter(ImageFilter.GaussianBlur(img.size[0] * 0.012))
        img.alpha_composite(blur)

    d = ImageDraw.Draw(img)
    # The equals sign sits on the digits' optical centre line, not its own.
    eq_h = eq_box[3] - eq_box[1]
    d.text((x - eq_box[0], y + (dg_h - eq_h) / 2 - eq_box[1]), "=", font=f_equals, fill=equals_colour)
    d.text((x + eq_w + gap - dg_box[0], y - dg_box[1]), "10", font=f_digits, fill=digits_colour)


def rounded_mask(size: int, radius_ratio: float) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=int(size * radius_ratio), fill=255
    )
    return mask


def circle_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    return mask


def legacy_icon(size: int, mask: Image.Image | None) -> Image.Image:
    img = gradient(size).convert("RGBA")
    # The mark occupies 62% of the square -- large enough to read at 48px,
    # small enough to keep a margin inside a circular launcher mask.
    inset = size * 0.19
    draw_mark(img, (inset, inset, size - inset, size - inset))
    if mask is not None:
        out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        out.paste(img, (0, 0), mask)
        return out
    return img


def adaptive_foreground(size: int) -> Image.Image:
    """108dp canvas; content must stay inside the central 66dp safe circle."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    safe = size * 66 / 108
    inset = (size - safe) / 2
    draw_mark(img, (inset, inset, size - inset, size - inset))
    return img


def monochrome_foreground(size: int) -> Image.Image:
    """Themed-icon layer: one flat colour, alpha carries the shape."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    safe = size * 66 / 108
    inset = (size - safe) / 2
    draw_mark(img, (inset, inset, size - inset, size - inset), WHITE, WHITE, shadow=False)
    return img


def feature_graphic() -> Image.Image:
    """1024x500 Play Store header."""
    w, h = 1024, 500
    img = gradient(max(w, h)).convert("RGBA").resize((w, h), Image.Resampling.BICUBIC)

    # A faint lattice of the four operators on the right, so the header says
    # "arithmetic" before any of the copy is read. Drawn on a regular grid --
    # a random scatter reads as noise at this opacity.
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ops = ["\uff0b", "\u2212", "\u00d7", "\u00f7"]
    f = font(58)
    step_x, step_y = 132, 118
    for row in range(5):
        for col in range(4):
            x = 600 + col * step_x + (step_x // 2 if row % 2 else 0)
            y = -30 + row * step_y
            d.text((x, y), ops[(row + col) % 4], font=f, fill=(255, 255, 255, 30), anchor="mm")
    img.alpha_composite(layer)

    draw_mark(img, (74, 96, 74 + 300, 96 + 190))

    d = ImageDraw.Draw(img)
    d.text((78, 322), "4つの数字で10をつくる", font=font(46), fill=WHITE)
    d.text((80, 392), "＋ − × ÷ の頭の体操 ・ 完全オフライン", font=font(30), fill=(206, 212, 245))
    return img


def store_icon() -> Image.Image:
    """512x512, opaque -- Play rejects transparency in the listing icon."""
    img = legacy_icon(512, None)
    flat = Image.new("RGB", (512, 512), INDIGO_DARK)
    flat.paste(img.convert("RGB"), (0, 0))
    return flat


def main() -> None:
    for density, factor in DENSITIES.items():
        out = RES / f"mipmap-{density}"
        out.mkdir(parents=True, exist_ok=True)

        legacy = int(48 * factor)
        legacy_icon(legacy, rounded_mask(legacy, 0.22)).save(out / "ic_launcher.png")
        legacy_icon(legacy, circle_mask(legacy)).save(out / "ic_launcher_round.png")

        adaptive = int(108 * factor)
        adaptive_foreground(adaptive).save(out / "ic_launcher_foreground.png")
        gradient(adaptive).convert("RGBA").save(out / "ic_launcher_background.png")
        monochrome_foreground(adaptive).save(out / "ic_launcher_monochrome.png")

    # The PWA build on GitHub Pages shares the artwork with the Android app.
    web_icons = ROOT / "web/icons"
    web_icons.mkdir(parents=True, exist_ok=True)
    for px in (192, 512):
        legacy_icon(px, None).convert("RGB").save(web_icons / f"Icon-{px}.png")
        # A maskable icon may be cropped to a circle inscribed in the middle
        # 80%, so it is drawn full-bleed with the mark pulled further in.
        maskable = gradient(px).convert("RGBA")
        inset = px * 0.28
        draw_mark(maskable, (inset, inset, px - inset, px - inset))
        maskable.convert("RGB").save(web_icons / f"Icon-maskable-{px}.png")
    legacy_icon(64, rounded_mask(64, 0.22)).save(ROOT / "web/favicon.png")

    STORE.mkdir(parents=True, exist_ok=True)
    store_icon().save(STORE / "icon-512.png")
    feature_graphic().convert("RGB").save(STORE / "feature-graphic-1024x500.png")
    print("icons and store art written")


if __name__ == "__main__":
    main()
