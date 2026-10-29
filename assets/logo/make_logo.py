#!/usr/bin/env python3
"""识途 App Logo 生成脚本。

设计：蓝色渐变底 + 一条白色蜿蜒路线（S 形，呼应「识途」拼音首字母 S）
从左下出发，途经两个蓝色途经点，终点是一个白色定位图钉。
与高德图标（蓝底白纸飞机）神似蓝白气质，但元素与构图完全不同。

用法：python3 assets/logo/make_logo.py
产出：
  - assets/logo/shitu_logo.png        1024×1024 母版（圆角、透明底）
  - Android legacy mipmap（48/72/96/144/192）
  - Android 自适应图标前景/单色层（108dp 各密度）+ 背景色资源 + anydpi 配置
  - iOS AppIcon.appiconset 全套
  - macOS AppIcon 全套
  - Windows app_icon.ico
"""
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SS = 4  # 超采样倍数，画完再缩小以获得平滑边缘

# 品牌蓝（渐变上浅下深）
BLUE_TOP = (43, 127, 255)     # #2B7FFF
BLUE_BOTTOM = (9, 78, 196)    # #094EC4
BLUE_SOLID = (22, 99, 217)    # #1663D9 自适应图标背景色 / 途经点填充
WHITE = (255, 255, 255)


