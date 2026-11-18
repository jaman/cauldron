#!/usr/bin/env python3
"""Draws Crossing's art and writes it into the example's priv/art.

    python3 book/make_crossing_art.py

Each sprite is a 32-pixel tile, or a strip of frames for the water. `atlas.txt` gives
each art its terminal glyph and colour. Run it after changing a shape; the game loads
what it writes, and `book/make_crossing_frame.exs` draws the book's figure from it.
"""

from PIL import Image, ImageDraw
import os
import random

T = 32
OUT = os.path.join(os.path.dirname(__file__), "..", "cauldron_examples", "games", "crossing", "priv", "art")

INK = (10, 8, 12, 255)


def canvas():
    return Image.new("RGBA", (T, T), (0, 0, 0, 0))


def outline(im, col=INK, width=2):
    for _ in range(width):
        px = im.load()
        w, h = im.size
        out = im.copy()
        o = out.load()
        for y in range(h):
            for x in range(w):
                if px[x, y][3] == 0 and any(
                    0 <= x + dx < w and 0 <= y + dy < h and px[x + dx, y + dy][3] > 40
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                ):
                    o[x, y] = col
        im = out
    return im


def grass(seed, flower):
    random.seed(seed)
    im = canvas()
    dd = ImageDraw.Draw(im)
    dd.rectangle([0, 0, T - 1, T - 1], fill=(28, 92, 44, 255))
    dd.rectangle([0, 0, T - 1, 2], fill=(48, 128, 62, 255))
    dd.rectangle([0, T - 4, T - 1, T - 1], fill=(18, 62, 30, 255))
    for _ in range(40):
        x, y = random.randrange(T), random.randrange(T)
        dd.point((x, y), fill=(40, 116, 54, 255) if random.random() < 0.5 else (64, 148, 76, 255))
    for _ in range(5):
        x, y = random.randrange(2, T - 4), random.randrange(4, T - 5)
        dd.line([(x, y + 3), (x, y)], fill=(84, 176, 92, 255))
        dd.line([(x + 1, y + 3), (x + 2, y)], fill=(70, 158, 80, 255))
    if flower:
        x, y = random.randrange(7, T - 9), random.randrange(7, T - 9)
        dd.ellipse([x - 1, y - 1, x + 1, y + 1], fill=(252, 240, 150, 255))
        dd.point((x, y), fill=(240, 120, 60, 255))
    return im


def water(frame):
    im = canvas()
    dd = ImageDraw.Draw(im)
    dd.rectangle([0, 0, T - 1, T - 1], fill=(10, 22, 60, 255))
    for band in range(3):
        y = 6 + band * 9
        x = (band * 9 + frame * 7) % 14
        dd.line([(x, y), (x + 11, y)], fill=(40, 92, 168, 255), width=2)
        dd.line([(x + 3, y + 2), (x + 13, y + 2)], fill=(24, 56, 118, 255))
        dd.point((x + 5, y - 1), fill=(140, 210, 255, 255))
    return im


def road():
    im = canvas()
    dd = ImageDraw.Draw(im)
    dd.rectangle([0, 0, T - 1, T - 1], fill=(18, 18, 24, 255))
    dd.rectangle([0, 0, T - 1, 1], fill=(38, 38, 50, 255))
    random.seed(4)
    for _ in range(26):
        x, y = random.randrange(T), random.randrange(T)
        dd.point((x, y), fill=(30, 30, 38, 255))
    dd.rectangle([3, 0, 10, 2], fill=(250, 210, 70, 255))
    dd.rectangle([16, 0, 23, 2], fill=(250, 210, 70, 255))
    dd.rectangle([29, 0, 31, 2], fill=(250, 210, 70, 255))
    return im


def log(kind):
    im = canvas()
    dd = ImageDraw.Draw(im)
    body, light, dark = (150, 96, 46, 255), (196, 140, 78, 255), (92, 56, 26, 255)
    dd.rectangle([0, 6, T - 1, 24], fill=body)
    dd.rectangle([0, 6, T - 1, 8], fill=light)
    dd.rectangle([0, 22, T - 1, 24], fill=dark)
    for y in (12, 17):
        dd.line([(0, y), (T - 1, y)], fill=(112, 68, 32, 255))
    if kind == "left":
        dd.ellipse([-8, 6, 8, 24], fill=light, outline=(70, 40, 18, 255), width=2)
        dd.ellipse([-3, 10, 4, 20], fill=body)
        dd.ellipse([-1, 13, 2, 17], fill=dark)
    if kind == "right":
        dd.ellipse([T - 9, 6, T + 7, 24], fill=light, outline=(70, 40, 18, 255), width=2)
        dd.ellipse([T - 5, 10, T + 2, 20], fill=body)
        dd.ellipse([T - 3, 13, T, 17], fill=dark)
    return outline(im, (30, 16, 6, 255), 2)


