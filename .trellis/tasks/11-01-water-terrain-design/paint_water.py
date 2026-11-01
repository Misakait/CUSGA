from pathlib import Path
from collections import deque
import base64
import hashlib
import json
import math
import re
import struct
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
TASK = Path(__file__).parent
OUT = TASK / 'research'
BEFORE = OUT / 'before'
BEFORE.mkdir(exist_ok=True)
W, H, TILE = 80, 45, 16
REF = (OUT / 'coral_shoal.before.tscn').read_text(encoding='utf-8')
ATLAS_PATH = 'res/UI/生态图集/水-生态/水-生态.png'
ATLAS = Image.open(ROOT / ATLAS_PATH).convert('RGBA')
DECOR_DIR = ROOT / 'res/UI/生态图集/水-生态/装饰物'
DECORS = {int(p.name[:2]): p for p in DECOR_DIR.glob('*.png')}
BLOCK_RE = r'^\[(?:sub_resource|node|ext_resource)[^\n]*\]\n(?:(?!^\[).|\n)*'


def blocks(text, kind):
    return re.findall(r'^\[' + kind + r'[^\n]*\]\n(?:(?!^\[).|\n)*', text, re.M)


def node_path(block):
    header = block.splitlines()[0]
    name = re.search(r'name="([^"]+)"', header)[1]
    parent = re.search(r'parent="([^"]+)"', header)
    return (parent[1] + '/' if parent and parent[1] != '.' else '') + name


REF_SUBS = {re.search(r'id="([^"]+)"', b)[1]: b for b in blocks(REF, 'sub_resource')}
REF_LAYERS = {node_path(b): b for b in blocks(REF, 'node') if 'type="TileMapLayer"' in b.splitlines()[0]}


def field(predicate):
    return {(x, y) for y in range(-1, H + 2) for x in range(-1, W + 2) if predicate(x, y)}


def rect(x0, y0, x1, y1):
    return field(lambda x, y: x0 <= x <= x1 and y0 <= y <= y1)


def ellipse(cx, cy, rx, ry):
    return field(lambda x, y: ((x-cx)/rx)**2 + ((y-cy)/ry)**2 <= 1)


def polygon(points):
    def inside(x, y):
        odd = False
        for (ax, ay), (bx, by) in zip(points, points[1:] + points[:1]):
            if (ay > y) != (by > y) and x < (bx-ax)*(y-ay)/(by-ay)+ax:
                odd = not odd
        return odd
    return field(inside)


def stroke(points, radius):
    def distance(x, y, a, b):
        vx, vy = b[0]-a[0], b[1]-a[1]
        t = max(0, min(1, ((x-a[0])*vx+(y-a[1])*vy)/(vx*vx+vy*vy)))
        return math.hypot(x-a[0]-t*vx, y-a[1]-t*vy)
    return field(lambda x, y: min(distance(x, y, a, b) for a, b in zip(points, points[1:])) <= radius)


def erode(vertices, distance=1):
    # 先把材质缩进岸线，再取角点掩码，避免第二层的透明像素漏出岛外。
    return {p for p in vertices if all((p[0]+dx, p[1]+dy) in vertices for dx, dy in
            [(-distance, 0), (distance, 0), (0, -distance), (0, distance)])}


def masks(vertices):
    # 原图列号按左上、右上、左下、右下的 8/4/2/1 位排列。
    return {(x, y): m for y in range(H) for x in range(W)
            if (m := (8*((x, y) in vertices) + 4*((x+1, y) in vertices)
                      + 2*((x, y+1) in vertices) + ((x+1, y+1) in vertices)))}


def tiles(vertices, row):
    return {p: (mask, row) for p, mask in masks(vertices).items()}


def encode(cells):
    data = b'\0\0' + b''.join(struct.pack('<hhHHHH', x, y, 0, col, row, 0)
                             for (x, y), (col, row) in sorted(cells.items(), key=lambda c: (c[0][1], c[0][0])))
    return base64.b64encode(data).decode('ascii')


