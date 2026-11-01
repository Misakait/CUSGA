"""读取实际场景文件，审计参考资源、拼接、碰撞围合与可达性；不启动 Godot 游戏。"""
from pathlib import Path
from collections import deque
import base64
import hashlib
import json
import math
import re
import struct
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).parent / 'research'
REFERENCE = (OUT/'coral_shoal.before.tscn').read_text(encoding='utf-8')
DIRS = ['Up','Right','Down','Left']


def parse(text):
    sections = re.findall(r'^\[(node|sub_resource|ext_resource)[^\n]*\]\n(?:(?!^\[).|\n)*',text,re.M)
    del sections
    groups = {}
    for kind in ['node','sub_resource','ext_resource']:
        result = {}
        for b in re.findall(r'^\['+kind+r'[^\n]*\]\n(?:(?!^\[).|\n)*',text,re.M):
            h = b.splitlines()[0]
            if kind == 'node':
                n = re.search(r'name="([^"]+)"',h)[1]
                p = re.search(r'parent="([^"]+)"',h)
                key = p[1]+'/'+n if p and p[1]!='.' else n
            else:
                key = re.search(r'id="([^"]+)"',h)[1]
            result[key] = b
        groups[kind] = result
    return groups


def decode(block):
    m = re.search(r'tile_map_data = PackedByteArray\("([^"]*)"\)',block)
    if not m:
        return {}
    raw = base64.b64decode(m[1])
    assert raw[:2] == b'\0\0' and (len(raw)-2)%12==0
    result = {}
    for x,y,source,col,row,alternative in struct.iter_unpack('<hhHHHH',raw[2:]):
        assert (x,y) not in result, ('duplicate cell',x,y)
        result[x,y]=(source,col,row,alternative)
    return result


def resource_for(scene, block):
    tid = re.search(r'tile_set = SubResource\("([^"]+)"\)',block)[1]
    ts = scene['sub_resource'][tid]
    aid = re.search(r'sources/0 = SubResource\("([^"]+)"\)',ts)[1]
    return ts,scene['sub_resource'][aid]


def normalize_resource(block):
    return re.sub(r'ExtResource\("[^"]+"\)','ExtResource("TEXTURE")',block).strip()


def normalize_layer(block):
    body = block.split('\n',1)[1]
    return re.sub(r'^tile_map_data = .*\n','',body,flags=re.M).strip()


def colliders(scene, key, cells):
    ts,atlas = resource_for(scene,scene['node'][key])
    assert 'collision_layer = 32' in ts and 'collision_mask = 16' in ts
    blocked=[]
    for (x,y),(sid,col,row,alt) in cells.items():
        pattern=rf'^{col}:{row}/0/physics_layer_0/polygon_\d+/points = PackedVector2Array\(([^\n]+)\)'
        for numbers in re.findall(pattern,atlas,re.M):
            p=list(map(float,numbers.split(',')))
            blocked.append([(x*16+8+p[i],y*16+8+p[i+1]) for i in range(0,len(p),2)])
    return blocked


