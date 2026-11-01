"""本任务离线绘图工具；生产场景不依赖本文件，输入固定为用户原场景备份。"""
from pathlib import Path
import base64
import json
import math
import re
import struct
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
TASK = Path(__file__).parent
OUT = TASK / 'research'
BEFORE = OUT / 'before'
W, H, TILE = 80, 45, 16
REF = (OUT / 'ash_plain.before.tscn').read_text(encoding='utf-8')
ATLAS_PATH = 'res/UI/生态图集/火-生态/火-生态.png'
OBSTACLE_PATH = 'res/UI/生态图集/火-生态/火-生态-Obstacle.png'
ATLAS = Image.open(ROOT / ATLAS_PATH).convert('RGBA')
OBSTACLE_ATLAS = Image.open(ROOT / OBSTACLE_PATH).convert('RGBA')
DECORS = {int(p.name[:2]): p for p in (ROOT / 'res/UI/生态图集/火-生态/装饰物').glob('*.png')}
GROUP_ORIGINS = [(0, 0), (4, 0), (8, 0), (12, 0), (0, 4), (4, 4)]


def blocks(text, kind):
    return re.findall(r'^\[' + kind + r'[^\n]*\]\n(?:(?!^\[).|\n)*', text, re.M)


def node_path(block):
    header = block.splitlines()[0]
    name = re.search(r'name="([^"]+)"', header)[1]
    parent = re.search(r'parent="([^"]+)"', header)
    return (parent[1] + '/' if parent and parent[1] != '.' else '') + name


REF_SUBS = blocks(REF, 'sub_resource')
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
    # 材质离开真实岸线，保证叠层的透明内角不会画出悬空碎边。
    return {p for p in vertices if all((p[0]+dx, p[1]+dy) in vertices for dx, dy in
            [(-distance, 0), (distance, 0), (0, -distance), (0, distance)])}


def connected_land(vertices):
    # 凹口切到外轮廓时可能留下孤点或一角宽的细尾；这些碎片没有通行用途。
    protected = SAFE | LAND_PORTS
    while True:
        leaves = {p for p in vertices - protected if sum((p[0]+dx,p[1]+dy) in vertices
                  for dx,dy in [(0,1),(0,-1),(1,0),(-1,0)]) < 2}
        if not leaves:
            break
        vertices -= leaves
    reached, stack = {(40,23)}, [(40,23)]
    while stack:
        x,y = stack.pop()
        for p in [(x+1,y),(x-1,y),(x,y+1),(x,y-1)]:
            if p in vertices and p not in reached:
                reached.add(p)
                stack.append(p)
    return reached


def masks(vertices):
    # 四角掩码直接对应图集列号，包含单角、凹角和对角片。
    return {(x, y): m for y in range(H) for x in range(W)
            if (m := (8*((x, y) in vertices) + 4*((x+1, y) in vertices)
                      + 2*((x, y+1) in vertices) + ((x+1, y+1) in vertices)))}


def tiles(vertices, row):
    return {p: (m, row) for p, m in masks(vertices).items()}


def encode(cells):
    raw = b'\0\0' + b''.join(struct.pack('<hhHHHH', x, y, 0, col, row, 0)
                             for (x, y), (col, row) in sorted(cells.items(), key=lambda c: (c[0][1], c[0][0])))
    return base64.b64encode(raw).decode('ascii')


def replace_property(block, key, value):
    pattern = r'^' + re.escape(key) + r' = .*\n'
    if re.search(pattern, block, re.M):
        return re.sub(pattern, lambda _: key + ' = ' + value + '\n', block, flags=re.M)
    return block.rstrip() + '\n' + key + ' = ' + value + '\n\n'


PORTS = [rect(37, -1, 43, 7), rect(73, 19, 81, 26), rect(37, 38, 43, 46), rect(-1, 19, 7, 26)]
LAND_PORTS = rect(37, 3, 43, 10) | rect(37, 35, 43, 42) | rect(3, 19, 12, 26) | rect(68, 19, 77, 26)
DIRECTIONS = ['Up', 'Right', 'Down', 'Left']
SAFE = rect(23, 13, 57, 36)
PORT_GUARD = rect(34, 0, 46, 11) | rect(34, 36, 46, 45) | rect(0, 17, 15, 28) | rect(65, 17, 80, 28)
OBSTACLE_GUARD = SAFE | PORT_GUARD