def car(side):
    im = canvas()
    dd = ImageDraw.Draw(im)
    red, light, dark = (226, 44, 44, 255), (255, 96, 88, 255), (150, 16, 28, 255)
    dd.rectangle([0, 8, T - 1, 24], fill=red)
    dd.rectangle([0, 8, T - 1, 10], fill=light)
    dd.rectangle([0, 22, T - 1, 24], fill=dark)
    if side == "left":
        dd.rectangle([10, 2, T + 2, 9], fill=light)
        dd.rectangle([13, 4, T - 1, 8], fill=(120, 220, 255, 255))
        dd.rectangle([13, 4, T - 1, 5], fill=(220, 250, 255, 255))
    else:
        dd.rectangle([-2, 2, T - 11, 9], fill=light)
        dd.rectangle([0, 4, T - 14, 8], fill=(120, 220, 255, 255))
        dd.rectangle([0, 4, T - 14, 5], fill=(220, 250, 255, 255))
    wheel(dd, 6 if side == "left" else T - 7, 26)
    return outline(im)


def wheel(dd, x, y):
    dd.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(12, 12, 16, 255))
    dd.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(90, 90, 108, 255))
    dd.ellipse([x - 1, y - 1, x + 1, y + 1], fill=(200, 200, 220, 255))


def cab():
    im = canvas()
    dd = ImageDraw.Draw(im)
    dd.rectangle([0, 6, T - 1, 24], fill=(30, 110, 200, 255))
    dd.rectangle([0, 6, T - 1, 8], fill=(80, 180, 245, 255))
    dd.rectangle([0, 22, T - 1, 24], fill=(16, 70, 140, 255))
    dd.rectangle([3, 9, T - 4, 16], fill=(150, 230, 255, 255))
    dd.rectangle([3, 9, T - 4, 10], fill=(220, 250, 255, 255))
    return im


def truck(side):
    im = cab()
    dd = ImageDraw.Draw(im)
    wheel(dd, 6 if side == "left" else T - 7, 26)
    return outline(im)


def cargo():
    im = canvas()
    dd = ImageDraw.Draw(im)
    dd.rectangle([0, 5, T - 1, 24], fill=(222, 160, 44, 255))
    dd.rectangle([0, 5, T - 1, 7], fill=(255, 206, 96, 255))
    dd.rectangle([0, 22, T - 1, 24], fill=(150, 98, 20, 255))
    for y in (10, 15, 20):
        dd.line([(0, y), (T - 1, y)], fill=(180, 120, 30, 255))
    return outline(im, (40, 24, 4, 255))


def bus(side):
    im = canvas()
    dd = ImageDraw.Draw(im)
    dd.rectangle([0, 4, T - 1, 26], fill=(40, 140, 200, 255))
    dd.rectangle([0, 4, T - 1, 6], fill=(110, 210, 250, 255))
    dd.rectangle([0, 24, T - 1, 26], fill=(20, 84, 130, 255))
    dd.rectangle([3, 8, T - 4, 16], fill=(170, 236, 255, 255))
    dd.rectangle([3, 8, T - 4, 9], fill=(230, 252, 255, 255))
    wheel(dd, 6 if side == "left" else T - 7, 28)
    return outline(im)


def bus_mid():
    im = canvas()
    dd = ImageDraw.Draw(im)
    dd.rectangle([0, 4, T - 1, 26], fill=(40, 140, 200, 255))
    dd.rectangle([0, 4, T - 1, 6], fill=(110, 210, 250, 255))
    dd.rectangle([0, 24, T - 1, 26], fill=(20, 84, 130, 255))
    for x in (2, 12, 22):
        dd.rectangle([x, 8, x + 7, 16], fill=(170, 236, 255, 255))
        dd.rectangle([x, 8, x + 7, 9], fill=(230, 252, 255, 255))
    return im


