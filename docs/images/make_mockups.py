#!/usr/bin/env python3
"""识途界面样板图生成脚本（设计示意图，非真机截图）。

按已批准原型用 PIL 绘制三屏：主页地图 / 路线多方案 / 导航中。
用法：python3 docs/images/make_mockups.py
产出：docs/images/sample_home.png、sample_route.png、sample_navi.png
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent
SS = 2
W, H = 720, 1560

BLUE = (26, 115, 232)
DARK_BLUE = (23, 35, 59)
GREY = (123, 135, 148)
LIGHT_LINE = (238, 241, 244)

_font_cache = {}


def font(px, bold=False):
    key = (int(px), bold)
    if key not in _font_cache:
        name = 'NotoSansCJK-Bold.ttc' if bold else 'NotoSansCJK-Regular.ttc'
        path = f'/usr/share/fonts/opentype/noto/{name}'
        try:
            _font_cache[key] = ImageFont.truetype(path, key[0], index=2)
        except Exception:
            _font_cache[key] = ImageFont.truetype(path, key[0], index=0)
    return _font_cache[key]


def rr(d, box, rad, **kw):
    d.rounded_rectangle(box, radius=rad, **kw)


def txt(d, xy, s, px, color=(38, 48, 60), bold=False, anchor='la'):
    d.text(xy, s, font=font(px * SS, bold), fill=color, anchor=anchor)


def new_phone():
    img = Image.new('RGB', (W * SS, H * SS), (32, 36, 43))
    d = ImageDraw.Draw(img)
    rr(d, [10 * SS, 10 * SS, (W - 10) * SS, (H - 10) * SS], 56 * SS,
       fill=(233, 239, 228))
    return img, d


def clip_screen(img):
    mask = Image.new('L', img.size, 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([10 * SS, 10 * SS, (W - 10) * SS, (H - 10) * SS],
                         56 * SS, fill=255)
    out = Image.new('RGB', img.size, (32, 36, 43))
    out.paste(img, (0, 0), mask)
    return out


def draw_map(d, dark=False):
    bg = (20, 28, 41) if dark else (233, 239, 228)
    rr(d, [10 * SS, 10 * SS, (W - 10) * SS, (H - 10) * SS], 56 * SS, fill=bg)
    road = (38, 51, 74) if dark else (255, 255, 255)
    minor = (49, 67, 95) if dark else (246, 217, 138)
    for y in (300, 620, 940, 1240):
        d.line([(0, y * SS), (W * SS, y * SS)], fill=road, width=26 * SS)
    for x in (150, 380, 570):
        d.line([(x * SS, 0), (x * SS, H * SS)], fill=road, width=26 * SS)
    d.line([(0, 620 * SS), (W * SS, 620 * SS)], fill=minor, width=10 * SS)
    d.line([(380 * SS, 0), (380 * SS, H * SS)], fill=minor, width=10 * SS)
    if not dark:
        rr(d, [420 * SS, 130 * SS, 640 * SS, 250 * SS], 18 * SS,
           fill=(207, 229, 192))
        d.polygon([(0, 1330 * SS), (240 * SS, 1280 * SS), (520 * SS, 1380 * SS),
                   (W * SS, 1340 * SS), (W * SS, H * SS), (0, H * SS)],
                  fill=(188, 217, 245))


def status_bar(d, dark=False):
    c = (219, 230, 242) if dark else (38, 48, 60)
    txt(d, (52 * SS, 34 * SS), '9:41', 26, c, bold=True)
    txt(d, ((W - 52) * SS, 34 * SS), '5G', 26, c, bold=True, anchor='ra')


def search_pill(d):
    rr(d, [34 * SS, 84 * SS, (W - 34) * SS, 168 * SS], 42 * SS,
       fill=(255, 255, 255))
    cx, cy = 84 * SS, 126 * SS
    d.ellipse([cx - 17 * SS, cy - 17 * SS, cx + 17 * SS, cy + 17 * SS],
              outline=(91, 107, 125), width=5 * SS)
    d.line([(cx + 13 * SS, cy + 13 * SS), (cx + 27 * SS, cy + 27 * SS)],
           fill=(91, 107, 125), width=5 * SS)
    txt(d, (126 * SS, 126 * SS), '搜索地点 / 地址', 32, (138, 149, 163),
        anchor='lm')
    txt(d, ((W - 66) * SS, 126 * SS), '设置', 28, (91, 107, 125), anchor='rm')


def home():
    img, d = new_phone()
    draw_map(d)
    status_bar(d)
    search_pill(d)
    # 数据源芯片
    rr(d, [34 * SS, 188 * SS, 168 * SS, 240 * SS], 26 * SS, fill=BLUE)
    txt(d, (94 * SS, 214 * SS), '高德', 27, (255, 255, 255), bold=True,
        anchor='mm')
    d.polygon([(134 * SS, 206 * SS), (150 * SS, 206 * SS), (142 * SS, 219 * SS)],
              fill=(255, 255, 255))
    rr(d, [180 * SS, 188 * SS, 300 * SS, 240 * SS], 26 * SS,
       fill=(255, 255, 255))
    txt(d, (240 * SS, 214 * SS), '路况 开', 27, (60, 71, 84), anchor='mm')
    # 右侧控件
    for i, label in enumerate(['▦', '+', '−']):
        y = 420 + i * 104
        rr(d, [(W - 118) * SS, y * SS, (W - 34) * SS, (y + 84) * SS], 20 * SS,
           fill=(255, 255, 255))
        txt(d, ((W - 76) * SS, (y + 42) * SS), label, 40, (64, 80, 106),
            anchor='mm')
    # 定位蓝点
    cx, cy = 300 * SS, 700 * SS
    d.ellipse([cx - 34 * SS, cy - 34 * SS, cx + 34 * SS, cy + 34 * SS],
              fill=(26, 115, 232, 60))
    d.ellipse([cx - 17 * SS, cy - 17 * SS, cx + 17 * SS, cy + 17 * SS],
              fill=BLUE, outline=(255, 255, 255), width=6 * SS)
    # 底部面板
    rr(d, [10 * SS, 1090 * SS, (W - 10) * SS, (H - 10) * SS], 56 * SS,
       fill=(255, 255, 255))
    d.rectangle([10 * SS, 1090 * SS, (W - 10) * SS, 1180 * SS],
                fill=(255, 255, 255))
    rr(d, [330 * SS, 1112 * SS, 390 * SS, 1122 * SS], 5 * SS,
       fill=(213, 219, 226))
    for i, name in enumerate(['家', '公司', '收藏', '离线']):
        x = 44 + i * 164
        rr(d, [x * SS, 1150 * SS, (x + 140) * SS, 1250 * SS], 24 * SS,
           fill=(240, 244, 249))
        cx, cy = (x + 70) * SS, 1184 * SS
        if i == 0:  # 家：小屋轮廓
            d.polygon([(cx - 20 * SS, cy - 2 * SS), (cx, cy - 20 * SS),
                       (cx + 20 * SS, cy - 2 * SS)], outline=BLUE,
                      width=4 * SS)
            d.rectangle([cx - 13 * SS, cy - 2 * SS, cx + 13 * SS,
                         cy + 16 * SS], outline=BLUE, width=4 * SS)
        elif i == 1:  # 公司：楼宇
            d.rectangle([cx - 13 * SS, cy - 18 * SS, cx + 13 * SS,
                         cy + 16 * SS], outline=BLUE, width=4 * SS)
            for wy in (-8, 2):
                d.line([(cx - 6 * SS, (cy + wy * SS)), (cx + 6 * SS,
                        (cy + wy * SS))], fill=BLUE, width=3 * SS)
        elif i == 2:  # 收藏：星
            txt(d, (cx, cy), '★', 36, BLUE, anchor='mm')
        else:  # 离线：下载箭头
            d.line([(cx, cy - 18 * SS), (cx, cy + 6 * SS)], fill=BLUE,
                   width=5 * SS)
            d.polygon([(cx - 10 * SS, cy - 2 * SS), (cx + 10 * SS, cy - 2 * SS),
                       (cx, cy + 12 * SS)], fill=BLUE)
            d.line([(cx - 18 * SS, cy + 17 * SS), (cx + 18 * SS, cy + 17 * SS)],
                   fill=BLUE, width=4 * SS)
        txt(d, ((x + 70) * SS, 1224 * SS), name, 26, (51, 65, 92),
            anchor='mm')
    for i, (name, sub) in enumerate([('深圳北站', '龙华区 · 距你 6.2 km'),
                                     ('万象城', '罗湖区 · 昨天去过')]):
        y = 1300 + i * 118
        d.ellipse([52 * SS, y * SS, 104 * SS, (y + 52) * SS],
                  fill=(232, 240, 254))
        txt(d, (78 * SS, (y + 26) * SS), '地' if i == 0 else '史', 24, BLUE,
            anchor='mm')
        txt(d, (128 * SS, (y + 4) * SS), name, 30, (38, 48, 60), bold=True)
        txt(d, (128 * SS, (y + 46) * SS), sub, 24, GREY)
    return clip_screen(img)


def route():
    img, d = new_phone()
    draw_map(d)
    status_bar(d)
    # 起终点卡
    rr(d, [34 * SS, 84 * SS, (W - 34) * SS, 350 * SS], 32 * SS,
       fill=(255, 255, 255))
    d.ellipse([66 * SS, 128 * SS, 84 * SS, 146 * SS], fill=(52, 168, 83))
    txt(d, (104 * SS, 118 * SS), '我的位置', 30, (38, 48, 60), bold=True)
    txt(d, (104 * SS, 156 * SS), '科技园南区', 24, GREY)
    d.rectangle([66 * SS, 208 * SS, 84 * SS, 226 * SS], fill=(232, 69, 60))
    txt(d, (104 * SS, 196 * SS), '万象城（罗湖店）', 30, (38, 48, 60),
        bold=True)
    txt(d, (104 * SS, 234 * SS), '宝安南路 1881 号', 24, GREY)
    rr(d, [66 * SS, 268 * SS, (W - 66) * SS, 326 * SS], 20 * SS,
       fill=(238, 241, 245))
    for i, name in enumerate(['驾车', '公交', '步行', '骑行']):
        x = 66 + i * 147
        if i == 0:
            rr(d, [x * SS, 274 * SS, (x + 135) * SS, 320 * SS], 16 * SS,
               fill=(255, 255, 255))
        txt(d, ((x + 68) * SS, 297 * SS), name, 27,
            BLUE if i == 0 else (91, 107, 125), bold=(i == 0), anchor='mm')
    # 双路线
    alt = [(110, 1330), (110, 1080), (210, 980), (330, 880), (430, 800),
           (520, 560)]
    main = [(110, 1330), (190, 1150), (150, 950), (300, 830), (430, 760),
            (520, 560)]
    for pts, color, wdt in ((alt, (185, 194, 204), 13), (main, BLUE, 13)):
        xy = [(x * SS, y * SS) for x, y in pts]
        d.line(xy, fill=color, width=wdt * SS, joint='curve')
    d.ellipse([92 * SS, 1312 * SS, 128 * SS, 1348 * SS], fill=(52, 168, 83),
              outline=(255, 255, 255), width=5 * SS)
    d.ellipse([502 * SS, 542 * SS, 538 * SS, 578 * SS], fill=(232, 69, 60),
              outline=(255, 255, 255), width=5 * SS)
    rr(d, [250 * SS, 700 * SS, 420 * SS, 756 * SS], 20 * SS,
       fill=(255, 255, 255))
    txt(d, (335 * SS, 728 * SS), '38 分钟', 27, BLUE, bold=True, anchor='mm')
    # 底部方案区
    rr(d, [10 * SS, 1010 * SS, (W - 10) * SS, (H - 10) * SS], 56 * SS,
       fill=(255, 255, 255))
    d.rectangle([10 * SS, 1010 * SS, (W - 10) * SS, 1100 * SS],
                fill=(255, 255, 255))
    rr(d, [330 * SS, 1032 * SS, 390 * SS, 1042 * SS], 5 * SS,
       fill=(213, 219, 226))
    txt(d, (44 * SS, 1078 * SS), '数据源', 25, GREY)
    rr(d, [150 * SS, 1058 * SS, 320 * SS, 1110 * SS], 24 * SS, fill=BLUE)
    txt(d, (228 * SS, 1084 * SS), '高德算路', 25, (255, 255, 255),
        bold=True, anchor='mm')
    d.polygon([(288 * SS, 1077 * SS), (302 * SS, 1077 * SS),
               (295 * SS, 1088 * SS)], fill=(255, 255, 255))
    rr(d, [44 * SS, 1140 * SS, (W - 44) * SS, 1290 * SS], 26 * SS,
       outline=BLUE, width=3 * SS, fill=(244, 249, 255))
    txt(d, (72 * SS, 1170 * SS), '38 分钟 · 12.4 km', 33, DARK_BLUE, bold=True)
    rr(d, [520 * SS, 1162 * SS, 640 * SS, 1210 * SS], 16 * SS, fill=BLUE)
    txt(d, (580 * SS, 1186 * SS), '推荐', 24, (255, 255, 255), bold=True,
        anchor='mm')
    txt(d, (72 * SS, 1224 * SS), '躲避拥堵 · 红绿灯 9 个 · 过路费 ¥5', 25, GREY)
    rr(d, [44 * SS, 1314 * SS, (W - 44) * SS, 1436 * SS], 26 * SS,
       outline=(227, 232, 238), width=3 * SS)
    txt(d, (72 * SS, 1344 * SS), '45 分钟 · 13.1 km', 33, DARK_BLUE, bold=True)
    txt(d, (72 * SS, 1396 * SS), '少收费 · 红绿灯 14 个 · 过路费 ¥0', 25, GREY)
    rr(d, [44 * SS, 1462 * SS, 500 * SS, (H - 36) * SS], 26 * SS, fill=BLUE)
    txt(d, (272 * SS, 1500 * SS), '开始导航', 32, (255, 255, 255), bold=True,
        anchor='mm')
    rr(d, [516 * SS, 1462 * SS, (W - 44) * SS, (H - 36) * SS], 26 * SS,
       fill=(240, 244, 249))
    txt(d, ((W - 44 - 80) * SS, 1500 * SS), '模拟', 30, (51, 65, 92),
        anchor='mm')
    return clip_screen(img)


def navi():
    img, d = new_phone()
    draw_map(d, dark=True)
    status_bar(d, dark=True)
    # 路线（深色图）
    pts = [(140, 1420), (140, 1180), (260, 1020), (330, 860), (390, 700),
           (398, 300)]
    d.line([(x * SS, y * SS) for x, y in pts], fill=(59, 130, 246),
           width=14 * SS, joint='curve')
    pts2 = [(330, 860), (390, 700), (398, 300)]
    d.line([(x * SS, y * SS) for x, y in pts2], fill=(245, 158, 11),
           width=14 * SS, joint='curve')
    # 指引横幅
    rr(d, [30 * SS, 84 * SS, (W - 30) * SS, 262 * SS], 34 * SS,
       fill=(13, 92, 70))
    ax, ay = 118 * SS, 173 * SS
    d.line([(ax, ay + 52 * SS), (ax, ay - 10 * SS)], fill=(255, 255, 255),
           width=13 * SS)
    d.line([(ax, ay - 10 * SS), (ax + 48 * SS, ay - 10 * SS)],
           fill=(255, 255, 255), width=13 * SS)
    d.polygon([(ax + 34 * SS, ay - 30 * SS), (ax + 34 * SS, ay + 10 * SS),
               (ax + 76 * SS, ay - 10 * SS)], fill=(255, 255, 255))
    txt(d, (220 * SS, 118 * SS), '300 米', 62, (255, 255, 255), bold=True)
    txt(d, (220 * SS, 192 * SS), '右转 进入深南大道', 33, (201, 236, 223))
    # 拥堵提示条
    rr(d, [30 * SS, 286 * SS, (W - 30) * SS, 356 * SS], 24 * SS,
       fill=(253, 243, 215))
    txt(d, (56 * SS, 321 * SS), '拥堵  前方 2 km 缓行，已重新规划', 26,
        (122, 91, 0), anchor='lm')
    rr(d, [560 * SS, 300 * SS, 668 * SS, 342 * SS], 14 * SS, fill=(245, 197, 66))
    txt(d, (614 * SS, 321 * SS), '接受', 24, (77, 58, 0), bold=True,
        anchor='mm')
    # 速度气泡
    cx, cy = 108 * SS, 560 * SS
    d.ellipse([cx - 62 * SS, cy - 62 * SS, cx + 62 * SS, cy + 62 * SS],
              fill=(255, 255, 255), outline=(232, 69, 60), width=7 * SS)
    txt(d, (cx, cy - 14 * SS), '65', 44, DARK_BLUE, bold=True, anchor='mm')
    txt(d, (cx, cy + 28 * SS), '限速 60', 20, GREY, anchor='mm')
    # 底部信息条
    rr(d, [10 * SS, 1300 * SS, (W - 10) * SS, (H - 10) * SS], 56 * SS,
       fill=(16, 24, 38))
    txt(d, (44 * SS, 1340 * SS), '剩余 22 分钟 · 8.6 km · 预计 18:42 到达', 29,
        (219, 230, 242))
    for i, (label, color) in enumerate([('总览', (219, 230, 242)),
                                        ('语音 · 英伟达', (219, 230, 242)),
                                        ('退出导航', (255, 180, 171))]):
        x = 44 + i * 218
        rr(d, [x * SS, 1400 * SS, (x + 200) * SS, 1496 * SS], 22 * SS,
           fill=(31, 44, 63) if i < 2 else (92, 35, 32))
        txt(d, ((x + 100) * SS, 1448 * SS), label, 27, color, anchor='mm')
    return clip_screen(img)


if __name__ == '__main__':
    for name, fn in [('sample_home.png', home), ('sample_route.png', route),
                     ('sample_navi.png', navi)]:
        out = fn().resize((W, H), Image.LANCZOS)
        out.save(OUT / name)
        print('wrote', name)