def replace_property(block, key, value):
    pattern = r'^' + re.escape(key) + r' = .*\n'
    if re.search(pattern, block, re.M):
        return re.sub(pattern, lambda _: key + ' = ' + value + '\n', block, flags=re.M)
    return block.rstrip() + '\n' + key + ' = ' + value + '\n\n'


PORTS = [rect(37, -1, 43, 7), rect(73, 19, 81, 26), rect(37, 38, 43, 46), rect(-1, 19, 7, 26)]
LAND_PORTS = rect(37, 3, 43, 10) | rect(37, 35, 43, 42) | rect(3, 19, 12, 26) | rect(68, 19, 77, 26)
DIRECTIONS = ['Up', 'Right', 'Down', 'Left']
SAFE = rect(23, 13, 57, 36)


def designs():
    return {
        'coral_shoal': dict(title='珊瑚浅滩', row=1,
            outline=[(4,19),(9,15),(8,10),(15,5),(25,4),(32,7),(38,3),(47,4),(53,7),(65,5),(72,10),(70,16),(77,20),(77,26),(70,29),(72,35),(65,40),(52,41),(45,38),(37,42),(26,39),(13,40),(7,34),(9,29),(3,26)],
            holes=[ellipse(18,10,5,2), ellipse(63,34,4,2)],
            patches=[(2, ellipse(24,22,18,12) | ellipse(58,21,13,10)),
                     (3, stroke([(14,16),(20,17),(23,21),(22,27),(28,31),(37,31)],2.4) | ellipse(58,13,7,3)),
                     (0, ellipse(53,28,7,3) | ellipse(31,10,4,2))],
            palette=[12,13,8,5,4,17], specials=[(13,15,32),(12,17,33),(4,62,22),(8,65,26)]),
        'crystal_river': dict(title='水晶河流', row=0,
            outline=[(5,18),(11,15),(10,7),(20,4),(29,6),(35,4),(44,3),(50,6),(66,4),(72,9),(69,16),(77,19),(77,27),(69,29),(71,37),(61,41),(50,38),(42,42),(33,40),(23,42),(12,37),(10,29),(3,26)],
            holes=[ellipse(14,10,3,2), ellipse(64,36,4,2)],
            patches=[(3, stroke([(27,5),(25,10),(31,15),(46,19),(49,24),(43,30),(47,34),(56,40)],3.5)),
                     (5, stroke([(25,9),(30,14),(46,19),(48,24),(43,30),(47,34)],1.0)),
                     (2, ellipse(17,25,7,7) | ellipse(62,17,7,5))],
            palette=[18,17,5,7,15,12], specials=[(18,29,11),(18,53,29),(7,43,20),(17,46,29)]),
        'deep_sea_rift': dict(title='深海裂谷', row=6,
            outline=[(4,19),(9,17),(8,11),(15,8),(24,4),(32,6),(38,3),(44,4),(51,8),(63,5),(72,8),(70,15),(76,19),(77,26),(72,28),(74,34),(66,38),(57,41),(48,38),(42,42),(33,39),(23,41),(17,37),(8,38),(7,31),(3,26)],
            holes=[stroke([(24,5),(28,8),(31,10)],1.3),stroke([(58,40),(61,37),(65,34)],1.4)],
            patches=[(7, stroke([(29,7),(35,12),(36,18),(43,23),(46,30),(54,34),(60,38)],4.2)),
                     (5, stroke([(28,9),(32,13),(32,19),(38,23),(41,31),(49,35)],1.2)),
                     (4, ellipse(16,27,7,5) | ellipse(65,16,5,4))],
            palette=[4,9,15,16,5], specials=[(16,42,25),(9,51,32),(4,21,16),(15,34,16)]),
        'frozen_lake': dict(title='封冻冰湖', row=0,
            outline=[(3,19),(8,18),(8,11),(14,7),(23,7),(27,3),(38,3),(45,4),(49,7),(65,6),(72,12),(72,18),(77,19),(77,26),(71,28),(70,35),(62,40),(50,40),(44,42),(35,41),(27,38),(15,40),(8,33),(8,28),(3,26)],
            holes=[ellipse(20,10,4,1.5),ellipse(62,36,6,1.4)],
            patches=[(3, polygon([(13,16),(23,13),(30,17),(37,14),(47,15),(57,12),(66,16),(63,26),(56,31),(47,30),(39,33),(28,29),(20,31),(14,25)])),
                     (0, polygon([(25,18),(34,17),(39,20),(46,18),(54,19),(58,24),(51,27),(41,26),(34,29),(26,25)])),
                     (5, stroke([(20,20),(30,22),(35,25)],0.7) | stroke([(52,13),(49,20),(54,24),(51,29)],0.7))],
            palette=[18,18,5,12,17], specials=[(18,17,14),(18,62,28),(18,57,34),(17,40,31)]),
        'waterfall_cave': dict(title='瀑布洞穴', row=4,
            outline=[(3,19),(8,19),(6,12),(12,7),(20,4),(31,5),(37,3),(44,3),(48,5),(61,4),(68,8),(74,13),(72,19),(77,19),(77,26),(71,29),(72,35),(63,40),(51,39),(43,42),(34,40),(24,41),(13,38),(7,32),(8,27),(3,26)],
            holes=[ellipse(15,10,5,2),ellipse(63,9,5,2)],
            patches=[(8, stroke([(11,15),(14,24),(13,31),(20,35)],2) | stroke([(68,14),(64,23),(68,32)],2)),
                     (7, ellipse(40,26,17,10) | rect(33,7,47,18)),
                     (3, rect(35,7,45,15) | ellipse(40,17,9,3) | ellipse(40,25,12,5)),
                     (5, rect(38,8,42,16) | stroke([(34,24),(37,22),(44,22),(47,25)],0.9))],
            palette=[5,4,15,17,2], specials=[(15,38,15),(15,42,17),(17,40,26),(2,21,32)]),
        'abyss_sea_market': dict(title='深渊海集', row=1,
            outline=[(7,9),(24,9),(24,5),(36,5),(38,3),(43,3),(45,5),(58,5),(58,9),(73,9),(73,19),(77,19),(77,26),(73,26),(73,37),(57,37),(57,40),(44,40),(43,42),(37,42),(36,40),(23,40),(23,37),(7,37),(7,26),(3,26),(3,19),(7,19)],
            holes=[rect(10,12,16,15),rect(64,31,69,34)],
            patches=[(4, rect(18,12,62,34) | rect(10,19,70,26)),
                     (6, rect(22,15,58,31)),
                     (1, rect(26,18,54,28) | rect(37,11,43,35)),
                     (3, rect(10,30,19,34) | rect(61,12,69,16))],
            palette=[12,14,5,8,13], specials=[(14,13,17),(14,66,28),(6,20,17),(6,59,30),(12,31,15),(13,49,32)]),
        'crystal_shoal': dict(title='水晶浅滩', row=0,
            outline=[(3,19),(10,17),(13,11),(24,8),(30,4),(38,3),(44,3),(49,8),(60,6),(67,12),(69,17),(77,19),(77,26),(69,28),(65,35),(54,38),(44,42),(37,42),(31,38),(18,38),(12,33),(9,28),(3,26)],
            holes=[ellipse(20,11,3,1.2),ellipse(60,34,3,1.2)],
            patches=[(3, polygon([(13,21),(25,16),(33,12),(41,16),(49,12),(64,19),(59,25),(49,30),(40,34),(31,29),(21,30)])),
                     (2, ellipse(28,24,6,4) | ellipse(53,22,6,5)),
                     (0, stroke([(18,23),(29,21),(39,23),(50,20),(61,22)],1.6))],
            palette=[18,12,15,5,17], specials=[(18,26,14),(18,53,29),(18,57,15),(15,42,30)]),
        'deep_sea_undercurrent': dict(title='深海暗流', row=6,
            outline=[(3,19),(10,16),(8,10),(17,5),(28,5),(34,8),(38,3),(44,3),(49,8),(61,6),(70,10),(68,17),(77,19),(77,26),(71,29),(73,35),(64,40),(51,39),(43,42),(37,42),(29,38),(18,40),(8,35),(9,28),(3,26)],
            holes=[ellipse(18,10,5,2),ellipse(63,35,5,2)],
            patches=[(7, stroke([(14,17),(24,14),(34,17),(43,25),(53,29),(64,27)],4.3)),
                     (5, stroke([(15,20),(23,18),(31,21),(42,28),(52,32),(63,30)],1.2)),
                     (3, ellipse(26,16,4,3) | ellipse(53,28,5,3))],
            palette=[4,4,9,15,16], specials=[(16,25,16),(16,54,28),(9,33,20),(4,18,30),(4,63,16)]),
        'frozen_lake_shore': dict(title='冰湖岸边', row=0,
            outline=[(3,19),(9,17),(9,11),(17,11),(17,6),(29,6),(29,4),(38,3),(44,3),(49,6),(62,6),(62,10),(70,10),(70,18),(77,19),(77,26),(69,28),(69,34),(60,34),(60,39),(48,39),(43,42),(37,42),(31,39),(19,39),(19,35),(10,35),(10,28),(3,26)],
            holes=[rect(12,13,18,16),rect(61,29,66,32)],
            patches=[(5, polygon([(12,19),(20,16),(31,18),(38,14),(49,17),(61,14),(66,21),(63,28),(53,30),(46,34),(34,32),(25,35),(15,29)])),
                     (3, stroke([(18,22),(29,21),(35,24),(46,24),(57,20),(63,24)],2.6)),
                     (0, polygon([(27,17),(36,18),(40,21),(50,20),(53,25),(47,29),(38,27),(31,29),(27,24)]))],
            palette=[18,18,5,17,12], specials=[(18,17,30),(18,24,12),(18,59,18),(17,55,26)]),
        'shallow_reef': dict(title='浅滩礁石', row=4,
            outline=[(3,19),(9,16),(7,12),(12,7),(23,5),(31,8),(38,3),(44,3),(50,8),(62,5),(70,9),(72,15),(70,18),(77,19),(77,26),(71,29),(72,34),(65,39),(53,38),(44,42),(37,42),(29,38),(17,40),(8,35),(9,28),(3,26)],
            holes=[ellipse(19,10,5,2),ellipse(62,34,5,2)],
            patches=[(1, ellipse(22,23,16,10) | ellipse(52,23,19,12)),
                     (3, ellipse(23,22,9,6) | ellipse(55,23,9,6)),
                     (2, ellipse(39,18,6,4) | ellipse(40,30,7,3))],
            palette=[5,12,13,8,17], specials=[(5,16,28),(13,29,29),(12,55,16),(8,64,25),(17,23,23)]),
        'waterfall_pool': dict(title='瀑布水潭', row=2,
            outline=[(3,19),(9,17),(9,10),(17,5),(29,5),(33,8),(38,3),(44,3),(48,7),(60,5),(69,10),(71,18),(77,19),(77,26),(70,29),(69,35),(61,40),(50,40),(44,42),(37,42),(28,38),(18,40),(10,35),(8,28),(3,26)],
            holes=[ellipse(18,10,4,2),ellipse(63,34,4,2)],
            patches=[(1, ellipse(39,23,27,14)),
                     (3, ellipse(40,23,23,11)),
                     (5, ellipse(42,24,13,7)),
                     (2, ellipse(28,23,5,4) | ellipse(54,20,4,3))],
            palette=[1,2,3,10,11,17], specials=[(3,27,21),(2,30,25),(10,29,24),(3,54,19),(17,43,26)]),
        'gate_of_surging_sea': dict(title='涌海之门', row=5,
            outline=[(3,19),(10,16),(10,10),(18,6),(30,7),(34,4),(38,3),(44,3),(47,6),(60,6),(69,10),(70,17),(77,19),(77,26),(71,28),(70,35),(60,39),(49,38),(43,42),(37,42),(30,39),(18,39),(10,34),(10,28),(3,26)],
            holes=[ellipse(18,10,4,2),ellipse(63,34,4,2)],
            patches=[(0, ellipse(40,23,23,13)),
                     (7, ellipse(40,23,18,10)),
                     (5, rect(36,10,44,37) | rect(16,19,64,27)),
                     (3, ellipse(27,23,5,5) | ellipse(53,23,5,5))],
            palette=[15,17,18,5,14], specials=[(18,35,17),(18,45,17),(15,39,22),(15,41,24),(14,22,32),(14,58,14)]),
    }