def designs():
    # 每张图独立指定轮廓、凹口、分层和完整障碍，不复用其他生态的布局。
    return {
        'ash_plain': dict(title='灰烬平原', row=3,
            outline=[(5,18),(10,15),(10,9),(18,5),(31,6),(35,4),(44,4),(48,8),(61,6),(68,11),(67,17),(75,19),(76,26),(69,28),(71,34),(65,38),(52,39),(45,37),(43,42),(37,42),(32,39),(23,41),(14,37),(8,32),(10,28),(4,26)],
            holes=[stroke([(10,9),(15,10),(19,11)], 1.2)],
            patches=[(5, polygon([(15,16),(25,10),(36,12),(41,17),(55,14),(65,19),(61,31),(49,35),(37,32),(26,36),(15,29)])),
                     (3, ellipse(39,23,20,10)),
                     (7, stroke([(16,18),(23,20),(27,19)],1.3) | stroke([(49,29),(56,31),(63,30)],1.2) | ellipse(51,12,5,2)),
                     (6, stroke([(22,29),(28,27),(34,28)],.7) | stroke([(45,15),(49,18),(57,18)],.8))],
            palette=[6,11,12,18,10,16],
            specials=[(11,18,15),(12,60,31),(18,31,11),(10,47,31)],
            obstacles=[(2,18,12),(2,61,29),(5,58,10),(6,15,30)]),
        'lava_riverside': dict(title='熔岩河畔', row=2,
            outline=[(4,19),(13,16),(11,11),(19,7),(28,9),(33,5),(43,3),(50,7),(61,8),(68,12),(66,17),(76,19),(77,26),(68,29),(65,34),(57,35),(55,40),(44,42),(37,42),(31,38),(21,36),(15,32),(13,28),(3,26)],
            holes=[stroke([(15,5),(19,8),(22,11)],1.1)],
            patches=[(7, stroke([(25,9),(21,14),(25,20),(20,28),(25,34),(32,39)],5.3)),
                     (0, stroke([(25,9),(21,14),(25,20),(20,28),(25,34),(32,39)],3.1)),
                     (1, stroke([(25,10),(23,14),(26,19),(23,25),(24,30),(29,36)],.65)),
                     (5, polygon([(32,12),(44,10),(58,15),(61,22),(56,32),(44,35),(32,31),(29,25)])),
                     (3, stroke([(16,22),(28,22),(35,25),(46,25),(59,22)],2.1))],
            palette=[4,5,7,8,16,17],
            specials=[(17,23,16),(17,22,30),(8,28,30),(5,55,16),(4,60,30)],
            obstacles=[(1,18,12),(3,28,9),(4,60,29),(6,16,29)]),
        'obsidian_cliff': dict(title='黑曜石崖', row=8,
            outline=[(7,18),(11,18),(11,12),(19,12),(19,6),(33,6),(33,4),(44,4),(44,8),(59,8),(59,11),(70,11),(70,19),(77,19),(77,26),(70,26),(70,32),(63,32),(63,38),(49,38),(49,40),(43,42),(37,42),(33,39),(19,39),(19,35),(11,35),(11,28),(3,26),(3,19)],
            holes=[rect(11,12,17,16),rect(64,28,72,31)],
            patches=[(7, polygon([(18,15),(25,10),(51,10),(62,15),(65,28),(58,35),(34,36),(23,32),(17,25)])),
                     (8, polygon([(23,18),(30,14),(51,14),(58,19),(59,28),(52,31),(31,32),(22,27)])),
                     (6, stroke([(20,30),(29,29),(36,31),(48,30),(57,33)],1.1)),
                     (2, stroke([(19,31),(29,30),(35,32),(48,31),(56,34)],.55)),
                     (7, rect(28,18,50,27))],
            palette=[5,5,4,13,14,16],
            specials=[(5,25,15),(5,55,30),(14,60,16),(5,21,32)],
            obstacles=[(2,20,9),(4,61,12),(5,17,29),(6,58,33)]),
        'sulfur_rift': dict(title='硫磺裂谷', row=1,
            outline=[(3,19),(12,17),(9,10),(17,6),(26,8),(32,5),(39,3),(44,4),(48,9),(60,5),(70,7),(68,15),(76,19),(77,26),(70,29),(72,36),(63,40),(55,36),(47,34),(43,42),(37,42),(31,37),(21,40),(11,37),(13,29),(3,26)],
            holes=[stroke([(13,5),(20,8),(27,11)],1.3),stroke([(59,41),(64,38),(68,35)],1.2)],
            patches=[(5, stroke([(31,7),(34,13),(39,20),(37,26),(43,33),(51,37)],4.2) | stroke([(39,20),(49,16),(57,11)],3.2)),
                     (7, stroke([(32,9),(35,14),(40,20),(39,26),(44,32),(50,35)],2.0) | stroke([(40,20),(48,16),(56,12)],1.7)),
                     (0, stroke([(34,12),(36,16),(41,21),(40,26),(45,32)],.6) | stroke([(42,20),(49,16),(53,14)],.5)),
                     (3, ellipse(20,27,6,5) | ellipse(61,25,5,6))],
            palette=[6,13,15,16,4,17],
            specials=[(15,31,15),(15,47,30),(17,43,29),(6,60,17)],
            obstacles=[(1,17,12),(2,62,13),(5,17,30),(6,60,31)]),
        'volcanic_foothills': dict(title='火山山麓', row=6,
            outline=[(3,19),(12,17),(15,10),(26,6),(34,8),(38,3),(44,3),(49,8),(56,7),(64,12),(68,18),(77,19),(77,26),(71,29),(72,34),(65,39),(55,41),(46,39),(43,42),(37,42),(32,39),(21,41),(12,37),(8,32),(11,28),(3,26)],
            holes=[ellipse(19,15,3.5,3)],
            patches=[(2, polygon([(15,25),(24,15),(38,11),(48,13),(58,19),(67,32),(59,36),(48,32),(38,34),(26,36)])),
                     (5, ellipse(40,25,18,10)),
                     (7, ellipse(19,15,7,6) | stroke([(49,12),(52,18),(58,23)],2.7)),
                     (0, (ellipse(19,15,5.8,4.7)-ellipse(19,15,4.6,3.7)) | stroke([(49,13),(52,18),(58,23)],.8)),
                     (3, ellipse(40,26,12,6))],
            palette=[4,6,7,8,16,18],
            specials=[(7,30,30),(8,53,28),(4,56,15),(16,24,18)],
            obstacles=[(3,25,9),(4,62,29),(1,14,29),(6,59,12)]),
        'scorched_wilds_exchange': dict(title='焦土交换所', row=5,
            outline=[(7,8),(27,8),(27,5),(37,5),(37,3),(44,3),(44,5),(56,5),(56,8),(73,8),(73,19),(77,19),(77,26),(73,26),(73,37),(57,37),(57,40),(44,40),(43,42),(37,42),(36,40),(23,40),(23,37),(7,37),(7,26),(3,26),(3,19),(7,19)],
            holes=[rect(6,11,14,16),rect(66,29,75,34)],
            patches=[(7, rect(17,11,63,35)),
                     (3, rect(20,14,60,32) | rect(11,19,69,26)),
                     (5, rect(25,17,55,29)),
                     (6, rect(28,19,52,27)),
                     (1, rect(17,11,24,13) | rect(56,33,63,35))],
            palette=[3,6,12,13,14,18],
            specials=[(3,20,17),(3,60,30),(14,17,30),(12,62,13),(13,21,32)],
            obstacles=[(2,17,9),(2,60,9),(5,15,31),(6,60,33)]),
        'ash_hill': dict(title='灰烬丘陵', row=3,
            outline=[(3,19),(9,17),(8,12),(15,7),(23,6),(30,10),(38,3),(44,3),(50,10),(60,7),(68,10),(71,15),(68,18),(77,19),(77,26),(69,28),(71,33),(66,38),(57,40),(48,36),(43,42),(37,42),(30,37),(22,40),(13,37),(8,32),(11,28),(3,26)],
            holes=[ellipse(16,10,4,1.7)],
            patches=[(5, ellipse(24,22,16,10) | ellipse(57,23,14,11)),
                     (7, ellipse(26,21,12,7) | ellipse(55,26,10,7)),
                     (3, ellipse(27,20,9,5) | ellipse(54,25,7,4)),
                     (6, stroke([(33,31),(38,30),(44,31)],1) | ellipse(53,13,5,2))],
            palette=[6,11,12,18,10,13],
            specials=[(11,20,29),(18,29,13),(18,54,30),(10,42,16)],
            obstacles=[(2,18,13),(2,60,30),(5,17,30),(6,59,12)]),
        'geothermal_valley': dict(title='地热谷地', row=5,
            outline=[(3,19),(10,17),(9,11),(17,6),(29,7),(34,10),(38,3),(44,3),(48,8),(61,5),(69,10),(71,17),(77,19),(77,26),(70,29),(69,35),(61,40),(50,38),(44,42),(37,42),(29,38),(19,40),(10,35),(8,29),(3,26)],
            holes=[ellipse(17,14,3,3),ellipse(64,32,3,2.5)],
            patches=[(1, ellipse(17,14,7,6) | ellipse(64,32,6,5) | ellipse(41,23,17,10)),
                     (0, ellipse(17,14,5.4,4.6) | ellipse(64,32,4.8,3.8) | ellipse(41,23,13,7)),
                     (5, ellipse(41,23,10,5)),
                     (3, ellipse(41,23,7,3)),
                     (7, stroke([(24,32),(28,30),(31,31)],1.1) | ellipse(60,13,4,2))],
            palette=[15,15,6,16,17,8],
            specials=[(15,23,16),(15,57,31),(17,29,20),(17,51,25),(8,35,29)],
            obstacles=[(1,25,9),(3,59,11),(5,15,29),(6,58,35)]),
        'igneous_cliff': dict(title='火成岩壁', row=7,
            outline=[(3,19),(12,17),(11,10),(19,10),(19,5),(28,8),(32,11),(38,3),(44,3),(48,11),(57,7),(65,9),(66,14),(71,16),(70,19),(77,19),(77,26),(69,29),(72,33),(65,36),(63,40),(54,38),(47,34),(43,42),(37,42),(31,35),(23,39),(15,36),(12,31),(13,27),(3,26)],
            holes=[polygon([(11,9),(19,10),(21,13),(15,15)]),polygon([(65,33),(72,31),(72,36),(66,38)])],
            patches=[(6, polygon([(17,20),(27,11),(36,15),(45,12),(61,15),(65,25),(56,33),(48,30),(36,34),(24,30)])),
                     (2, stroke([(20,27),(27,20),(35,20),(42,17),(53,21),(61,19)],2.1)),
                     (7, polygon([(23,25),(29,19),(39,21),(46,18),(56,23),(53,29),(44,28),(36,31),(28,28)])),
                     (8, stroke([(19,31),(27,27),(34,29),(45,25),(54,28),(62,24)],1.3)),
                     (0, stroke([(22,16),(28,13),(34,16)],.6))],
            palette=[4,5,5,14,16,13],
            specials=[(5,27,16),(5,55,30),(4,19,29),(14,59,14)],
            obstacles=[(4,18,16),(3,60,12),(5,15,30),(6,59,31)]),
        'lava_plateau': dict(title='熔岩高地', row=2,
            outline=[(3,19),(11,19),(11,13),(17,13),(17,8),(27,8),(27,5),(38,3),(44,3),(48,7),(61,7),(61,11),(69,11),(69,19),(77,19),(77,26),(70,26),(70,31),(64,31),(64,36),(55,36),(55,40),(44,42),(37,42),(32,39),(21,39),(21,35),(13,35),(13,28),(3,26)],
            holes=[rect(11,14,18,17)],
            patches=[(6, polygon([(20,13),(31,10),(53,12),(62,17),(60,31),(51,36),(29,34),(20,29)])),
                     (7, rect(24,15,57,32)),
                     (0, stroke([(24,16),(36,16),(36,20),(50,20),(50,29),(56,29)],1.2) | stroke([(25,30),(32,30),(32,26)],1.1)),
                     (2, polygon([(28,20),(33,20),(37,23),(47,23),(47,28),(35,30),(28,27)])),
                     (1, stroke([(24,16),(35,16)],.45) | stroke([(50,23),(50,28)],.45))],
            palette=[4,5,8,16,17,7],
            specials=[(17,28,16),(17,50,26),(8,45,30),(4,60,16)],
            obstacles=[(3,27,9),(1,60,12),(4,60,31),(6,17,29)]),
        'sulfur_passage': dict(title='硫磺通道', row=1,
            outline=[(3,19),(13,18),(13,13),(23,13),(23,8),(33,8),(38,3),(44,3),(44,10),(59,10),(59,15),(68,15),(68,19),(77,19),(77,26),(67,26),(67,31),(58,31),(58,37),(48,37),(43,42),(37,42),(33,37),(23,37),(23,33),(14,33),(14,28),(3,26)],
            holes=[rect(13,12,19,16),rect(62,29,70,33)],
            patches=[(5, polygon([(21,19),(27,14),(42,14),(47,18),(59,18),(63,24),(55,30),(46,30),(40,34),(28,31),(22,27)])),
                     (7, stroke([(24,25),(31,23),(38,25),(46,21),(55,22)],4.5)),
                     (1, stroke([(24,25),(31,23),(38,25),(46,21),(55,22)],2.8)),
                     (3, stroke([(24,25),(31,23),(38,25),(46,21),(55,22)],1.0)),
                     (0, ellipse(29,14,3,1) | ellipse(51,32,3,1))],
            palette=[6,13,15,16,18,4],
            specials=[(15,30,16),(15,51,30),(6,27,30),(18,56,16)],
            obstacles=[(2,26,9),(1,59,16),(5,18,28)]),
        'gate_of_scorched_wilds': dict(title='焦野之门', row=6,
            outline=[(3,19),(12,17),(12,10),(23,5),(32,7),(38,3),(44,3),(48,7),(57,5),(68,10),(68,18),(77,19),(77,26),(68,28),(68,35),(57,40),(48,38),(43,42),(37,42),(32,38),(23,40),(12,35),(12,28),(3,26)],
            holes=[ellipse(19,13,3,2),ellipse(61,13,3,2)],
            patches=[(7, polygon([(17,19),(25,11),(55,11),(63,19),(63,30),(55,35),(25,35),(17,30)])),
                     (5, rect(24,16,56,32) | rect(36,10,44,36)),
                     (3, rect(28,19,52,29)),
                     (2, ellipse(20,31,4.5,3.5) | ellipse(60,31,4.5,3.5)),
                     (0, ellipse(20,31,3,2) | ellipse(60,31,3,2))],
            palette=[2,4,5,13,14,16],
            specials=[(2,29,16),(2,51,16),(14,26,31),(14,54,31),(13,18,18)],
            obstacles=[(3,16,28),(4,59,28),(2,25,9),(2,51,9)]),
    }


