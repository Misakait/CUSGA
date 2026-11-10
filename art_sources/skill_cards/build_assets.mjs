// 五行卡牌的可编辑像素原稿；所有坐标落在整数像素网格，不依赖生成式图片或外部服务。
// 调整调色板或徽记后调用 buildAssets，即可同步导出 Godot 使用的 SVG、库存 PNG 与总览。

// 五行沿用战斗枚举的英文资源名；通用版本供无属性技能和通用卡胚回退。
export const palettes = {
  metal: { name: '金', main: '#f5c744', shade: '#ba852a', light: '#fff0a3', paper: '#fff9df', ink: '#674c2c' },
  wood: { name: '木', main: '#8ad95e', shade: '#4c934d', light: '#ddf6b2', paper: '#f6ffe8', ink: '#395a3b' },
  water: { name: '水', main: '#66cef4', shade: '#397fa8', light: '#c9f2ff', paper: '#f0fcff', ink: '#325668' },
  fire: { name: '火', main: '#ff896c', shade: '#b65846', light: '#ffddbd', paper: '#fff5e9', ink: '#6a4138' },
  earth: { name: '土', main: '#edb466', shade: '#aa7445', light: '#ffe5b0', paper: '#fff8e7', ink: '#674d35' },
  universal: { name: '通用', main: '#b7a1e5', shade: '#7c689e', light: '#ebdefa', paper: '#fff8ef', ink: '#59496b' },
};

// 16×16 徽记：句点透明，o 为轮廓，m 为主色，l 为亮部，w 为高光，s 为阴影。
// 通用徽记额外使用五行的独立颜色；图案同时服务卡背、卡面角标与卡胚封签。
export const emblems = {
  metal: [
    '.......oo.......','......ollo......','.....olwwlo.....','....olwwwwlo....',
    '...olwwwwmmlo...','..olwwwwmmmllo..','.olllllmmmmmmlo.', 'olllllmmmmmmmmlo',
    'ommmmmmsssssssmo','.ommmmmssssssmo.','..ommmmsssssmo..','...ommmssssmo...',
    '....ommsssmo....','.....omssmo.....','......ommo......','.......oo.......',
  ],
  wood: [
    '................','..oooo..........','.olllmo...oooo..','.olwllmo.olllmo.',
    '..olllmo.olwlmo.','...olmmoo.llmo..','....ommo.ommo...', '.....omoommo....',
    '......omomo.....','......ommo......','...ooooomoo.....','..ollllommlo....',
    '..olwllommmo....','...ooooommo.....','.......ommo.....','.......oooo.....',
  ],
  water: [
    '.......oo.......','......olmo......','......olmo......','.....olwlmo.....',
    '....olwwlmmo....','...olwwlmmmmo...','...olwlmmmmmo...', '..olwlmmmmmmmo..',
    '..olwmmmmmmmmo..','..olmmmmmmmmso.','..olmmmmmmmmso.','...ommmmmmsso...',
    '...ommmmmssso...','....osssssso....','.....oooooo.....','................',
  ],
  fire: [
    '.......oo.......','......olmo......','......olmo......','.....olwlmo.....',
    '.....olwlmo.....','..oo.olllmmoo...','..omo.ollmmmo...', '.olmmoolmmmmo...',
    '.olmmmolllmmmo..','.olmmolwwlmmmo..','.olmmolwwlmmmo.','..ommolwllmmo..',
    '..ommmolllmmo...','...ommmmmmmo....','....ossssso.....','.....ooooo......',
  ],
  earth: [
    '................','......oooooo....','.....olllllmo...','....olwwlllmmo..',
    '...olllllmmmmo..','...olllmmmmmso.','...ommmmmmmmso.', '..ooooooosssso..',
    '.olllllmoooooo..','olwwlllmmolllmo.','olllllmmmollmmmo','ollllmmmmommmmmo',
    'ommmmmsssommsso','ossssssssoossso.','.ooooooooooooo..','................',
  ],
  universal: [
    '.......oo.......','......oyyo......','.....oywwyo.....','......oyyo......',
    '...oo..oo..oo...','..oggo....orro..','.ogwwgo..orwwro.','..oggo.oo.orro..',
    '...oo.olwo.oo...','......owlo......','...oo..oo..oo...','..obbo....otto..',
    '.obwwbo..otwwto.','..obbo....otto..','...oo......oo...','................',
  ],
};