def draw_cells(canvas, cells):
    for (x, y), (col, row) in cells.items():
        tile = ATLAS.crop((col*16, row*16, (col+1)*16, (row+1)*16))
        canvas.alpha_composite(tile, (x*16, y*16))


def author_layout(name, spec):
    # 外轮廓不套同一椭圆模板：河图收窄成曲岸，礁图有侧湾，集市保留方形码头。
    outlines = {
        'crystal_river': [(3,19),(10,17),(11,13),(20,13),(20,7),(28,4),(38,3),(44,3),(46,7),(58,8),(67,12),(66,18),(77,19),(77,26),(68,28),(64,34),(56,34),(56,40),(44,42),(37,42),(33,37),(21,35),(14,31),(13,27),(3,26)],
        'deep_sea_rift': [(3,19),(11,17),(10,8),(21,5),(29,9),(35,11),(38,3),(44,3),(49,9),(59,6),(72,7),(68,16),(77,19),(77,26),(70,27),(73,36),(62,40),(54,35),(47,33),(43,42),(37,42),(31,37),(20,40),(8,38),(11,29),(3,26)],
        'crystal_shoal': [(3,19),(14,18),(22,10),(33,7),(38,3),(44,3),(48,8),(59,11),(67,18),(77,19),(77,26),(66,27),(58,35),(47,38),(43,42),(37,42),(32,38),(22,35),(14,28),(3,26)],
        'shallow_reef': [(3,19),(12,17),(9,13),(12,7),(24,6),(32,10),(38,3),(44,3),(49,10),(60,7),(69,8),(72,14),(68,18),(77,19),(77,26),(68,28),(72,33),(68,39),(57,40),(49,35),(43,42),(37,42),(31,36),(20,40),(10,37),(8,32),(12,28),(3,26)],
        'gate_of_surging_sea': [(3,19),(13,17),(14,10),(24,5),(34,7),(38,3),(44,3),(48,7),(58,5),(68,11),(68,18),(77,19),(77,26),(68,28),(65,36),(55,40),(47,37),(43,42),(37,42),(32,37),(23,40),(13,34),(13,28),(3,26)],
    }
    spec['outline'] = outlines.get(name,spec['outline'])
    holes = {
        'coral_shoal': [stroke([(9,7),(16,9),(19,10)],1.7)],
        'crystal_river': [],
        'deep_sea_rift': [stroke([(14,5),(22,8),(28,10),(32,12)],1.5),stroke([(49,36),(57,38),(65,40)],1.5)],
        'frozen_lake': [ellipse(60,11,8,2.5)],
        'waterfall_cave': [ellipse(15,6,6,4),ellipse(63,5,6,4)],
        'abyss_sea_market': [rect(6,11,15,16),rect(65,29,74,35)],
        'crystal_shoal': [],
        'deep_sea_undercurrent': [ellipse(23,9,8,2),ellipse(58,36,7,2)],
        'frozen_lake_shore': [rect(8,12,19,16),rect(60,30,71,34)],
        'shallow_reef': [ellipse(18,12,6,4),ellipse(61,34,6,4)],
        'waterfall_pool': [],
        'gate_of_surging_sea': [ellipse(20,12,4,3),ellipse(61,33,4,3)],
    }
    spec['holes'] = holes[name]
    land = polygon(spec['outline']) | LAND_PORTS | SAFE
    for hole in spec['holes']:
        land -= hole - SAFE - LAND_PORTS
    base = tiles(land, spec['row'])
    perimeter = {p: v for p, v in base.items() if v[0] != 15}
    layers = {'MapContainer/Ground/TileMapLayer': base}
    all_caps = set()
    for direction, extension in zip(DIRECTIONS, PORTS):
        extended = tiles(land | extension, spec['row'])
        changed = {p: v for p, v in extended.items() if v != base.get(p)}
        caps = {p: base[p] for p in changed if p in perimeter}
        all_caps.update(caps)
        layers[f'MapContainer/BridgeWithBoundary/{direction}BridgeWithBoundary'] = caps
        layers[f'MapContainer/BridgeContainer/{direction}Bridge'] = changed
        layers[f'MapContainer/BridgeBoundary/{direction}BridgeBoundary'] = {p: v for p, v in changed.items() if v[0] != 15}
    layers['MapContainer/Boundary/TileMapLayer'] = {p: v for p, v in perimeter.items() if p not in all_caps}
    inner = erode(land, 2)
    for i, (row, patch) in enumerate(spec['patches']):
        path = 'MapContainer/Ground/TileMapLayer2' if i == 0 else f'MapContainer/Ground/WaterDetail{i+1}'
        layers[path] = tiles(patch & inner, row)
    # 礁石只放在外围，中央物资网格、出生点和四条进出口通道留空。
    rocks = set()
    rock_positions = {
        'coral_shoal': [(65,16)], 'crystal_river': [(20,29)],
        'deep_sea_rift': [(16,30),(62,13)], 'frozen_lake': [],
        'waterfall_cave': [(15,27),(64,17)],'abyss_sea_market': [],
        'crystal_shoal': [],'deep_sea_undercurrent': [(18,31)],
        'frozen_lake_shore': [],'shallow_reef': [(17,30),(62,13)],
        'waterfall_pool': [],'gate_of_surging_sea': [(26,9)],
    }
    for x, y in rock_positions[name]:
        blob = polygon([(x-2,y-1),(x+1,y-2),(x+3,y),(x+1,y+2),(x-2,y+1)])
        if blob <= inner and not blob & SAFE:
            rocks |= blob
    layers['MapContainer/Obstack/TileMapLayer'] = tiles(rocks, 4)
    obstacle_cells = set(layers['MapContainer/Obstack/TileMapLayer'])
    # 点缀位置逐图固定；不会在游戏中随机生成，也不抢占可交互物资格。
    seed = sum(ord(c) for c in name)
    decorations = []
    occupied = []
    candidates = [(x, y) for y in range(7,39,3) for x in range(9,72,4)]
    candidates.sort(key=lambda p: ((p[0]*97+p[1]*71+seed*13)%499))
    safe_slots = [(360+(i+.5)*560/6,220+(j+.5)*340/4) for j in range(4) for i in range(6)]
    surface = dict(base)
    for key,cells in layers.items():
        if '/Ground/' in key:
            surface.update({p:val for p,val in cells.items() if val[0] == 15})

    def place(asset, x, y, scale=1.0):
        px, py = x*16+8, y*16+8
        im = Image.open(DECORS[asset])
        row = surface.get((x,y),(0,-1))[1]
        allowed = {1:{2,3,5,8},2:{2,3,5},3:{2,3,5},4:{3,5,6,7},7:{3,5,6,7},
                   8:{1,2,4},9:{3,5,6,7},10:{2,3,5},11:{2,3,5},12:{0,1,2,4},
                   13:{1,2,4},14:{1,3,5,6,7},15:{0,3,5,6,7},16:{3,5,6,7},17:{3,5,6,7},18:{0,3,5}}
        if asset in allowed and row not in allowed[asset]:
            return
        margin_x = math.ceil(im.width*scale/32)
        margin_y = math.ceil(im.height*scale/32)
        footprint = {(xx, yy) for yy in range(y-margin_y,y+margin_y+1) for xx in range(x-margin_x,x+margin_x+1)}
        if any(base.get(p, (0,0))[0] != 15 for p in footprint) or footprint & obstacle_cells:
            return
        if abs(x-40)<5 and (y<11 or y>34) or abs(y-22.5)<4 and (x<16 or x>64):
            return
        if math.hypot(px-640,py-360)<56 or any(math.hypot(px-sx,py-sy)<28 for sx,sy in safe_slots):
            return
        if any(math.hypot(x-ox,y-oy)<3 for ox,oy in occupied):
            return
        occupied.append((x,y))
        decorations.append(dict(asset=asset,x=px,y=py,scale=scale,flip=(x+y+seed)%3==0))

    for asset,x,y in spec['specials']:
        place(asset,x,y,1.1 if asset in [18,4,14] else 1.0)
    for k,(x,y) in enumerate(candidates):
        if len(decorations)>=30:
            break
        place(spec['palette'][k%len(spec['palette'])],x,y,.8 if k%4==0 else 1.0)
    return dict(name=name,title=spec['title'],layers=layers,decorations=decorations)


