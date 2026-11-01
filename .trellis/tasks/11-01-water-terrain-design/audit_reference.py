from pathlib import Path
import re, json, hashlib, base64, struct
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).parent / 'research'
OUT.mkdir(exist_ok=True)
REF = ROOT / 'scenes/map_scenes/map_env/water/main/coral_shoal.tscn'
raw = REF.read_bytes()
backup = OUT / 'coral_shoal.before.tscn'
if not backup.exists():
    backup.write_bytes(raw)
text = raw.decode('utf-8')
blocks = re.findall(r'^\[sub_resource [^\n]+\]\n(?:(?!^\[).|\n)*', text, re.M)
resources = {re.search(r'\bid="([^"]+)"', b.splitlines()[0])[1]: b for b in blocks}
layers = []
for block in re.findall(r'^\[node [^\n]+\]\n(?:(?!^\[).|\n)*', text, re.M):
    header = block.splitlines()[0]
    if 'type="TileMapLayer"' not in header:
        continue
    name = re.search(r'name="([^"]+)"', header)[1]
    parent = re.search(r'parent="([^"]+)"', header)[1]
    tid = re.search(r'tile_set = SubResource\("([^"]+)"\)', block)[1]
    tileset = resources[tid]
    aid = re.search(r'sources/\d+ = SubResource\("([^"]+)"\)', tileset)[1]
    atlas = resources[aid]
    encoded = re.search(r'tile_map_data = PackedByteArray\("([^"]*)"\)', block)
    cells = list(struct.iter_unpack('<hhHHHH', base64.b64decode(encoded[1])[2:])) if encoded else []
    layers.append({
        'node': parent + '/' + name,
        'tileset': tid, 'atlas': aid,
        'tile_size': re.search(r'tile_size = ([^\n]+)', tileset)[1] if 'tile_size =' in tileset else '16 default',
        'region_size': re.search(r'texture_region_size = ([^\n]+)', atlas)[1] if 'texture_region_size =' in atlas else '16 default',
        'tiles_defined': len(re.findall(r'^\d+:\d+/0 =', atlas, re.M)),
        'collision_polygons': len(re.findall(r'/polygon_\d+/points =', atlas)),
        'physics': [v for v in tileset.splitlines() if 'physics_layer' in v],
        'cells': len(cells),
        'bounds': [min(c[0] for c in cells), min(c[1] for c in cells), max(c[0] for c in cells), max(c[1] for c in cells)] if cells else None,
        'configuration_without_cells': re.sub(r'^tile_map_data = .*\n', '', block, flags=re.M),
    })
assets = ROOT / 'res/UI/生态图集/水-生态'
atlas_image = Image.open(assets / '水-生态.png').convert('RGBA')
atlas_image.resize((1024, 1024), Image.Resampling.NEAREST).save(OUT / 'atlas_large.png')
decorations = sorted((assets / '装饰物').glob('*.png'))
font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 18)
sheet = Image.new('RGB', (800, ((len(decorations)+3)//4)*140), (29, 35, 40))
draw = ImageDraw.Draw(sheet)
for i, path in enumerate(decorations):
    im = Image.open(path).convert('RGBA')
    factor = min(4, 96/max(im.size))
    im = im.resize((round(im.width*factor), round(im.height*factor)), Image.Resampling.NEAREST)
    x, y = (i % 4)*200, (i // 4)*140
    sheet.paste(im, (x+80-im.width//2, y+10), im)
    draw.text((x+5, y+112), path.stem, font=font, fill='white')
sheet.save(OUT / 'decorations_sheet.png')
paths = list((ROOT/'scenes').rglob('*.tscn')) + list((ROOT/'scripts/map_scripts').glob('*.gd')) + list(assets.rglob('*.png')) + list((ROOT/'resources/map').rglob('*.tres')) + [ROOT/'project.godot']
protected = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
baseline = OUT / 'protected_baseline.json'
if not baseline.exists():
    baseline.write_text(json.dumps(protected, ensure_ascii=False, indent=2), encoding='utf-8')
report = {'reference_sha256': hashlib.sha256(raw).hexdigest(), 'atlas_size': atlas_image.size, 'layers': layers, 'decorations': [{'path': p.relative_to(ROOT).as_posix(), 'size': Image.open(p).size} for p in decorations]}
(OUT/'reference_audit.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({'atlas_size': atlas_image.size, 'decorations': len(decorations), 'layers': [{k:v for k,v in layer.items() if k!='configuration_without_cells'} for layer in layers]}, ensure_ascii=False, indent=2))
