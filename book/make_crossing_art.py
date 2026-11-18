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


def mirror(im):
    return im.transpose(Image.FLIP_LEFT_RIGHT)


def wheel_at(dd, x, y):
    dd.rectangle([x - 3, y - 2, x + 3, y + 2], fill=(16, 16, 20, 255))


def draw_car(length=2):
    """A car from above, drawn whole: body, roof, glass at both ends, four wheels."""
    w, h = length * T, T
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dd = ImageDraw.Draw(im)
    body, roof = (196, 34, 40, 255), (240, 72, 72, 255)

    dd.rounded_rectangle([2, 5, w - 3, 27], radius=8, fill=(150, 16, 28, 255))
    dd.rounded_rectangle([4, 7, w - 5, 25], radius=7, fill=body)
    dd.rounded_rectangle([12, 9, w - 13, 23], radius=5, fill=roof)
    # windscreen at the front, rear window at the back
    dd.polygon([(w - 6, 10), (w - 18, 12), (w - 18, 20), (w - 6, 22)], fill=(120, 220, 255, 255))
    dd.line([(w - 6, 10), (w - 6, 22)], fill=(210, 250, 255, 255))
    dd.polygon([(6, 11), (16, 12), (16, 20), (6, 21)], fill=(96, 160, 200, 255))

    for y in (3, 29):
        wheel_at(dd, 12, y)
        wheel_at(dd, w - 13, y)

    for y in (6, 26):
        dd.rectangle([w - 5, y - 2, w - 2, y + 2], fill=(252, 236, 150, 255))
        dd.rectangle([2, y - 2, 5, y + 2], fill=(226, 60, 60, 255))

    return outline(im)


def draw_truck(length=3):
    """A truck from above: a cab at the front and a ribbed box behind it."""
    w, h = length * T, T
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dd = ImageDraw.Draw(im)
    amber, amber_light, amber_dark = (222, 160, 44, 255), (255, 206, 96, 255), (150, 98, 20, 255)

    cab = T
    dd.rounded_rectangle([2, 5, w - 3, 27], radius=6, fill=(120, 96, 58, 255))
    dd.rectangle([4, 7, w - cab - 4, 25], fill=(196, 186, 160, 255))
    dd.rectangle([6, 9, w - cab - 6, 23], fill=(214, 206, 182, 255))
    for x in range(14, w - cab - 8, 16):
        dd.rectangle([x, 7, x + 2, 25], fill=(150, 140, 116, 255))

    dd.rounded_rectangle([w - cab - 2, 5, w - 3, 27], radius=6, fill=(16, 70, 140, 255))
    dd.rounded_rectangle([w - cab, 7, w - 5, 25], radius=4, fill=(30, 110, 200, 255))
    dd.polygon([(w - 6, 11), (w - 15, 12), (w - 15, 20), (w - 6, 21)], fill=(150, 230, 255, 255))

    for y in (3, 29):
        wheel_at(dd, 12, y)
        wheel_at(dd, w - cab - 6, y)
        wheel_at(dd, w - 14, y)

    for y in (6, 26):
        dd.rectangle([w - 5, y - 2, w - 2, y + 2], fill=(252, 236, 150, 255))

    return outline(im, (40, 24, 4, 255))


def draw_bus(length=4):
    """A bus from above: a long roof with hatches, a windscreen and a door."""
    w, h = length * T, T
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dd = ImageDraw.Draw(im)
    body, light, dark = (40, 140, 200, 255), (110, 210, 250, 255), (20, 84, 130, 255)

    dd.rounded_rectangle([2, 4, w - 3, 28], radius=7, fill=dark)
    dd.rounded_rectangle([4, 6, w - 5, 26], radius=6, fill=body)
    dd.rectangle([8, 8, w - 9, 24], fill=light)
    dd.polygon([(w - 6, 9), (w - 16, 10), (w - 16, 22), (w - 6, 23)], fill=(170, 236, 255, 255))
    dd.line([(w - 6, 9), (w - 6, 23)], fill=(216, 248, 255, 255))
    dd.rectangle([8, 9, 12, 15], fill=(30, 90, 140, 255))

    for x in range(18, w - 20, 24):
        dd.rectangle([x, 10, x + 11, 22], fill=(190, 238, 255, 255))
        dd.rectangle([x + 2, 12, x + 9, 20], fill=(150, 214, 244, 255))

    for y in (3, 29):
        wheel_at(dd, 14, y)
        wheel_at(dd, w - 15, y)

    return outline(im)


def vehicle_parts(kind, length):
    """The parts of a vehicle, left to right, in both directions of travel."""
    whole = {"car": draw_car, "truck": draw_truck, "bus": draw_bus}[kind]
    image = whole(length)
    parts = [image.crop((i * T, 0, (i + 1) * T, T)) for i in range(length)]
    flipped = mirror(image)
    flipped_parts = [flipped.crop((i * T, 0, (i + 1) * T, T)) for i in range(length)]
    return parts, flipped_parts