def author_layout(name, spec):
    land = polygon(spec['outline']) | SAFE | LAND_PORTS
    for hole in spec['holes']:
        land -= hole - SAFE - LAND_PORTS
    land = connected_land(land)
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
        path = 'MapContainer/Ground/TileMapLayer2' if i == 0 else f'MapContainer/Ground/FireDetail{i+1}'
        layers[path] = tiles((patch & inner) - PORT_GUARD, row)

    # 每个障碍按完整 4×4 组合复制，包括透明格；保留源图每一格已有的碰撞。
    obstacle_cells = {}
    obstacle_groups = []
    for group, wanted_x, wanted_y in spec['obstacles']:
        candidates = [(x, y) for y in range(max(4,wanted_y-4),min(38,wanted_y+5))
                      for x in range(max(5,wanted_x-4),min(71,wanted_x+5))]
        candidates.sort(key=lambda p: (abs(p[0]-wanted_x)+abs(p[1]-wanted_y), p[1], p[0]))
        for x, y in candidates:
            footprint = {(x+dx,y+dy) for dy in range(4) for dx in range(4)}
            if footprint & OBSTACLE_GUARD or any(base.get(p,(0,0))[0]!=15 for p in footprint):
                continue
            if any((xx+dx,yy+dy) in obstacle_cells for xx,yy in footprint for dx,dy in [(0,0),(-1,0),(1,0),(0,-1),(0,1)]):
                continue
            ax, ay = GROUP_ORIGINS[group-1]
            obstacle_cells.update({(x+dx,y+dy):(ax+dx,ay+dy) for dy in range(4) for dx in range(4)})
            obstacle_groups.append(dict(group=group,cell=[x,y],atlas_origin=[ax,ay],size=[4,4]))
            break
        else:
            raise ValueError(f'{name}: 障碍组{group}在预定位置附近没有完整地表')
    layers['MapContainer/Obstack/TileMapLayer'] = obstacle_cells

    surface = dict(base)
    for key,cells in layers.items():
        if '/Ground/' in key:
            surface.update({p:v for p,v in cells.items() if v[0]==15})
    seed = sum(map(ord,name))
    decorations, occupied = [], []
    safe_slots = [(360+(i+.5)*560/6,220+(j+.5)*340/4) for j in range(4) for i in range(6)]

    def place(asset, x, y, scale=1):
        px, py = x*16+8, y*16+8
        image = Image.open(DECORS[asset])
        row = surface.get((x,y),(0,-1))[1]
        # 岩石与灰烬适用于固态表面；熔岩气泡和烟柱依附热区。
        if asset==17 and row not in [0,1,2]:
            return
        if asset in [11,12,18] and row in [0,1]:
            return
        if asset==15 and row not in [0,1,2,5,6]:
            return
        mx, my = math.ceil(image.width*scale/32), math.ceil(image.height*scale/32)
        footprint = {(xx,yy) for yy in range(y-my,y+my+1) for xx in range(x-mx,x+mx+1)}
        if any(base.get(p,(0,0))[0]!=15 for p in footprint) or footprint & (set(obstacle_cells)|PORT_GUARD):
            return
        if math.hypot(px-640,py-360)<56 or any(math.hypot(px-sx,py-sy)<27 for sx,sy in safe_slots):
            return
        if any(math.hypot(x-ox,y-oy)<3 for ox,oy in occupied):
            return
        occupied.append((x,y))
        decorations.append(dict(asset=asset,x=px,y=py,scale=scale,flip=(x+y+seed)%3==0))

    for asset,x,y in spec['specials']:
        place(asset,x,y)
    candidates=[(x,y) for y in range(8,38,3) for x in range(12,69,4)]
    candidates.sort(key=lambda p:(p[0]*97+p[1]*71+seed*13)%499)
    for i,(x,y) in enumerate(candidates):
        if len(decorations)>=30:
            break
        place(spec['palette'][i%len(spec['palette'])],x,y,.8 if i%4==0 else 1)
    return dict(name=name,title=spec['title'],base_row=spec['row'],layers=layers,
                decorations=decorations,obstacle_groups=obstacle_groups)


