"""独立读取火生态场景，审计配置、完整障碍、四角拼接和桥状态；不运行游戏。"""
from collections import Counter, defaultdict, deque
from functools import lru_cache
from pathlib import Path
import base64
import hashlib
import json
import math
import re
import struct

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).parent / 'research'
DIRS = ('Up', 'Right', 'Down', 'Left')
ORIGINS = ((0, 0), (4, 0), (8, 0), (12, 0), (0, 4), (4, 4))
GROUND = 'MapContainer/Ground/TileMapLayer'
OBSTACLE = 'MapContainer/Obstack/TileMapLayer'


def parse(text):
    result = {kind: {} for kind in ('node', 'sub_resource', 'ext_resource')}
    for match in re.finditer(r'^\[(node|sub_resource|ext_resource)[^\n]*\]\n(?:(?!^\[).|\n)*', text, re.M):
        block = match[0]
        kind = match[1]
        header = block.splitlines()[0]
        if kind == 'node':
            name = re.search(r'name="([^"]+)"', header)[1]
            parent = re.search(r'parent="([^"]+)"', header)
            key = parent[1] + '/' + name if parent and parent[1] != '.' else name
        else:
            key = re.search(r' id="([^"]+)"', header)[1]
        assert key not in result[kind], ('重复区块', kind, key)
        result[kind][key] = block
    return result


def decode(block):
    match = re.search(r'tile_map_data = PackedByteArray\("([^"]*)"\)', block)
    if not match:
        return {}
    raw = base64.b64decode(match[1], validate=True)
    assert raw[:2] == b'\0\0' and (len(raw) - 2) % 12 == 0, '瓦片编码无效'
    result = {}
    for x, y, source, col, row, alternative in struct.iter_unpack('<hhHHHH', raw[2:]):
        assert (x, y) not in result, ('重复瓦片', x, y)
        result[x, y] = (source, col, row, alternative)
    return result


def resource_for(scene, block):
    tid = re.search(r'tile_set = SubResource\("([^"]+)"\)', block)[1]
    tileset = scene['sub_resource'][tid]
    aid = re.search(r'sources/0 = SubResource\("([^"]+)"\)', tileset)[1]
    return tileset, scene['sub_resource'][aid]


def resource_chain(scene, block):
    """逐级保留实际资源定义，包括压缩纹理的导入路径。"""
    result = {}
    pending = re.findall(r'SubResource\("([^"]+)"\)', block)
    while pending:
        rid = pending.pop()
        if rid in result:
            continue
        value = scene['sub_resource'][rid].strip()
        result[rid] = value
        pending.extend(re.findall(r'SubResource\("([^"]+)"\)', value))
        for eid in re.findall(r'ExtResource\("([^"]+)"\)', value):
            result['external:' + eid] = scene['ext_resource'][eid].strip()
    return result


def normalized_layer(block):
    return re.sub(r'^tile_map_data = .*\n', '', block.split('\n', 1)[1], flags=re.M).strip()


def transformed(scene, key, point):
    """保留原始微小旋转，并按节点链把碰撞多边形转换到房间坐标。"""
    while key:
        block = scene['node'][key]
        x, y = point
        scale = re.search(r'^scale = Vector2\(([^,]+), ([^)]+)\)', block, re.M)
        if scale:
            x *= float(scale[1])
            y *= float(scale[2])
        rotation = re.search(r'^rotation = (.+)', block, re.M)
        if rotation:
            angle = float(rotation[1])
            x, y = x * math.cos(angle) - y * math.sin(angle), x * math.sin(angle) + y * math.cos(angle)
        position = re.search(r'^position = Vector2\(([^,]+), ([^)]+)\)', block, re.M)
        if position:
            x += float(position[1])
            y += float(position[2])
        point = x, y
        parent = re.search(r'parent="([^"]+)"', block.splitlines()[0])
        key = parent[1] if parent and parent[1] != '.' else ''
    return point


def polygons(scene, key, cells):
    tileset, atlas = resource_for(scene, scene['node'][key])
    assert 'collision_layer = 32' in tileset and 'collision_mask = 16' in tileset, (key, '碰撞层错误')
    result = []
    for (x, y), (_, col, row, _) in cells.items():
        pattern = rf'^{col}:{row}/0/physics_layer_0/polygon_\d+/points = PackedVector2Array\(([^\n]+)\)'
        for numbers in re.findall(pattern, atlas, re.M):
            values = list(map(float, numbers.split(',')))
            assert len(values) >= 6 and len(values) % 2 == 0
            result.append([transformed(scene, key, (x * 16 + 8 + values[i], y * 16 + 8 + values[i + 1]))
                           for i in range(0, len(values), 2)])
    return result