def frog(hop=False):
    im = canvas()
    dd = ImageDraw.Draw(im)
    green, light, dark = (60, 200, 80, 255), (130, 245, 140, 255), (20, 110, 40, 255)
    lift = -3 if hop else 0
    dd.ellipse([2, 18 + lift, 12, 30 + lift], fill=dark)
    dd.ellipse([T - 13, 18 + lift, T - 3, 30 + lift], fill=dark)
    dd.ellipse([5, 8 + lift, T - 6, 26 + lift], fill=green)
    dd.ellipse([9, 13 + lift, T - 10, 22 + lift], fill=(210, 250, 190, 255))
    dd.ellipse([5, 8 + lift, T - 6, 14 + lift], fill=light)
    for ex in (9, T - 10):
        dd.ellipse([ex - 4, 2 + lift, ex + 4, 10 + lift], fill=green)
        dd.ellipse([ex - 3, 3 + lift, ex + 3, 9 + lift], fill=(252, 255, 240, 255))
        dd.ellipse([ex - 2, 4 + lift, ex + 2, 8 + lift], fill=(8, 16, 8, 255))
        dd.point((ex + 1, 5 + lift), fill=(255, 255, 255, 255))
    dd.line([(13, 19 + lift), (T - 14, 19 + lift)], fill=dark)
    return outline(im, (4, 30, 12, 255), 2)


def pad():
    im = canvas()
    dd = ImageDraw.Draw(im)
    dd.rectangle([0, 0, T - 1, T - 1], fill=(10, 22, 60, 255))
    dd.ellipse([0, 1, T - 1, T - 2], fill=(40, 150, 90, 255), outline=(8, 40, 24, 255), width=2)
    dd.ellipse([4, 5, T - 5, T - 6], fill=(70, 190, 110, 255))
    dd.ellipse([11, 12, T - 12, T - 13], fill=(30, 110, 70, 255))
    dd.polygon([(16, 2), (19, 7), (13, 7)], fill=(10, 22, 60, 255))
    dd.ellipse([20, 6, 24, 10], fill=(255, 240, 140, 255))
    dd.point((22, 8), fill=(240, 120, 60, 255))
    return im


def shadow():
    im = canvas()
    ImageDraw.Draw(im).ellipse([3, 6, T - 4, T - 7], fill=(0, 0, 0, 90))
    return im


def strip(frames):
    im = Image.new("RGBA", (T * len(frames), T), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        im.alpha_composite(frame, (index * T, 0))
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    arts = {
        "grass_a": grass(1, True),
        "grass_b": grass(5, False),
        "grass_c": grass(9, True),
        "water_a": strip([water(0), water(1)]),
        "water_b": strip([water(1), water(0)]),
        "road": road(),
        "log_left": log("left"),
        "log_mid": log("mid"),
        "log_right": log("right"),
        "car_l": car("left"),
        "car_r": car("right"),
        "truck_l": truck("left"),
        "truck_mid": cargo(),
        "truck_r": truck("right"),
        "bus_l": bus("left"),
        "bus_mid": bus_mid(),
        "bus_r": bus("right"),
        "frog": frog(False),
        "frog_hop": frog(True),
        "bank": pad(),
        "shadow": shadow(),
    }
    for name, image in arts.items():
        image.save(os.path.join(OUT, f"{name}.png"))

    glyphs = {
        "grass_a": ("░░", "#1c5c2c"),
        "grass_b": ("░░", "#1c5c2c"),
        "grass_c": ("░░", "#1c5c2c"),
        "water_a": ("≈≈", "#0a163c"),
        "water_b": ("≈≈", "#0a163c"),
        "road": ("▓▓", "#121218"),
        "log_left": ("▬▬", "#966030"),
        "log_mid": ("▬▬", "#966030"),
        "log_right": ("▬▬", "#966030"),
        "car_l": ("▛▜", "#e22c2c"),
        "car_r": ("▛▜", "#e22c2c"),
        "truck_l": ("▛▜", "#1e6ec8"),
        "truck_mid": ("▛▜", "#dea02c"),
        "truck_r": ("▛▜", "#1e6ec8"),
        "bus_l": ("▛▜", "#288cc8"),
        "bus_mid": ("▛▜", "#288cc8"),
        "bus_r": ("▛▜", "#288cc8"),
        "frog": ("♞ ", "#3cc850"),
        "frog_hop": ("♞ ", "#3cc850"),
        "bank": ("○ ", "#28905a"),
        "shadow": ("  ", "#000000"),
    }

    lines = []
    for name in arts:
        glyph, colour = glyphs[name]
        fps = "3" if name.startswith("water") else ""
        lines.append("\t".join([name, glyph, colour, fps]))
    with open(os.path.join(OUT, "atlas.txt"), "w") as handle:
        handle.write("\n".join(lines) + "\n")

    print(f"wrote {len(arts)} arts to {os.path.normpath(OUT)}")


if __name__ == "__main__":
    main()