def write_scene(path, layout):
    backup = BEFORE / path.name
    if not backup.exists():
        backup.write_bytes(path.read_bytes())
    old = backup.read_text(encoding='utf-8')
    resource_blocks = ''.join(REF_SUBS.values())
    ref_texture_id = '7_ck2l1'
    # 各场景的脚本资源 ID 不同，只替换图集外部引用，不复用错误的旧 TileSet。
    resource_blocks = resource_blocks.replace(f'ExtResource("{ref_texture_id}")', 'ExtResource("water_atlas")')
    externals = blocks(old, 'ext_resource')
    externals = [b for b in externals if 'type="Texture2D"' not in b.splitlines()[0]]
    externals.append(f'[ext_resource type="Texture2D" path="res://{ATLAS_PATH}" id="water_atlas"]\n\n')
    used_assets = sorted({d['asset'] for d in layout['decorations']})
    for asset in used_assets:
        rel = DECORS[asset].relative_to(ROOT).as_posix()
        externals.append(f'[ext_resource type="Texture2D" path="res://{rel}" id="water_decor_{asset}"]\n\n')
    nodes = []
    for block in blocks(old, 'node'):
        key = node_path(block)
        if 'type="TileMapLayer"' in block.splitlines()[0]:
            # 配置模板保留 rotation 等原有非布局参数，包括参考图的独立 TileSet ID。
            header = block.splitlines()[0]
            body = REF_LAYERS[key].split('\n',1)[1]
            body = re.sub(r'^tile_map_data = .*\n','',body,flags=re.M)
            block = header+'\n'+body
            block = replace_property(block, 'tile_map_data', f'PackedByteArray("{encode(layout["layers"][key])}")')
        if key in ['MapContainer/Ground','MapContainer/Boundary','MapContainer/BridgeContainer','MapContainer/BridgeWithBoundary','MapContainer/BridgeBoundary','MapContainer/Obstack']:
            z = {'Ground':-5,'Boundary':-4,'BridgeContainer':-3,'BridgeWithBoundary':-3,'BridgeBoundary':-2,'Obstack':-2}[key.split('/')[-1]]
            block = replace_property(block,'z_index',str(z))
        nodes.append(block)
    # 材质叠层仍归 Ground Controller 所有，避免把逻辑添加到表现节点中。
    for key,cells in layout['layers'].items():
        if '/WaterDetail' not in key:
            continue
        nodes.append(f'[node name="{key.split("/")[-1]}" type="TileMapLayer" parent="MapContainer/Ground"]\ntile_set = SubResource("TileSet_a7d7s")\ntile_map_data = PackedByteArray("{encode(cells)}")\n\n')
    nodes.append('[node name="Decorations" type="Node2D" parent="MapContainer"]\nz_index = -1\ntexture_filter = 1\n\n')
    for i,d in enumerate(layout['decorations']):
        nodes.append(f'[node name="Decor{i+1:02d}" type="Sprite2D" parent="MapContainer/Decorations"]\nposition = Vector2({d["x"]}, {d["y"]})\nscale = Vector2({d["scale"]}, {d["scale"]})\ntexture = ExtResource("water_decor_{d["asset"]}")\nflip_h = {str(d["flip"]).lower()}\n\n')
    scene_header = old.splitlines()[0]
    path.write_text((scene_header+'\n\n'+''.join(externals)+resource_blocks+''.join(nodes)).rstrip()+'\n',encoding='utf-8',newline='\n')


