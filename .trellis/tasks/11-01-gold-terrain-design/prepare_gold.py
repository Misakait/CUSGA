from pathlib import Path
import hashlib,json,re,shutil
ROOT=Path(__file__).resolve().parents[3]
OUT=Path(__file__).parent/'research'
OUT.mkdir(exist_ok=True)
(OUT/'before').mkdir(exist_ok=True)
paths=sorted((ROOT/'scenes/map_scenes/map_env/gold').rglob('*.tscn'))
for p in paths:
 target=OUT/'before'/p.name
 if not target.exists(): shutil.copy2(p,target)
ref=OUT/'copper_rust_forest.before.tscn'
if not ref.exists(): shutil.copy2(ROOT/'scenes/map_scenes/map_env/gold/main/copper_rust_forest.tscn',ref)
baseline=OUT/'protected_baseline.json'
if not baseline.exists():
 protected=[]
 for d in ['scenes','scripts','core','resources','res/UI/生态图集']:
  protected.extend(p for p in (ROOT/d).rglob('*') if p.is_file())
 protected.extend([ROOT/'project.godot',ROOT/'agent.local.md'])
 baseline.write_text(json.dumps({p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in protected},ensure_ascii=False,indent=2),encoding='utf-8')
print('Backup ready:',len(paths),'scenes')
try:
 from PIL import Image,ImageDraw,ImageFont
 atlas=Image.open(ROOT/'res/UI/生态图集/金-生态/金-生态.png').convert('RGBA')
 atlas.resize((atlas.width*3,atlas.height*3),Image.Resampling.NEAREST).save(OUT/'gold_atlas_large.png')
 decors=sorted((ROOT/'res/UI/生态图集/金-生态/装饰物').glob('*.png'))
 sheet=Image.new('RGB',(880,((len(decors)+7)//8)*115),(34,31,29))
 draw=ImageDraw.Draw(sheet)
 for i,p in enumerate(decors):
  im=Image.open(p).convert('RGBA'); im.thumbnail((76,76),Image.Resampling.NEAREST)
  x,y=(i%8)*110,(i//8)*115
  sheet.paste(im,(x+16,y+8),im);draw.text((x+5,y+88),p.stem[:18],fill='white')
 sheet.save(OUT/'decorations_sheet.png')
 print('Atlas',atlas.size,'decorations',len(decors))
except ImportError: print('Pillow unavailable')