def cross(o, a, b):
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def hull(points):
    points = sorted(set(points))
    lower, upper = [], []
    for point in points:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], point) <= 0:
            lower.pop()
        lower.append(point)
    for point in reversed(points):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], point) <= 0:
            upper.pop()
        upper.append(point)
    return lower[:-1] + upper[:-1]


@lru_cache(maxsize=16384)
def expanded_hull(poly):
    return hull([(x + dx, y + dy) for x, y in poly
                 for dx in (-14.667, 14.667) for dy in (-7.867, 7.867)])


def blocked_samples(polys):
    """使用实际多边形和玩家胶囊包围盒求保守碰撞区，不把4×4障碍当满格。"""
    blocked = set()
    for poly in polys:
        expanded = expanded_hull(tuple(poly))
        xs, ys = zip(*expanded)
        for y in range(max(0, math.ceil((min(ys) - 4) / 8)), min(89, math.floor((max(ys) - 4) / 8)) + 1):
            for x in range(max(0, math.ceil((min(xs) - 4) / 8)), min(159, math.floor((max(xs) - 4) / 8)) + 1):
                point = (x * 8 + 4, y * 8 + 4)
                if all(cross(expanded[i - 1], expanded[i], point) >= -1e-8 for i in range(len(expanded))):
                    blocked.add((x, y))
    return blocked


def blocked_point(polys, point):
    for poly in polys:
        expanded = expanded_hull(tuple(poly))
        if all(cross(expanded[i - 1], expanded[i], point) >= -1e-8 for i in range(len(expanded))):
            return True
    return False