def preview(layout, bridge_mask):
    im = Image.new('RGBA',(1280,720),(20,29,40,255))
    layers = layout['layers']
    for path,cells in layers.items():
        if '/Ground/' in path:
            draw_cells(im,cells)
    draw_cells(im,layers['MapContainer/Boundary/TileMapLayer'])
    for direction,bit in zip(DIRECTIONS,[1,2,4,8]):
        group = 'BridgeContainer' if bridge_mask & bit else 'BridgeWithBoundary'
        suffix = 'Bridge' if bridge_mask & bit else 'BridgeWithBoundary'
        draw_cells(im,layers[f'MapContainer/{group}/{direction}{suffix}'])
        if bridge_mask & bit:
            draw_cells(im,layers[f'MapContainer/BridgeBoundary/{direction}BridgeBoundary'])
    draw_cells(im,layers['MapContainer/Obstack/TileMapLayer'])
    for d in layout['decorations']:
        decor=Image.open(DECORS[d['asset']]).convert('RGBA')
        if d['flip']:
            decor=decor.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        decor=decor.resize((round(decor.width*d['scale']),round(decor.height*d['scale'])),Image.Resampling.NEAREST)
        im.alpha_composite(decor,(round(d['x']-decor.width/2),round(d['y']-decor.height/2)))
    return im.convert('RGB')