def write_scene(path, layout):
    old = (BEFORE/path.name).read_text(encoding='utf-8')
    # 原参考图的全部子资源原样保留，压缩纹理包装也不能省略。
    externals=[b for b in blocks(old,'ext_resource') if 'type="Texture2D"' not in b.splitlines()[0]]
    for b in blocks(REF,'ext_resource'):
        if 'type="Texture2D"' in b.splitlines()[0]:
            new_id=re.search(r'id="([^"]+)"',b)[1]
            assert not any(f'id="{new_id}"' in other.splitlines()[0] for other in externals)
            externals.append(b)
    for asset in sorted({d['asset'] for d in layout['decorations']}):
        rel=DECORS[asset].relative_to(ROOT).as_posix()
        externals.append(f'[ext_resource type="Texture2D" path="res://{rel}" id="fire_decor_{asset}"]\n\n')
    nodes=[]
    for block in blocks(old,'node'):
        key=node_path(block)
        if 'type="TileMapLayer"' in block.splitlines()[0]:
            header=block.splitlines()[0]
            body=re.sub(r'^tile_map_data = .*\n','',REF_LAYERS[key].split('\n',1)[1],flags=re.M)
            block=replace_property(header+'\n'+body,'tile_map_data',f'PackedByteArray("{encode(layout["layers"][key])}")')
        if key in ['MapContainer/Ground','MapContainer/Boundary','MapContainer/BridgeContainer',
                   'MapContainer/BridgeWithBoundary','MapContainer/BridgeBoundary','MapContainer/Obstack']:
            z={'Ground':-5,'Boundary':-4,'BridgeContainer':-3,'BridgeWithBoundary':-3,'BridgeBoundary':-2,'Obstack':-2}[key.split('/')[-1]]
            block=replace_property(block,'z_index',str(z))
        nodes.append(block)
    for key,cells in layout['layers'].items():
        if '/FireDetail' in key:
            nodes.append(f'[node name="{key.split("/")[-1]}" type="TileMapLayer" parent="MapContainer/Ground"]\n'
                         f'tile_set = SubResource("TileSet_vi0mc")\ntile_map_data = PackedByteArray("{encode(cells)}")\n\n')
    nodes.append('[node name="Decorations" type="Node2D" parent="MapContainer"]\nz_index = -1\ntexture_filter = 1\n\n')
    for i,d in enumerate(layout['decorations']):
        nodes.append(f'[node name="Decor{i+1:02d}" type="Sprite2D" parent="MapContainer/Decorations"]\n'
                     f'position = Vector2({d["x"]}, {d["y"]})\nscale = Vector2({d["scale"]}, {d["scale"]})\n'
                     f'texture = ExtResource("fire_decor_{d["asset"]}")\nflip_h = {str(d["flip"]).lower()}\n\n')
    text=old.splitlines()[0]+'\n\n'+''.join(externals)+''.join(REF_SUBS)+''.join(nodes)
    path.write_text(text.rstrip()+'\n',encoding='utf-8',newline='\n')