def supports(cells, point):
    x, y = point
    col = cells.get((x // 2, y // 2), (0, 0, 0, 0))[1]
    bit = ((8, 4), (2, 1))[y % 2][x % 2]
    return bool(col & bit)


def reachability(scene, layers):
    actual_polys = {key: polygons(scene, key, cells) for key, cells in layers.items()
                    if any('/' + role + '/' in key for role in ('Boundary', 'Obstack', 'BridgeBoundary', 'BridgeWithBoundary'))}
    collision = {key: blocked_samples(polys) for key, polys in actual_polys.items()}
    fixed = collision['MapContainer/Boundary/TileMapLayer'] | collision[OBSTACLE]
    counts = []
    for mask in range(16):
        blocked = set(fixed)
        active_polys = actual_polys['MapContainer/Boundary/TileMapLayer'] + actual_polys[OBSTACLE]
        support_layers = [cells for key, cells in layers.items() if '/Ground/' in key]
        for direction, bit in zip(DIRS, (1, 2, 4, 8)):
            active = 'BridgeBoundary' if mask & bit else 'BridgeWithBoundary'
            blocked.update(collision[f'MapContainer/{active}/{direction}{active}'])
            active_polys += actual_polys[f'MapContainer/{active}/{direction}{active}']
            if mask & bit:
                support_layers.append(layers[f'MapContainer/BridgeContainer/{direction}Bridge'])
        # 玩家出生节点(640,360)，碰撞中心向下16.8像素，取最近8像素采样点。
        start = (80, 47)
        assert start not in blocked, ('出生点被挡', mask)
        assert not blocked_point(active_polys, (640, 376.8)), ('实际出生碰撞中心被挡', mask)
        visited, queue = {start}, deque([start])
        while queue:
            x, y = queue.popleft()
            for point in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= point[0] < 160 and 0 <= point[1] < 90 and point not in blocked and point not in visited:
                    visited.add(point)
                    queue.append(point)
        void = [point for point in visited if not any(supports(cells, point) for cells in support_layers)]
        assert not void, ('可达透明区域', mask, void[:8])
        exits = [any(y == 0 for x, y in visited), any(x == 159 for x, y in visited),
                 any(y == 89 for x, y in visited), any(x == 0 for x, y in visited)]
        assert exits == [bool(mask & bit) for bit in (1, 2, 4, 8)], ('桥口状态错误', mask, exits)
        for j in range(4):
            for i in range(6):
                px, py = 360 + (i + .5) * 560 / 6, 220 + (j + .5) * 340 / 4
                target = (int(px // 8), int((py + 16.8) // 8))
                assert target in visited, ('物资格不可达', mask, i, j, target)
                assert not blocked_point(active_polys, (px, py + 16.8)), ('实际物资格碰撞中心被挡', mask, i, j)
        counts.append(len(visited))
    return counts


def check_obstacles(layers):
    groups = defaultdict(dict)
    for (x, y), (sid, col, row, alt) in layers[OBSTACLE].items():
        candidates = [(i, ox, oy) for i, (ox, oy) in enumerate(ORIGINS) if ox <= col < ox + 4 and oy <= row < oy + 4]
        assert len(candidates) == 1, ('障碍组坐标错误', col, row)
        index, ox, oy = candidates[0]
        dx, dy = col - ox, row - oy
        groups[index, x - dx, y - dy][dx, dy] = (sid, col, row, alt)
    result = Counter()
    expected = {(x, y) for x in range(4) for y in range(4)}
    protected = [(640, 360), (640, 376.8)] + [(360 + (i + .5) * 560 / 6, 220 + (j + .5) * 340 / 4)
                                                         for j in range(4) for i in range(6)]
    for (index, x, y), cells in groups.items():
        assert set(cells) == expected, ('障碍组缺格或打散', index, x, y, len(cells))
        assert all(layers[GROUND].get((x + dx, y + dy), (0, 0, 0, 0))[1] == 15 for dx, dy in expected), ('障碍组悬空', index, x, y)
        assert not any(x * 16 <= px < (x + 4) * 16 and y * 16 <= py < (y + 4) * 16 for px, py in protected), ('障碍覆盖出生或物资格', index, x, y)
        result[index] += 1
    assert groups, '未使用完整障碍组'
    return dict(sorted(result.items()))


def check_scene(path, reference):
    text = path.read_text(encoding='utf-8')
    scene = parse(text)
    before_text = (OUT / 'before' / path.name).read_text(encoding='utf-8')
    before = parse(before_text)
    assert text.splitlines()[0] == before_text.splitlines()[0], '场景UID改变'
    layers = {key: decode(block) for key, block in scene['node'].items() if 'type="TileMapLayer"' in block.splitlines()[0]}
    for key, block in reference['node'].items():
        if 'type="TileMapLayer"' in block.splitlines()[0]:
            assert normalized_layer(scene['node'][key]) == normalized_layer(block), (key, '图层配置变化')
            assert resource_chain(scene, scene['node'][key]) == resource_chain(reference, block), (key, '完整资源链变化')
    for key, block in before['node'].items():
        if 'type="TileMapLayer"' not in block.splitlines()[0]:
            cleaned = lambda value: re.sub(r'^z_index = .*\n', '', value, flags=re.M).strip()
            assert cleaned(block) == cleaned(scene['node'][key]), (key, '原有节点身份或配置变化')
    for block in scene['ext_resource'].values():
        relative = re.search(r'path="res://([^"]+)"', block)[1]
        assert (ROOT / relative).exists(), ('外部资源缺失', relative)
    for rid, block in before['ext_resource'].items():
        if not block.startswith('[ext_resource type="Texture2D"'):
            assert scene['ext_resource'].get(rid, '').strip() == block.strip(), ('脚本或地形资源配置变化', rid)
    for key, cells in layers.items():
        tileset, atlas = resource_for(scene, scene['node'][key])
        defined = {tuple(map(int, pair)) for pair in re.findall(r'^(\d+):(\d+)/0 =', atlas, re.M)}
        for (x, y), (sid, col, row, alt) in cells.items():
            assert 0 <= x < 80 and 0 <= y < 45 and sid == 0 and alt == 0, (key, '越界或变体', x, y, sid, alt)
            assert (col, row) in defined, (key, '未定义瓦片', col, row)
        if '/Ground/' in key or '/BridgeContainer/' in key:
            assert 'physics_layer' not in tileset and '/points' not in atlas, (key, '地表有碰撞')
    decorations = scene['node']['MapContainer/Decorations']
    assert 'type="Node2D"' in decorations and 'z_index = -1' in decorations
    decoration_count = 0
    for key, block in scene['node'].items():
        if '/Decorations/' in key:
            decoration_count += 1
            assert not any(word in block for word in ('Collision', 'Physics', 'script =', 'z_as_relative = false')), (key, '装饰碰撞或额外行为')
            assert not re.search(r'^z_index = [1-9]', block, re.M), (key, '装饰挡住玩家')
    assert decoration_count > 0, '缺少装饰'
    for container in ('Ground', 'Boundary', 'BridgeContainer', 'BridgeWithBoundary', 'BridgeBoundary', 'Obstack'):
        block = scene['node'][f'MapContainer/{container}']
        z = re.search(r'^z_index = (-?\d+)', block, re.M)
        assert z and int(z[1]) < -1, (container, '图层顺序错误')
    ground = layers[GROUND]
    for key, cells in layers.items():
        if '/Ground/' not in key:
            continue
        for x in range(80):
            for y in range(45):
                col = cells.get((x, y), (0, 0, 0, 0))[1]
                right = cells.get((x + 1, y), (0, 0, 0, 0))[1]
                below = cells.get((x, y + 1), (0, 0, 0, 0))[1]
                if x < 79:
                    assert bool(col & 4) == bool(right & 8) and bool(col & 1) == bool(right & 2), ('地形水平毛刺', key, x, y)
                if y < 44:
                    assert bool(col & 2) == bool(below & 8) and bool(col & 1) == bool(below & 4), ('地形垂直毛刺', key, x, y)
    bridge_lengths = {}
    for direction, approach in zip(DIRS, ((40, 3), (76, 22), (40, 41), (3, 22))):
        cells = layers[f'MapContainer/BridgeContainer/{direction}Bridge']
        rows = {value[2] for value in cells.values()}
        assert rows == {ground[approach][2]} and ground[approach][1] == 15, (direction, '桥面与引道不匹配')
        axis = 1 if direction in ('Up', 'Down') else 0
        length = max(point[axis] for point in cells) - min(point[axis] for point in cells) + 1
        assert length <= 3, (direction, '桥过长', length)
        bridge_lengths[direction] = length
    obstacle_groups = check_obstacles(layers)
    reachable = reachability(scene, layers)
    special = sum(value[1] in (6, 7, 9, 11, 13, 14) for value in ground.values())
    assert special > 0, '未使用内角或对角特殊瓦片'
    return dict(scene=path.relative_to(ROOT).as_posix(), layer_count=len(layers), decorations=decoration_count,
                bridge_combinations=16, resource_slots=24, minimum_reachable_samples=min(reachable),
                obstacle_groups=obstacle_groups, special_corner_tiles=special, bridge_lengths_tiles=bridge_lengths,
                all_ground_layers_seam_checked=True,
                outline_signature=hashlib.sha256(str(sorted((point, value[1]) for point, value in ground.items())).encode()).hexdigest())


def main():
    reference = parse((OUT / 'ash_plain.before.tscn').read_text(encoding='utf-8'))
    paths = sorted((ROOT / 'scenes/map_scenes/map_env/fire').rglob('*.tscn'))
    errors, report = [], []
    assert len(paths) == 12, ('场景数量', len(paths))
    for path in paths:
        try:
            report.append(check_scene(path, reference))
        except (AssertionError, KeyError, AttributeError, ValueError) as error:
            errors.append(dict(scene=path.relative_to(ROOT).as_posix(), error=str(error)))
    if len(report) == 12:
        if len({item['outline_signature'] for item in report}) != 12:
            errors.append(dict(error='存在相同地形轮廓'))
        used = {int(group) for item in report for group in item['obstacle_groups']}
        if used != set(range(6)):
            errors.append(dict(error='未使用全部六组障碍', used=sorted(used)))
    baseline = json.loads((OUT / 'protected_baseline.json').read_text(encoding='utf-8'))
    changed = [relative for relative, digest in baseline.items()
               if not (ROOT / relative).exists() or hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() != digest]
    unexpected = [relative for relative in changed if not relative.startswith('scenes/map_scenes/map_env/fire/')]
    if unexpected:
        errors.append(dict(error='保护范围外文件变化', files=unexpected))
    result = dict(passed=not errors, scene_count=len(paths), checked_scenes=len(report),
                  bridge_combinations=len(report) * 16, runtime_tested=False,
                  method='实际场景资源与碰撞多边形，玩家胶囊包围盒保守膨胀，8像素采样；不是物理引擎验证',
                  scope_changes=changed, scenes=report, errors=errors)
    for filename in ('static_validation.json', 'independent_review.json'):
        (OUT / filename).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if not errors else 1


if __name__ == '__main__':
    raise SystemExit(main())