def verify_reachability(scene,layers,mask):
    active_polys=[]
    support=dict(layers['MapContainer/Ground/TileMapLayer'])
    for key in ['MapContainer/Boundary/TileMapLayer','MapContainer/Obstack/TileMapLayer']:
        active_polys += colliders(scene,key,layers[key])
    for d,bit in zip(DIRS,[1,2,4,8]):
        if mask&bit:
            active_polys += colliders(scene,f'MapContainer/BridgeBoundary/{d}BridgeBoundary',layers[f'MapContainer/BridgeBoundary/{d}BridgeBoundary'])
            support.update(layers[f'MapContainer/BridgeContainer/{d}Bridge'])
        else:
            active_polys += colliders(scene,f'MapContainer/BridgeWithBoundary/{d}BridgeWithBoundary',layers[f'MapContainer/BridgeWithBoundary/{d}BridgeWithBoundary'])
    # 使用玩家 0.4 倍横向胶囊的包围盒（宽 29.33、高 15.73 像素）保守膨胀碰撞。
    # 在 8 像素步长上做搜索；这是静态布局审计，不代替物理引擎运行测试。
    blocked=Image.new('1',(160,90))
    draw=ImageDraw.Draw(blocked)
    for poly in active_polys:
        xs,ys=zip(*poly)
        assert sorted(set(xs))==[min(xs),max(xs)] and sorted(set(ys))==[min(ys),max(ys)]
        x0=math.ceil((min(xs)-14.667-4)/8)
        x1=math.floor((max(xs)+14.667-4)/8)
        y0=math.ceil((min(ys)-7.867-4)/8)
        y1=math.floor((max(ys)+7.867-4)/8)
        draw.rectangle((x0,y0,x1,y1),fill=1)
    pixels=blocked.load()
    # 玩家节点为 (640,360)，碰撞中心向下偏移 42×0.4 像素。
    start=(80,47)
    assert not pixels[start],('spawn blocked',mask)
    visited={start}
    queue=deque([start])
    while queue:
        x,y=queue.popleft()
        for xx,yy in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
            if 0<=xx<160 and 0<=yy<90 and (xx,yy) not in visited and not pixels[xx,yy]:
                visited.add((xx,yy));queue.append((xx,yy))
    assert all(support.get((x//2,y//2),(0,0,0,0))[1]==15 for x,y in visited),('reachable void',mask)
    exits=[any(y==0 for x,y in visited),any(x==159 for x,y in visited),any(y==89 for x,y in visited),any(x==0 for x,y in visited)]
    assert exits==[bool(mask&b) for b in [1,2,4,8]],('wrong exit state',mask,exits)
    for j in range(4):
        for i in range(6):
            x,y=360+(i+.5)*560/6,220+(j+.5)*340/4
            target=(int(x//8),int((y+16.8)//8))
            assert target in visited,('resource slot unreachable',mask,i,j,target)
    return len(visited)


def main():
    ref=parse(REFERENCE)
    report=[]
    outline_signatures=[]
    for path in sorted((ROOT/'scenes/map_scenes/map_env/water').rglob('*.tscn')):
        text=path.read_text(encoding='utf-8')
        scene=parse(text)
        layers={k:decode(b) for k,b in scene['node'].items() if 'type="TileMapLayer"' in b.splitlines()[0]}
        for k,b in ref['node'].items():
            if 'type="TileMapLayer"' not in b.splitlines()[0]:
                continue
            assert normalize_layer(scene['node'][k])==normalize_layer(b),(path,k,'layer configuration')
            ours=resource_for(scene,scene['node'][k]); original=resource_for(ref,b)
            assert [normalize_resource(x) for x in ours]==[normalize_resource(x) for x in original],(path,k,'resource changed')
        for b in scene['ext_resource'].values():
            p=re.search(r'path="res://([^"]+)"',b)[1]
            assert (ROOT/p).exists(),(path,'missing reference',p)
        for key,cells in layers.items():
            ts,atlas=resource_for(scene,scene['node'][key])
            defined={tuple(map(int,p)) for p in re.findall(r'^(\d+):(\d+)/0 =',atlas,re.M)}
            for (x,y),(sid,col,row,alt) in cells.items():
                assert 0<=x<80 and 0<=y<45 and sid==0 and alt==0
                assert (col,row) in defined,(path,key,'undefined atlas cell',col,row)
            if '/Ground/' in key or '/BridgeContainer/' in key:
                assert 'physics_layer' not in ts and '/points' not in atlas,(key,'unexpected collision')
        assert 'z_index = -1' in scene['node']['MapContainer/Decorations']
        for container in ['Ground','Boundary','BridgeContainer','BridgeWithBoundary','BridgeBoundary','Obstack']:
            assert int(re.search(r'z_index = (-?\d+)',scene['node'][f'MapContainer/{container}'])[1]) < -1
        ground=layers['MapContainer/Ground/TileMapLayer']
        outline_signatures.append(hashlib.sha256(str(sorted(ground.items())).encode()).hexdigest())
        for (x,y),(_,col,row,_) in ground.items():
            # 四角位相邻必须一致；直接读场景中的列号而非生成器的数据结构。
            right=ground.get((x+1,y),(0,0,0,0))[1]
            below=ground.get((x,y+1),(0,0,0,0))[1]
            if x<79:
                assert bool(col&4)==bool(right&8) and bool(col&1)==bool(right&2),('horizontal seam',path,x,y)
            if y<44:
                assert bool(col&2)==bool(below&8) and bool(col&1)==bool(below&4),('vertical seam',path,x,y)
        counts=[verify_reachability(scene,layers,m) for m in range(16)]
        report.append(dict(scene=path.relative_to(ROOT).as_posix(),layer_count=len(layers),
                           decorations=sum('/Decorations/' in k for k in scene['node']),bridge_combinations=16,
                           reference_configuration='unchanged',resource_slots=24,reachable_samples=min(counts),
                           special_corner_tiles=sum(v[1] in [6,7,9,11,13,14] for v in ground.values())))
    assert len(set(outline_signatures))==12
    baseline=json.loads((OUT/'protected_baseline.json').read_text(encoding='utf-8'))
    changed=[]
    for rel,digest in baseline.items():
        file=ROOT/rel
        if hashlib.sha256(file.read_bytes()).hexdigest()!=digest:
            changed.append(rel)
    assert all(rel.startswith('scenes/map_scenes/map_env/water/') for rel in changed),changed
    result={'passed':True,'scene_count':len(report),'bridge_combinations':len(report)*16,
            'runtime_tested':False,'scope_changes':changed,'scenes':report}
    (OUT/'static_validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2))


if __name__=='__main__':
    main()