def main():
    all_layouts=[]
    for path in sorted((ROOT/'scenes/map_scenes/map_env/water').rglob('*.tscn')):
        layout=author_layout(path.stem,designs()[path.stem])
        write_scene(path,layout)
        all_layouts.append(layout)
        for state,mask in [('closed',0),('open',15)]:
            preview(layout,mask).save(OUT/f'{path.stem}.{state}.png')
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
    for state in ['closed','open']:
        sheet=Image.new('RGB',(1920,4*400),(17,23,31))
        draw=ImageDraw.Draw(sheet)
        for i,layout in enumerate(all_layouts):
            x,y=(i%3)*640,(i//3)*400
            sample=Image.open(OUT/f'{layout["name"]}.{state}.png').resize((640,360),Image.Resampling.NEAREST)
            sheet.paste(sample,(x,y+36));draw.text((x+12,y+6),layout['title'],font=font,fill=(215,231,240))
        sheet.save(OUT/f'water_contact_{state}.png')
    # JSON 仅作本次静态审计输入，生产场景没有运行时生成依赖。
    serial=[]
    for layout in all_layouts:
        serial.append({**layout,'layers':{k:[[x,y,c,r] for (x,y),(c,r) in cells.items()] for k,cells in layout['layers'].items()}})
    (OUT/'layouts.json').write_text(json.dumps(serial,ensure_ascii=False),encoding='utf-8')
    print(json.dumps([{'scene':l['name'],'layers':len(l['layers']),'decorations':len(l['decorations']),'tiles':sum(map(len,l['layers'].values()))} for l in all_layouts],indent=2))


if __name__=='__main__':
    main()