// 星形采用离散像素轮廓；运行时用纹理显示，避免字体缺字或不同平台星号形状不一致。
const starRows = ['.....oo.....','....oyyo....','....oyyo....','.ooooyyoooo.','oyywwyyyyyyo','.oyyyyyyyyo.','..oyyyyyyo..','..oyyyyyyo..','.oyyyoyyyyo.','.oyyo.oyyyo.','..oo...ooo..','............'];

// 构造 SVG 基元；输出保持普通 SVG，既可在矢量编辑器中修改，也可直接由 Godot 导入。
const rect = (x, y, w, h, fill, extra = '') => `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${fill}" ${extra}/>`;
const path = (d, fill, extra = '') => `<path d="${d}" fill="${fill}" ${extra}/>`;
const group = (x, y, scale, body) => `<g transform="translate(${x} ${y}) scale(${scale})">${body}</g>`;
const svg = (w, h, body) => `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" shape-rendering="crispEdges">\n${body}\n</svg>\n`;
const stepped = (x, y, w, h, c, fill) => path(`M${x+c} ${y}H${x+w-c}V${y+2}H${x+w-2}V${y+c}H${x+w}V${y+h-c}H${x+w-2}V${y+h-2}H${x+w-c}V${y+h}H${x+c}V${y+h-2}H${x+2}V${y+h-c}H${x}V${y+c}H${x+2}V${y+2}H${x+c}Z`, fill);

// 按行合并同色像素，避免一个徽记产生数百个冗余节点。
function pixels(rows, colors) {
  let output = '';
  for (let y = 0; y < rows.length; y++) {
    for (let x = 0; x < rows[y].length;) {
      const token = rows[y][x];
      let end = x + 1;
      while (end < rows[y].length && rows[y][end] === token) end++;
      if (colors[token]) output += rect(x, y, end - x, 1, colors[token]);
      x = end;
    }
  }
  return output;
}

// 徽记对比比卡框更强，确保缩到库存格时仍能区分叶片、晶石、水滴、火苗和岩块。
function emblem(key) {
  const p = palettes[key];
  return pixels(emblems[key], {o:p.ink,m:p.main,l:p.light,w:'#fffef0',s:p.shade,y:'#f5c744',g:'#8ad95e',b:'#66cef4',r:'#ff896c',t:'#edb466'});
}

function frame(p) {
  return stepped(1, 3, 138, 97, 7, '#584139') + stepped(0, 0, 140, 97, 7, p.ink)
    + stepped(2, 2, 136, 93, 5, p.shade) + stepped(3, 3, 134, 89, 4, p.main)
    + rect(8, 3, 124, 2, p.light) + rect(3, 8, 2, 78, p.light)
    + rect(8, 92, 124, 1, p.ink);
}

// 140×100 卡面与既有碰撞范围严格一致；文字、费用和星级由游戏动态叠加。
export function front(key) {
  const p = palettes[key];
  return svg(140, 100, frame(p)
    + stepped(7, 7, 126, 25, 3, p.paper)
    + stepped(9, 9, 22, 21, 3, p.shade) + stepped(10, 9, 20, 19, 3, p.main)
    + rect(13, 10, 14, 1, p.light)
    + stepped(7, 35, 126, 44, 3, p.paper)
    + rect(12, 38, 74, 1, p.light) + rect(12, 74, 74, 1, p.light)
    + stepped(7, 82, 126, 10, 3, p.light)
    + group(116, 79, 0.75, emblem(key)));
}

// 卡背以统一的封印结构连接五行家族，避免把不可见信息（名称、费用、星级）画入卡背。
export function back(key) {
  const p = palettes[key];
  return svg(140, 100, frame(p)
    + stepped(7, 7, 126, 83, 3, p.light) + stepped(10, 10, 120, 77, 3, p.main)
    + stepped(12, 12, 116, 73, 3, p.light)
    + path('M70 16L102 48L70 80L38 48Z', p.main)
    + path('M70 21L97 48L70 75L43 48Z', p.paper)
    + group(50, 28, 2.5, emblem(key))
    + rect(19, 46, 12, 3, p.shade) + rect(24, 41, 3, 13, p.shade)
    + rect(109, 46, 12, 3, p.shade) + rect(113, 41, 3, 13, p.shade)
    + rect(17, 17, 17, 2, p.paper) + rect(17, 17, 2, 12, p.paper)
    + rect(106, 79, 17, 2, p.shade) + rect(121, 68, 2, 13, p.shade)
    + rect(64, 13, 12, 2, p.paper) + rect(64, 83, 12, 2, p.shade));
}