def catmull_rom(points, samples_per_seg=48):
    """把控制点平滑成折线点列。"""
    pts = [points[0]] + points + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        for j in range(samples_per_seg):
            t = j / samples_per_seg
            t2, t3 = t * t, t * t * t
            out.append(tuple(
                0.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * t +
                       (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2 +
                       (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3)
                for k in (0, 1)))
    out.append(points[-1])
    return out


def point_at(polyline, frac):
    """取折线按弧长比例 frac 处的点。"""
    total = 0.0
    segs = []
    for a, b in zip(polyline, polyline[1:]):
        d = math.dist(a, b)
        segs.append(d)
        total += d
    target = total * frac
    acc = 0.0
    for (a, b), d in zip(zip(polyline, polyline[1:]), segs):
        if acc + d >= target and d > 0:
            t = (target - acc) / d
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        acc += d
    return polyline[-1]


# 路线控制点（相对坐标，S 形蜿蜒，左下 → 图钉针尖）
ROUTE_CTRL = [(0.21, 0.78), (0.38, 0.84), (0.52, 0.74), (0.43, 0.60),
              (0.38, 0.52), (0.49, 0.46), (0.615, 0.45)]
PIN_CENTER = (0.615, 0.295)
PIN_R = 0.118


def draw_foreground(draw, size, scale=1.0, cx=0.5, cy=0.5):
    """画白色路线 + 途经点 + 图钉。scale<1 时整体向中心收缩（自适应图标安全区）。"""
    def tf(p):
        return ((cx + (p[0] - 0.5) * scale) * size,
                (cy + (p[1] - 0.5) * scale) * size)

    route = [tf(p) for p in catmull_rom(ROUTE_CTRL)]
    line_w = max(2, int(0.082 * size * scale))
    # 沿路径盖圆点画粗线：避免 PIL line 的 joint 在密集采样点上产生毛刺。
    step = max(1.0, line_w / 16)
    acc = 0.0
    prev = route[0]
    half = line_w / 2
    draw.ellipse([prev[0] - half, prev[1] - half, prev[0] + half, prev[1] + half],
                 fill=WHITE)
    for p in route[1:]:
        acc += math.dist(prev, p)
        if acc >= step:
            draw.ellipse([p[0] - half, p[1] - half, p[0] + half, p[1] + half],
                         fill=WHITE)
            acc = 0.0
        prev = p
    end = route[-1]
    draw.ellipse([end[0] - half, end[1] - half, end[0] + half, end[1] + half],
                 fill=WHITE)
    # 起点：白圈蓝芯
    sx, sy = route[0]
    r0 = 0.040 * size * scale
    draw.ellipse([sx - r0, sy - r0, sx + r0, sy + r0], fill=WHITE)
    r1 = 0.018 * size * scale
    draw.ellipse([sx - r1, sy - r1, sx + r1, sy + r1], fill=BLUE_SOLID)
    # 两个途经点：蓝芯白环，压在路线上
    for frac in (0.38, 0.70):
        px, py = point_at(route, frac)
        rr = 0.050 * size * scale
        draw.ellipse([px - rr, py - rr, px + rr, py + rr], fill=BLUE_SOLID,
                     outline=WHITE, width=max(2, int(0.020 * size * scale)))
    # 终点图钉：白钉 + 蓝孔，针尖落在路线末端
    pcx, pcy = tf(PIN_CENTER)
    pr = PIN_R * size * scale
    tip = route[-1]
    draw.polygon([(pcx - pr * 0.74, pcy + pr * 0.52),
                  (pcx + pr * 0.74, pcy + pr * 0.52), tip], fill=WHITE)
    draw.ellipse([pcx - pr, pcy - pr, pcx + pr, pcy + pr], fill=WHITE)
    hr = 0.052 * size * scale
    draw.ellipse([pcx - hr, pcy - hr, pcx + hr, pcy + hr], fill=BLUE_SOLID)


def render(size, *, rounded=True, background=True, fg_scale=1.0):
    """渲染一张图标。rounded/background/fg_scale 组合出母版/全出血/前景层。"""
    big = size * SS
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    if background:
        # 竖向渐变
        grad = Image.new('RGB', (1, big))
        for y in range(big):
            t = y / (big - 1)
            grad.putpixel((0, y), tuple(
                int(BLUE_TOP[k] + (BLUE_BOTTOM[k] - BLUE_TOP[k]) * t)
                for k in range(3)))
        bg = grad.resize((big, big)).convert('RGBA')
        if rounded:
            mask = Image.new('L', (big, big), 0)
            md = ImageDraw.Draw(mask)
            radius = int(0.225 * big)
            md.rounded_rectangle([0, 0, big - 1, big - 1], radius, fill=255)
            img.paste(bg, (0, 0), mask)
        else:
            img.paste(bg, (0, 0))
    draw = ImageDraw.Draw(img)
    draw_foreground(draw, big, scale=fg_scale)
    return img.resize((size, size), Image.LANCZOS)


def save(img, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print('wrote', path.relative_to(ROOT))


def main():
    master = render(1024, rounded=True, background=True)
    save(master, ROOT / 'assets/logo/shitu_logo.png')
    full_bleed = render(1024, rounded=False, background=True)

    # Android legacy mipmap（母版圆角款）
    for name, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                     ('xxhdpi', 144), ('xxxhdpi', 192)]:
        save(master.resize((px, px), Image.LANCZOS),
             ROOT / f'android/app/src/main/res/mipmap-{name}/ic_launcher.png')
        save(master.resize((px, px), Image.LANCZOS),
             ROOT / f'android/app/src/main/res/mipmap-{name}/ic_launcher_round.png')
    # Android 自适应图标：前景（安全区收缩）+ 单色层（同图，白剪影）
    fg = render(1024, rounded=False, background=False, fg_scale=0.80)
    for name, px in [('mdpi', 108), ('hdpi', 162), ('xhdpi', 216),
                     ('xxhdpi', 324), ('xxxhdpi', 432)]:
        small = fg.resize((px, px), Image.LANCZOS)
        save(small, ROOT / f'android/app/src/main/res/mipmap-{name}/ic_launcher_foreground.png')
        save(small, ROOT / f'android/app/src/main/res/mipmap-{name}/ic_launcher_monochrome.png')
    res = ROOT / 'android/app/src/main/res'
    (res / 'values').mkdir(parents=True, exist_ok=True)
    (res / 'values/ic_launcher_background.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#1663D9</color>\n'
        '</resources>\n', encoding='utf-8')
    anydpi = res / 'mipmap-anydpi-v26'
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / 'ic_launcher.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
        '</adaptive-icon>\n', encoding='utf-8')
    print('wrote adaptive icon config')

    # iOS：按 Contents.json 的尺寸表逐个生成（全出血、无圆角无透明）
    iconset = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    contents = json.loads((iconset / 'Contents.json').read_text())
    for entry in contents['images']:
        size_pt = float(entry['size'].split('x')[0])
        scale = int(entry['scale'].rstrip('x'))
        px = int(size_pt * scale)
        save(full_bleed.resize((px, px), Image.LANCZOS),
             iconset / entry['filename'])

    # macOS：圆角母版各尺寸
    macset = ROOT / 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    for px in (16, 32, 64, 128, 256, 512, 1024):
        save(master.resize((px, px), Image.LANCZOS), macset / f'app_icon_{px}.png')

    # Windows ICO（多尺寸）
    ico_path = ROOT / 'windows/runner/resources/app_icon.ico'
    master.save(ico_path, format='ICO',
                sizes=[(s, s) for s in (16, 20, 24, 32, 48, 64, 128, 256)])
    print('wrote', ico_path.relative_to(ROOT))


if __name__ == '__main__':
    main()