def draw_cells(canvas,cells,atlas=ATLAS):
    for (x,y),(col,row) in cells.items():
        tile=atlas.crop((col*16,row*16,(col+1)*16,(row+1)*16))
        canvas.alpha_composite(tile,(x*16,y*16))


def preview(layout, bridge_mask):
    image=Image.new('RGBA',(1280,720),(25,20,23,255))
    layers=layout['layers']
    for path,cells in layers.items():
        if '/Ground/' in path:
            draw_cells(image,cells)
    draw_cells(image,layers['MapContainer/Boundary/TileMapLayer'])
    for direction,bit in zip(DIRECTIONS,[1,2,4,8]):
        opened=bridge_mask&bit
        group,suffix=('BridgeContainer','Bridge') if opened else ('BridgeWithBoundary','BridgeWithBoundary')
        draw_cells(image,layers[f'MapContainer/{group}/{direction}{suffix}'])
        if opened:
            draw_cells(image,layers[f'MapContainer/BridgeBoundary/{direction}BridgeBoundary'])
    draw_cells(image,layers['MapContainer/Obstack/TileMapLayer'],OBSTACLE_ATLAS)
    for d in layout['decorations']:
        decor=Image.open(DECORS[d['asset']]).convert('RGBA')
        if d['flip']:
            decor=decor.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        decor=decor.resize((round(decor.width*d['scale']),round(decor.height*d['scale'])),Image.Resampling.NEAREST)
        image.alpha_composite(decor,(round(d['x']-decor.width/2),round(d['y']-decor.height/2)))
    return image.convert('RGB')


