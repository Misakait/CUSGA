# 战斗界面素材

`res/battle_ui/` 下的三个 SVG 是血条底槽、生命填充和能量填充的可编辑原稿，尺寸统一为 **64 × 12**。对应 `.tres` 用 `StyleBoxTexture` 九宫格拉伸，四边各保留 **4** 像素，放大长度时保留像素切角和高光。

玩家与怪物复用同一组资源：玩家显示 **304 × 14** 的上下双条，怪物仅显示卡面下缘的 **138 × 12** 生命条。文字由实际数值绑定，SVG 不含生命或能量数值。纯色血条与贴图血条共用 `StatBar`，缓冲层使用独立资源副本，避免修改一只怪物的样式时影响其它角色。

布局保持左侧纵向行动轴，怪物预告放在卡面上方，生命数值与状态图标放在下方。玩家五项属性在双条右侧分为两行。`ingame_preview.png` 为真实战斗画面；完整布局参数见 `docs/游戏机制与玩法内容.md`。

五行背景均使用内置 imagegen 分别生成，原图 **1672 × 941**，风格为有限色板、块状像素和开阔空地，环境细节集中在边缘。最终游戏素材与完整提示词如下：

| 五行 | 地图目录 | 素材 | 提示词 |
| --- | --- | --- | --- |
| 金 | `gold` | `res/background/battle/metal.png` | `metal_background_prompt.txt` |
| 木 | `wood` | `res/background/battle/wood.png` | `wood_background_prompt.txt` |
| 水 | `water` | `res/background/battle/water.png` | `water_background_prompt.txt` |
| 火 | `fire` | `res/background/battle/fire.png` | `fire_background_prompt.txt` |
| 土 | `earth` | `res/background/battle/earth.png` | `earth_background_prompt.txt` |

世界交互协调器在淡出前读取 `MapWorldModel` 当前坐标的场景资源路径，入树前交给战斗内 `测试背景` 节点的 `battle_background.gd`。该组件从 `map_env` 后的首个目录选择贴图；普通 `normal` 区域、未知地图和独立运行的战斗默认使用木行背景。组件只负责表现，不依赖世界节点、怪物五行或地图显示缓存。

`backgrounds` 字典可在检查器中替换素材，`fallback_biome` 控制默认群系，`design_size` 默认为 **1280 × 720**。背景按原图尺寸自动铺满设计视口，使用最近邻采样；背景层级 **-1000** 与昼夜滤镜保持原有配置。