def turtle(frame, submerged=False):
    """A turtle from above, or the shadow of one that has gone under."""
    im = canvas()
    dd = ImageDraw.Draw(im)
    if submerged:
        dd.ellipse([6, 9, T - 7, T - 8], fill=(16, 34, 70, 200))
        dd.ellipse([9, 12, T - 10, T - 11], fill=(10, 24, 54, 220))
        dd.arc([4, 7, T - 5, T - 6], 200, 340, fill=(60, 120, 190, 255), width=1)
        return im

    shell, light, dark = (86, 150, 74, 255), (128, 190, 104, 255), (44, 92, 44, 255)
    skin = (150, 190, 110, 255)

    # flippers, lifted on alternate frames
    offset = 2 if frame == 0 else -1
    for side in (-1, 1):
        x0, x1 = sorted([8 + side * 9, 8 + side * 13])
        y0, y1 = sorted([6 + offset * side, 12 + offset * side])
        dd.ellipse([x0, y0, x1, y1], fill=skin)
        y0, y1 = sorted([T - 12 - offset * side, T - 6 - offset * side])
        dd.ellipse([x0, y0, x1, y1], fill=skin)

    dd.ellipse([3, 6, T - 4, T - 7], fill=dark)
    dd.ellipse([5, 8, T - 6, T - 9], fill=shell)
    dd.ellipse([9, 11, T - 10, T - 12], fill=light)
    dd.ellipse([12, 14, T - 13, T - 15], fill=shell)
    # head
    dd.ellipse([T // 2 - 4, 1, T // 2 + 4, 8], fill=skin)
    dd.point((T // 2 - 2, 4), fill=(16, 24, 16, 255))
    dd.point((T // 2 + 2, 4), fill=(16, 24, 16, 255))
    return outline(im, (24, 52, 26, 255))


def snake(frame=0):
    """A snake from above: a looping body and a head with a tongue."""
    im = canvas()
    dd = ImageDraw.Draw(im)
    green, light, dark = (74, 176, 96, 255), (130, 220, 140, 255), (26, 96, 48, 255)

    # body: three loops
    for index, y in enumerate((8, 16, 24)):
        x0 = 4 + (index % 2) * 6
        dd.arc([x0 - 4, y - 7, x0 + 20, y + 7], 180, 360, fill=dark, width=6)
        dd.arc([x0 - 3, y - 6, x0 + 19, y + 6], 180, 360, fill=green, width=4)
        dd.arc([x0 - 1, y - 5, x0 + 17, y + 5], 180, 360, fill=light, width=1)

    # head
    hx, hy = T - 7 + (1 if frame else 0), 16
    dd.ellipse([hx - 5, hy - 4, hx + 5, hy + 4], fill=dark)
    dd.ellipse([hx - 4, hy - 3, hx + 4, hy + 3], fill=green)
    dd.point((hx - 1, hy - 2), fill=(250, 250, 230, 255))
    dd.point((hx + 2, hy - 2), fill=(250, 250, 230, 255))
    dd.line([(hx + 4, hy), (hx + 7, hy - 1)], fill=(226, 60, 60, 255))
    return outline(im, (18, 48, 24, 255), 1)


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
        "turtle_0": turtle(0),
        "turtle_1": turtle(1),
        "turtle_under": turtle(0, submerged=True),
        "snake_0": snake(0),
        "snake_1": snake(1),
        "frog": frog(False),
        "frog_hop": frog(True),
        "bank": pad(),
        "shadow": shadow(),
    }
    for kind, length in (("car", 2), ("truck", 3), ("bus", 4)):
        east, west = vehicle_parts(kind, length)
        for index, part in enumerate(east):
            arts[f"{kind}_{index}"] = part
        for index, part in enumerate(west):
            arts[f"{kind}_{index}_w"] = part

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

        "turtle_0": ("◍ ", "#6ab04a"),
        "turtle_1": ("◍ ", "#6ab04a"),
        "turtle_under": ("◌ ", "#16305a"),
        "snake_0": ("§ ", "#4ab060"),
        "snake_1": ("§ ", "#4ab060"),
        "frog": ("♞ ", "#3cc850"),
        "frog_hop": ("♞ ", "#3cc850"),
        "bank": ("○ ", "#28905a"),
        "shadow": ("  ", "#000000"),
    }

    for kind, colour in (("car", "#e22c2c"), ("truck", "#dea02c"), ("bus", "#288cc8")):
        for index in range(4):
            for suffix, glyph in (("", "▛▜"), ("_w", "▜▛")):
                name = f"{kind}_{index}{suffix}"
                if name in arts:
                    glyphs[name] = (glyph, colour)

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