// 卡胚为尚未写入技能的三张小纸胚，用封签而非卡面内容区分于已获得的技能卡。
export function embryo(key) {
  const p = palettes[key];
  return svg(48, 48,
    stepped(10, 15, 35, 27, 4, p.ink) + stepped(11, 15, 32, 24, 3, p.shade)
    + stepped(7, 11, 35, 27, 4, p.ink) + stepped(8, 11, 32, 24, 3, p.light)
    + stepped(3, 6, 35, 28, 4, p.ink) + stepped(5, 8, 31, 23, 3, p.paper)
    + rect(8, 9, 21, 2, '#ffffff') + rect(8, 13, 20, 2, p.light)
    + rect(8, 26, 10, 2, p.light)
    + rect(28, 8, 5, 23, p.main) + rect(28, 8, 1, 20, p.light)
    + stepped(22, 22, 24, 23, 5, p.ink) + stepped(23, 22, 22, 20, 4, p.main)
    + rect(28, 23, 12, 1, p.light) + group(26, 24, 1, emblem(key)));
}

// 背包用小卡图标保留 32×32 尺寸，原资源引用和 UID 无需批量迁移。
export function inventoryIcon(key) {
  const p = palettes[key];
  return svg(32, 32, stepped(1, 4, 30, 25, 3, p.ink) + stepped(2, 5, 28, 21, 3, p.main)
    + rect(4, 7, 24, 3, p.light) + rect(4, 11, 24, 13, p.paper)
    + group(5, 11, 0.75, emblem(key)) + rect(19, 13, 7, 2, p.shade)
    + rect(19, 17, 5, 1, p.main) + rect(19, 20, 6, 1, p.main));
}

// 参数 fs/sharp 由本地工具提供；只写项目中的明确资产目录，不安装依赖或访问网络。
export async function buildAssets({ fs, sharp, root }) {
  const assetDir = `${root}/res/skillcard/elemental`;
  const sourceDir = `${root}/art_sources/skill_cards`;
  await fs.mkdir(assetDir, { recursive: true });
  const outputs = [];
  for (const key of Object.keys(palettes)) {
    for (const [suffix, drawing] of [['front',front(key)],['back',back(key)],['embryo',embryo(key)]]) {
      const file = `${assetDir}/${key}_${suffix}.svg`;
      await fs.writeFile(file, drawing, 'utf8');
      outputs.push(file);
    }
    if (key !== 'universal') {
      const drawing = inventoryIcon(key);
      await fs.writeFile(`${assetDir}/${key}_icon.svg`, drawing, 'utf8');
      const oldName = key === 'metal' ? 'gold' : key;
      await sharp(Buffer.from(drawing)).png().toFile(`${root}/res/skillcard/${oldName}_skill_card.png`);
    }
  }
  await fs.writeFile(`${assetDir}/star.svg`, svg(12,12,pixels(starRows,{o:'#9b692b',y:'#ffd457',w:'#fff5b3'})), 'utf8');
  // 总览只用于美术审阅，不导入游戏。放大采用最近邻，避免像素边缘被柔化。
  const parts = [];
  for (const [index,key] of Object.keys(palettes).entries()) {
    parts.push({input:await sharp(Buffer.from(front(key))).resize(280,200,{kernel:'nearest'}).png().toBuffer(),left:38,top:64+index*220});
    parts.push({input:await sharp(Buffer.from(back(key))).resize(280,200,{kernel:'nearest'}).png().toBuffer(),left:350,top:64+index*220});
    parts.push({input:await sharp(Buffer.from(embryo(key))).resize(144,144,{kernel:'nearest'}).png().toBuffer(),left:680,top:88+index*220});
  }
  await sharp({create:{width:870,height:1400,channels:4,background:'#eadfc9'}}).composite(parts).png().toFile(`${sourceDir}/preview.png`);
  return {svg_count:24,preview:`${sourceDir}/preview.png`,outputs};
}
