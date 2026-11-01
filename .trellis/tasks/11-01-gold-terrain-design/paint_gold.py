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
REF = (OUT / 'copper_rust_forest.before.tscn').read_text(encoding='utf-8')
ATLAS_PATH = 'res/UI/生态图集/金-生态/金-生态.png'
ATLAS = Image.open(ROOT / ATLAS_PATH).convert('RGBA')
DECORS = {int(p.name[:2]): p for p in (ROOT / 'res/UI/生态图集/金-生态/装饰物').glob('*.png')}


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


def cog(cx,cy,rx,ry):
    # 齿形只用于无碰撞的地表花纹，真实通行边界仍沿房间岸线。
    return field(lambda x,y: ((x-cx)/rx)**2+((y-cy)/ry)**2 <=
                 (1+.10*math.cos(12*math.atan2((y-cy)/ry,(x-cx)/rx)))**2)


def designs():
    # 十二种构图分别手工指定；矿脉、铸造带和齿圈不复用其他生态布局。
    return {
      'copper_rust_forest':dict(title='铜锈之森',row=5,
        outline=[(3,19),(10,17),(8,11),(14,7),(24,5),(30,8),(36,7),(38,3),(44,3),(47,9),(55,6),(66,7),(72,13),(69,18),(77,19),(77,26),(69,28),(70,34),(63,39),(54,38),(48,36),(43,42),(37,42),(32,38),(25,41),(17,38),(11,33),(12,28),(3,26)],
        holes=[ellipse(17,11,3,2),stroke([(62,40),(63,36),(68,32)],1.3)],
        patches=[(3,ellipse(22,22,13,11)|ellipse(58,21,12,10)),
          (6,(ellipse(22,22,10,8)-ellipse(24,24,6,4))|(ellipse(58,21,9,7)-ellipse(56,22,5,4))),
          (5,stroke([(18,29),(29,27),(39,23),(48,24),(61,28)],2.1)),
          (4,ellipse(18,14,3,1.5)|ellipse(61,32,4,2)|stroke([(33,14),(39,17),(43,16)],.8))],
        palette=[3,4,9,14,18,21,25],specials=[(15,18,18),(9,58,18),(18,23,32),(3,53,30)]),
      'gear_wasteland':dict(title='齿轮荒原',row=7,
        outline=[(3,19),(11,19),(11,14),(8,14),(8,9),(19,9),(19,5),(30,5),(30,8),(36,8),(38,3),(44,3),(45,8),(56,8),(56,5),(65,5),(65,11),(72,11),(72,19),(77,19),(77,26),(71,26),(71,33),(65,33),(65,39),(55,39),(55,36),(46,36),(43,42),(37,42),(34,37),(25,37),(25,40),(14,40),(14,34),(8,34),(8,28),(3,26)],
        holes=[rect(9,9,14,13),rect(66,34,72,39)],
        patches=[(4,cog(39,23,23,13)),(0,cog(39,23,18,10)-ellipse(39,23,14,7)),
          (5,ellipse(39,23,12,6)),(7,ellipse(39,23,8,4)),
          (3,rect(15,12,23,15)|rect(58,31,65,34))],
        palette=[1,2,5,8,21,22,24,31],specials=[(2,20,18),(1,57,28),(22,40,16),(19,59,15)]),
      'golden_sand_plain':dict(title='金沙平原',row=2,
        outline=[(3,19),(10,17),(12,12),(19,8),(28,9),(33,7),(38,3),(44,3),(50,7),(60,8),(67,13),(69,18),(77,19),(77,26),(70,28),(67,34),(58,39),(49,37),(43,42),(37,42),(32,39),(23,38),(16,35),(11,30),(3,26)],
        holes=[ellipse(15,13,3,1.7)],
        patches=[(1,stroke([(15,17),(24,13),(33,15),(42,13),(52,16),(63,14)],2.0)),
          (5,stroke([(15,29),(25,32),(35,29),(44,32),(54,29),(64,31)],2.7)),
          (1,stroke([(17,28),(26,30),(35,27),(45,30),(55,27),(63,29)],1)),
          (0,ellipse(24,23,5,2)|ellipse(54,22,5,2))],
        palette=[10,11,12,16,18,25,26],specials=[(11,26,18),(10,55,30),(12,54,17),(16,20,30)]),
      'iron_ridge_canyon':dict(title='铁脊峡谷',row=4,
        outline=[(3,19),(12,18),(10,12),(18,6),(25,6),(30,10),(35,9),(38,3),(44,3),(47,9),(53,6),(60,8),(67,7),(70,13),(68,18),(77,19),(77,26),(68,28),(72,33),(65,37),(58,36),(53,40),(47,37),(43,42),(37,42),(33,38),(26,40),(20,36),(13,36),(9,31),(12,27),(3,26)],
        holes=[polygon([(12,6),(20,7),(23,11),(21,14),(17,12),(15,9)]),polygon([(63,33),(68,32),(73,35),(69,39),(64,37)])],
        patches=[(7,stroke([(23,10),(28,17),(35,18),(43,27),(52,27),(59,34)],4.4)),
          (8,stroke([(24,11),(29,18),(36,20),(43,28),(52,29),(58,34)],2.1)),
          (0,stroke([(23,12),(27,17),(34,18),(41,26),(49,26),(57,32)],.75)),
          (5,ellipse(58,15,7,3)|ellipse(22,31,6,3))],
        palette=[14,17,18,24,25,26,32],specials=[(18,24,16),(17,54,30),(32,60,16),(25,20,30)]),
      'magnetite_mine':dict(title='磁铁矿洞',row=8,
        outline=[(3,19),(11,18),(11,11),(18,11),(18,7),(27,5),(34,8),(38,3),(44,3),(48,8),(55,6),(64,8),(69,12),(69,18),(77,19),(77,26),(70,28),(69,34),(61,39),(51,37),(43,42),(37,42),(32,38),(23,39),(15,35),(11,29),(3,26)],
        holes=[ellipse(20,12,3,2),rect(62,32,66,35)],
        patches=[(4,polygon([(18,17),(23,10),(48,10),(61,15),(64,27),(57,35),(28,35),(18,29)])),
          (7,polygon([(23,18),(28,14),(48,14),(57,18),(59,27),(52,31),(29,31),(23,27)])),
          (8,rect(28,18,51,28)),
          (0,stroke([(21,27),(28,26),(34,22),(43,22),(49,18),(57,18)],.9)),
          (5,rect(29,12,36,14)|rect(54,29,61,31))],
        palette=[17,17,18,18,12,25,32],specials=[(32,25,16),(18,48,30),(17,57,16),(12,30,30)]),
      'steel_dome_exchange':dict(title='钢穹交换所',row=4,
        outline=[(3,19),(9,19),(9,12),(15,6),(32,6),(38,3),(44,3),(48,6),(65,6),(71,12),(71,19),(77,19),(77,26),(71,26),(71,33),(65,39),(48,39),(43,42),(37,42),(32,39),(15,39),(9,33),(9,26),(3,26)],
        holes=[rect(11,11,16,14),rect(64,31,69,34)],
        patches=[(7,polygon([(19,10),(61,10),(67,16),(67,30),(61,35),(19,35),(13,29),(13,16)])),
          (0,rect(23,12,57,33)|rect(14,19,66,26)),
          (5,rect(27,16,53,30)),(1,rect(31,19,49,27)),
          (4,rect(35,19,45,27)|rect(31,21,49,25))],
        palette=[6,10,11,13,16,28,29,31],specials=[(29,26,17),(29,54,30),(6,23,30),(28,57,16),(31,39,15)]),
      'alloy_rift_valley':dict(title='合金裂谷',row=0,
        outline=[(3,19),(11,18),(8,12),(15,8),(24,6),(31,10),(38,3),(44,3),(48,8),(56,5),(65,9),(71,14),(68,18),(77,19),(77,26),(69,28),(71,34),(63,39),(52,36),(46,38),(43,42),(37,42),(32,38),(22,41),(13,36),(9,30),(3,26)],
        holes=[ellipse(17,12,3,2),ellipse(64,33,3,2)],
        patches=[(4,stroke([(17,31),(26,27),(33,20),(43,17),(50,12),(61,11)],4.6)),
          (7,stroke([(18,31),(27,27),(34,21),(44,18),(51,13),(60,12)],2.4)),
          (2,stroke([(18,29),(26,25),(32,19),(42,16),(49,11),(57,10)],.85)),
          (5,ellipse(25,14,6,3)|ellipse(56,30,7,3)),
          (3,ellipse(25,14,3,1)|ellipse(56,30,4,1))],
        palette=[1,3,8,14,18,21,25],specials=[(18,28,28),(14,49,16),(3,57,29),(1,23,16)]),
      'magnetite_hills':dict(title='磁铁丘陵',row=7,
        outline=[(3,19),(10,16),(13,10),(21,7),(29,10),(33,7),(38,3),(44,3),(50,9),(58,7),(66,10),(70,16),(68,19),(77,19),(77,26),(69,28),(66,34),(58,38),(50,35),(43,42),(37,42),(31,36),(23,40),(15,36),(10,30),(3,26)],
        holes=[ellipse(20,11,3,1.5)],
        patches=[(4,polygon([(15,23),(24,12),(34,21),(26,33)])|polygon([(43,23),(55,11),(66,24),(55,35)])),
          (8,polygon([(20,24),(25,17),(31,24),(26,29)])|polygon([(48,23),(55,16),(61,24),(55,30)])),
          (0,stroke([(18,24),(24,16),(29,20)],.65)|stroke([(47,24),(54,15),(60,20)],.65)),
          (5,stroke([(31,32),(39,30),(45,32)],1.1))],
        palette=[17,18,25,26,32,14],specials=[(32,25,21),(17,55,25),(18,22,30),(18,60,16)]),
      'ore_vein_field':dict(title='矿脉旷野',row=5,
        outline=[(3,19),(11,18),(12,10),(19,8),(27,9),(32,6),(38,3),(44,3),(48,7),(57,5),(65,10),(70,16),(68,18),(77,19),(77,26),(69,28),(67,34),(60,40),(51,38),(45,38),(43,42),(37,42),(32,38),(25,40),(16,37),(11,31),(3,26)],
        holes=[stroke([(10,10),(15,12),(18,16)],1.2),ellipse(63,33,2.5,2)],
        patches=[(7,stroke([(17,31),(26,27),(34,23),(43,20),(53,14),(62,12)],2.8)|stroke([(34,23),(30,16),(25,12)],2.2)|stroke([(43,20),(48,28),(56,32)],2.2)),
          (1,stroke([(17,31),(26,27),(34,23),(43,20),(53,14),(62,12)],.8)|stroke([(34,23),(30,16),(25,12)],.6)),
          (3,stroke([(43,21),(49,28),(56,32)],.7)),
          (0,ellipse(21,18,4,2)|ellipse(58,24,4,2))],
        palette=[10,11,12,18,18,25,26],specials=[(18,28,16),(18,55,15),(25,21,30),(10,53,30)]),
      'rusted_plains':dict(title='锈蚀平原',row=6,
        outline=[(3,19),(10,17),(9,12),(16,7),(27,7),(32,10),(38,3),(44,3),(48,9),(61,6),(69,11),(70,18),(77,19),(77,26),(69,29),(70,35),(60,39),(51,37),(43,42),(37,42),(31,38),(24,40),(15,36),(10,30),(3,26)],
        holes=[polygon([(14,7),(21,9),(23,12),(18,13),(15,11)])],
        patches=[(3,polygon([(16,16),(27,12),(35,18),(49,14),(61,17),(65,27),(55,33),(42,30),(30,35),(18,30)])),
          (5,stroke([(18,22),(27,20),(35,23),(45,22),(52,25),(63,24)],2.2)),
          (7,ellipse(24,16,5,2)|ellipse(52,32,7,2)|ellipse(61,18,4,2)),
          (4,rect(29,26,34,29)|rect(47,15,54,17)),
          (6,rect(30,27,33,28)|rect(48,16,53,16))],
        palette=[3,4,7,9,14,15,21,23],specials=[(15,19,17),(9,58,30),(3,36,16),(23,52,18)]),
      'smelting_ruins':dict(title='冶炼遗迹',row=7,
        outline=[(3,19),(10,19),(10,9),(23,9),(23,5),(34,5),(38,3),(44,3),(47,7),(58,7),(58,10),(70,10),(70,19),(77,19),(77,26),(70,26),(70,36),(58,36),(58,40),(46,40),(43,42),(37,42),(34,38),(21,38),(21,35),(10,35),(10,26),(3,26)],
        holes=[rect(10,10,16,15),rect(64,30,71,34)],
        patches=[(6,rect(18,12,62,33)),
          (4,rect(23,16,57,29)|rect(16,21,64,25)),
          (0,rect(26,19,54,27)),
          (3,rect(19,12,28,15)|rect(51,30,61,33)|rect(59,17,62,25)),
          (5,rect(19,12,28,13)|rect(51,32,61,33)|rect(61,17,62,25))],
        palette=[3,4,6,7,19,20,23,33],specials=[(6,24,17),(19,57,17),(20,58,28),(33,23,31),(3,40,15)]),
      'gate_steel_dome':dict(title='钢穹之门',row=4,
        outline=[(3,19),(10,19),(10,12),(16,12),(16,6),(28,6),(28,9),(35,9),(38,3),(44,3),(45,9),(52,9),(52,6),(64,6),(64,12),(70,12),(70,19),(77,19),(77,26),(70,26),(70,33),(64,33),(64,39),(52,39),(52,36),(45,36),(43,42),(37,42),(35,36),(28,36),(28,39),(16,39),(16,33),(10,33),(10,26),(3,26)],
        holes=[rect(17,8,21,11),rect(59,34,63,37)],
        patches=[(7,rect(21,12,59,33)),
          (0,rect(27,15,53,30)|rect(17,20,63,26)),
          (5,rect(30,18,50,28)),
          (1,rect(35,18,45,28)|rect(30,21,50,25)),
          (8,rect(21,12,25,17)|rect(55,28,59,33))],
        palette=[3,4,8,13,14,19,20,22],specials=[(19,27,18),(19,53,29),(20,27,30),(20,53,17),(13,40,16)]),
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
        path = 'MapContainer/Ground/TileMapLayer2' if i == 0 else f'MapContainer/Ground/GoldDetail{i+1}'
        layers[path] = tiles((patch & inner) - PORT_GUARD, row)

    # 用户要求不使用障碍；保留原节点和资源，但不放置任何瓦片。
    obstacle_cells = {}
    obstacle_groups = []
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
        externals.append(f'[ext_resource type="Texture2D" path="res://{rel}" id="gold_decor_{asset}"]\n\n')
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
        if '/GoldDetail' in key:
            nodes.append(f'[node name="{key.split("/")[-1]}" type="TileMapLayer" parent="MapContainer/Ground"]\n'
                         f'tile_set = SubResource("TileSet_g36n5")\ntile_map_data = PackedByteArray("{encode(cells)}")\n\n')
    nodes.append('[node name="Decorations" type="Node2D" parent="MapContainer"]\nz_index = -1\ntexture_filter = 1\n\n')
    for i,d in enumerate(layout['decorations']):
        nodes.append(f'[node name="Decor{i+1:02d}" type="Sprite2D" parent="MapContainer/Decorations"]\n'
                     f'position = Vector2({d["x"]}, {d["y"]})\nscale = Vector2({d["scale"]}, {d["scale"]})\n'
                     f'texture = ExtResource("gold_decor_{d["asset"]}")\nflip_h = {str(d["flip"]).lower()}\n\n')
    text=old.splitlines()[0]+'\n\n'+''.join(externals)+''.join(REF_SUBS)+''.join(nodes)
    path.write_text(text.rstrip()+'\n',encoding='utf-8',newline='\n')


def draw_cells(canvas,cells,atlas=ATLAS):
    for (x,y),(col,row) in cells.items():
        tile=atlas.crop((col*16,row*16,(col+1)*16,(row+1)*16))
        canvas.alpha_composite(tile,(x*16,y*16))


def preview(layout, bridge_mask):
    image=Image.new('RGBA',(1280,720),(21,23,28,255))
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
    # 先生成整批布局再写场景，保证十二张图使用同一份已备份配置。
    paths=sorted((ROOT/'scenes/map_scenes/map_env/gold').rglob('*.tscn'))
    for path in paths:
        layouts.append(author_layout(path.stem,specs[path.stem]))
    for path,layout in zip(paths,layouts):
        write_scene(path,layout)
        for state,mask in [('closed',0),('open',15)]:
            preview(layout,mask).save(OUT/f'{path.stem}.{state}.png')
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
    for state in ['closed','open']:
        sheet=Image.new('RGB',(1920,1600),(16,19,25))
        draw=ImageDraw.Draw(sheet)
        for i,layout in enumerate(layouts):
            x,y=(i%3)*640,(i//3)*400
            sample=Image.open(OUT/f'{layout["name"]}.{state}.png').resize((640,360),Image.Resampling.NEAREST)
            sheet.paste(sample,(x,y+36))
            draw.text((x+12,y+6),layout['title'],font=font,fill=(239,222,197))
        sheet.save(OUT/f'gold_contact_{state}.png')
    serial=[{**layout,'layers':{k:[[x,y,c,r] for (x,y),(c,r) in cells.items()] for k,cells in layout['layers'].items()}}
            for layout in layouts]
    (OUT/'layouts.json').write_text(json.dumps(serial,ensure_ascii=False),encoding='utf-8')
    (OUT/'obstacle_groups.json').write_text(json.dumps({l['name']:l['obstacle_groups'] for l in layouts},indent=2),encoding='utf-8')
    print(json.dumps([{'scene':l['name'],'layers':len(l['layers']),'decorations':len(l['decorations']),
                       'obstacle_groups':len(l['obstacle_groups']),'tiles':sum(map(len,l['layers'].values()))}
                      for l in layouts],indent=2))


if __name__=='__main__':
    main()
