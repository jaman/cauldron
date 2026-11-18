from PIL import Image
from collections import deque
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(ROOT, 'art_source')
OUT = os.path.join(ROOT, 'priv/art')

def resize_bg(name):
    im = Image.open(os.path.join(RAW, name + '.png')).convert('RGB')
    im = im.resize((1280, 720), Image.LANCZOS)
    im.save(os.path.join(OUT, name + '.png'), optimize=True)
    print('bg', name, im.size)

def is_bg(p):
    r, g, b = p[0], p[1], p[2]
    top = max(r, b)
    if top == 0:
        return False
    return b > g + 20 and r > g + 20 and (top - min(r, g, b)) > 0.45 * top

def keyed(name, out_name, box):
    im = Image.open(os.path.join(RAW, name + '.png')).convert('RGBA')
    w, h = im.size
    px = im.load()
    fg = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            fg[y * w + x] = 0 if is_bg(px[x, y]) else 1
    seen = bytearray(w * h)
    comps = []
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if fg[i] and not seen[i]:
                q = deque([(x, y)])
                seen[i] = 1
                cells = []
                border = False
                while q:
                    cx, cy = q.popleft()
                    cells.append((cx, cy))
                    if cx in (0, w - 1) or cy in (0, h - 1):
                        border = True
                    for nx, ny in ((cx-1, cy), (cx+1, cy), (cx, cy-1), (cx, cy+1)):
                        if 0 <= nx < w and 0 <= ny < h and fg[ny * w + nx] and not seen[ny * w + nx]:
                            seen[ny * w + nx] = 1
                            q.append((nx, ny))
                comps.append((len(cells), border, cells))
    comps.sort(key=lambda c: -c[0])
    keep = [c for c in comps if not c[1] and c[0] > 500] or [comps[0]]
    mask = bytearray(w * h)
    for _, _, cells in keep:
        for x, y in cells:
            mask[y * w + x] = 1
    # Outside the object, on the holes in the mask.
    outside = bytearray(w * h)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            i = y * w + x
            if mask[i] == 0 and not outside[i]:
                outside[i] = 1
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            i = y * w + x
            if mask[i] == 0 and not outside[i]:
                outside[i] = 1
                q.append((x, y))
    while q:
        cx, cy = q.popleft()
        for nx, ny in ((cx-1, cy), (cx+1, cy), (cx, cy-1), (cx, cy+1)):
            if 0 <= nx < w and 0 <= ny < h:
                i = ny * w + nx
                if mask[i] == 0 and not outside[i]:
                    outside[i] = 1
                    q.append((nx, ny))
    # An enclosed region is a real opening if it is magenta, or a bitten-out part of
    # the object if it is not; only the latter is filled back in.
    handled = bytearray(w * h)
    for y0 in range(h):
        for x0 in range(w):
            i0 = y0 * w + x0
            if mask[i0] == 0 and not outside[i0] and not handled[i0]:
                q = deque([(x0, y0)])
                handled[i0] = 1
                cells = []
                bgish = 0
                while q:
                    cx, cy = q.popleft()
                    cells.append((cx, cy))
                    if is_bg(px[cx, cy]):
                        bgish += 1
                    for nx, ny in ((cx-1, cy), (cx+1, cy), (cx, cy-1), (cx, cy+1)):
                        if 0 <= nx < w and 0 <= ny < h:
                            i = ny * w + nx
                            if mask[i] == 0 and not outside[i] and not handled[i]:
                                handled[i] = 1
                                q.append((nx, ny))
                if bgish * 2 < len(cells):
                    for cx, cy in cells:
                        mask[cy * w + cx] = 1
    alpha = Image.new('L', (w, h), 0)
    ap = alpha.load()
    for y in range(h):
        for x in range(w):
            if mask[y * w + x]:
                ap[x, y] = 255
    im.putalpha(alpha)
    bbox = im.getbbox()
    if not bbox:
        print('EMPTY', name)
        return
    im = im.crop(bbox)
    tw, th = box
    scale = min(tw / im.width, th / im.height)
    im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
    canvas = Image.new('RGBA', box, (0, 0, 0, 0))
    canvas.alpha_composite(im, ((tw - im.width) // 2, (th - im.height) // 2))
    canvas.save(os.path.join(OUT, out_name + '.png'), optimize=True)
    print('keyed', name, canvas.size, 'bbox', bbox)

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for name in ['bg_workshop', 'bg_garden', 'bg_cellar', 'bg_fair', 'bg_kiln']:
        if os.path.exists(os.path.join(RAW, name + '.png')):
            resize_bg(name)
    figs = {
        'fig_greenware': (180, 220), 'fig_cat': (120, 120), 'fig_green_man': (180, 240),
        'fig_boy': (150, 210), 'fig_choir': (160, 160), 'fig_potter': (180, 260),
    }
    for name, box in figs.items():
        if os.path.exists(os.path.join(RAW, name + '.png')):
            keyed(name, name, box)
    props = {
        'prop_cup': (144, 128), 'prop_bucket': (144, 128), 'prop_key': (120, 220),
        'prop_lamp': (192, 176), 'prop_plate': (240, 200), 'prop_doll': (128, 240),
        'prop_ferris': (440, 440), 'prop_mirror': (220, 280), 'prop_box': (240, 180),
        'prop_heart': (200, 200), 'prop_kiln': (320, 400), 'prop_door': (240, 360),
        'prop_well': (240, 192), 'prop_bird': (160, 120), 'prop_dam': (360, 220),
        'prop_arm': (240, 140), 'prop_chasm': (480, 220),
    }
    for name, box in props.items():
        if os.path.exists(os.path.join(RAW, name + '.png')):
            keyed(name, name, box)
        mended = name + "_mended"
        if os.path.exists(os.path.join(RAW, mended + '.png')):
            keyed(mended, mended, box)
