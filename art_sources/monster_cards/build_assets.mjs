// 怪物卡的 SVG 原稿：复用技能卡调色板，只绘制信息区和边框，游戏内不需要生成工具。
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';
import { palettes } from '../skill_cards/build_assets.mjs';

// 全部结构使用整数坐标；缩放时由 Godot 的最近邻采样保留像素轮廓。
const rect = (x,y,w,h,c) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${c}"/>`;
const path = (d,c) => `<path d="${d}" fill="${c}"/>`;
const step = (x,y,w,h,c) => path(`M${x+3} ${y}H${x+w-3}V${y+2}H${x+w-1}V${y+4}H${x+w}V${y+h-4}H${x+w-1}V${y+h-2}H${x+w-3}V${y+h}H${x+3}V${y+h-2}H${x+1}V${y+h-4}H${x}V${y+4}H${x+1}V${y+2}H${x+3}Z`,c);
const svg = (w,h,s) => `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" shape-rendering="crispEdges">\n${s}\n</svg>\n`;

function front(key) {
  const p=palettes[key];
  let s=step(1,3,98,137,'#38333b')+step(0,0,100,137,p.ink)
    +step(2,2,96,133,p.shade)+step(3,3,94,129,p.main);
  s+=rect(7,3,86,2,p.light)+rect(3,7,2,119,p.light)+rect(7,130,86,2,p.ink);
  // 顶部名称、五行条和五行属性列表只承载动态信息，不预留插画区域。
  s+=step(7,7,86,19,p.paper)+rect(12,24,76,1,p.light);
  s+=step(7,29,86,13,p.light)+step(73,30,18,11,p.main);
  s+=step(7,45,86,83,p.paper);
  // 五条等高信息行用浅底色区分，数值列留足空间以容纳三位以上数字。
  for(let i=0;i<5;i++) {
    const y=47+i*16;
    s+=rect(10,y,80,14,i%2===0 ? p.paper : p.light);
    if(i<4) s+=rect(13,y+14,74,1,p.light);
  }
  s+=rect(9,132,4,2,p.light)+rect(87,132,4,2,p.light);
  return svg(100,140,s);
}
const icons={
  physical: path('M8 0H11V3H9V5H7V7H5V9H3V7H1V5H3V7H4V5H6V3H8Z','#ad5b42')+rect(8,1,2,2,'#fff2c5'),
  magic: path('M5 0H7V3H10V5H12V7H9V9H7V12H5V9H2V7H0V5H3V3H5Z','#4b8db8')+rect(5,4,2,4,'#d2f5ff')+rect(4,5,4,2,'#d2f5ff'),
  armor: path('M1 0H11V8H9V10H7V12H5V10H3V8H1Z','#68946f')+path('M3 2H6V9H5V7H3Z','#c6e6ae'),
  ward: path('M6 0H8V2H11V4H12V8H10V10H8V12H4V10H2V8H0V4H1V2H4V0Z','#8e79ac')+path('M5 3H7V5H9V7H7V9H5V7H3V5H5Z','#f1e0ff'),
  speed: path('M5 0H10L7 5H11L3 12L5 7H1Z','#b4863c')+path('M6 1H8L5 6H3Z','#fff1b0'),
};

// 默认根目录从原稿位置定位，允许在其他工作目录运行导出。
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const out=resolve(root,'res/monstercard');
await mkdir(out,{recursive:true});
for(const key of Object.keys(palettes)) await writeFile(resolve(out,`${key}_monster.svg`),front(key));
for(const [key,s] of Object.entries(icons)) await writeFile(resolve(out,`${key}_stat.svg`),svg(12,12,s));
// 保留通用入口路径，供编辑器在怪物尚未初始化时显示预览。
await writeFile(resolve(out,'monster_frame.svg'),front('universal'));
console.log('已导出 6 种五行怪物卡面和 5 个属性图标。');