def main():
    layouts=[]
    specs=designs()
    # 全部布局先生成成功，再写场景，避免某张图无支撑障碍导致半批完成。
    paths=sorted((ROOT/'scenes/map_scenes/map_env/fire').rglob('*.tscn'))
    for path in paths:
        layouts.append(author_layout(path.stem,specs[path.stem]))
    for path,layout in zip(paths,layouts):
        write_scene(path,layout)
        for state,mask in [('closed',0),('open',15)]:
            preview(layout,mask).save(OUT/f'{path.stem}.{state}.png')
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
    for state in ['closed','open']:
        sheet=Image.new('RGB',(1920,1600),(17,15,18))
        draw=ImageDraw.Draw(sheet)
        for i,layout in enumerate(layouts):
            x,y=(i%3)*640,(i//3)*400
            sample=Image.open(OUT/f'{layout["name"]}.{state}.png').resize((640,360),Image.Resampling.NEAREST)
            sheet.paste(sample,(x,y+36))
            draw.text((x+12,y+6),layout['title'],font=font,fill=(239,222,197))
        sheet.save(OUT/f'fire_contact_{state}.png')
    serial=[{**layout,'layers':{k:[[x,y,c,r] for (x,y),(c,r) in cells.items()] for k,cells in layout['layers'].items()}}
            for layout in layouts]
    (OUT/'layouts.json').write_text(json.dumps(serial,ensure_ascii=False),encoding='utf-8')
    (OUT/'obstacle_groups.json').write_text(json.dumps({l['name']:l['obstacle_groups'] for l in layouts},indent=2),encoding='utf-8')
    print(json.dumps([{'scene':l['name'],'layers':len(l['layers']),'decorations':len(l['decorations']),
                       'obstacle_groups':len(l['obstacle_groups']),'tiles':sum(map(len,l['layers'].values()))}
                      for l in layouts],indent=2))


if __name__=='__main__':
    main()
