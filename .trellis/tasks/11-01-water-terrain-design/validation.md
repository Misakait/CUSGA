# 水生态场景检查结果

日期：2026-11-01。场景绘制已完成；未提交、未推送。没有启动游戏，运行验证交给用户。

## 已完成内容

- water 下全部 12 图重铺为与现有世界步长一致的 1280×720；TileSet 和图集切片保持 16×16。
- coral_shoal 的 16 套 TileSet 与 Atlas 子资源、原有 TileMapLayer 非布局参数保持一致。其余 11 图按节点路径迁移对应配置，桥口封闭、桥侧边界、桥面、地面和障碍保持独立职责。
- 每行原始瓦片的列号表示四角占用：左上 8、右上 4、左下 2、右下 1。合并位掩码选列，使用特殊内角和对角瓦片；不是只铺九宫格。
- 每图 MapContainer/Decorations 放置 30 个 Sprite2D，Z=-1；Ground 为 -5，Boundary 为 -4，桥面/封口为 -3，桥侧/礁石为 -2。玩家保持原配置，点缀显示在玩家下方。
- 新增 WaterDetail 图层只做表现，不带碰撞。水域色块为可行走地表材质；离岛外与中空区域由 Boundary 围合。少量礁石使用参考 Obstack 碰撞，未扩展 earth 的禁用障碍要求。

## 静态检查

命令使用桌面内置 Python（含 Pillow）：

```powershell
& 'C:/Users/huhu9/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' .trellis/tasks/11-01-water-terrain-design/check_water.py
```

- 12 图 × 16 种桥组合 = 192 种全部通过。
- 直接读取最终场景序列化瓦片及 TileSet 碰撞，检查引用存在、atlas 坐标有效、网格无越界/重复、地面无碰撞、四角拼缝一致。
- 对当前玩家横向胶囊包围盒进行保守碰撞膨胀，以 8 像素步长搜索。检查出生区可达、每图默认 6×4 共 24 个物资格中心可达、可达区域有完整地表、仅已开放方向可触及房间边缘。
- 原素材、其他生态场景、公共地图脚本与地图配置哈希未变化。
- 静态结果见 research/static_validation.json。离线碰撞搜索不能代替真实 Godot 物理运行测试。

## 编辑器检查

通过已打开的 Godot 4.7.1 编辑器 MCP 扫描文件，逐图 scene_open 和 scene_get_hierarchy，全部成功。原 16 个图层加新增材质层共 18～19 层，各图装饰节点 30 个。editor 日志为空。详情见 research/editor_validation.json。

查看了 coral_shoal 的编辑器 2D 视口及全部地图的无桥/全桥离线总览。当前编辑器停留 coral_shoal，游戏保持停止，编辑器保持打开。

## 预览与回退

- 无桥全览：research/water_contact_closed.png。
- 四桥全览：research/water_contact_open.png。
- 各图原尺寸预览：research/<场景名>.closed.png、research/<场景名>.open.png。
- 用户原 coral_shoal：research/coral_shoal.before.tscn；所有原场景副本：research/before/。
- paint_water.py 是本任务的离线作者工具，不被游戏引用。重新执行会基于原场景备份重写 12 图，因此用户再次手工编辑之后不要直接重跑。

## 用户验看

用户可逐图查看轮廓与材质，并在世界中检查跨房通行、玩家遮挡和资源交互。没有改动游戏机制、脚本、数值或地形生成资源，因此未修改玩法汇总文档。
