# 火生态绘制进度

实现代理：`/root/fire_implement`。当前已完成首批绘制并写入全部12个 fire 场景。

- 所有权：`scenes/map_scenes/map_env/fire/**/*.tscn`、本任务 `paint_fire.py` 和绘图预览/布局清单。
- 输入固定为 `research/ash_plain.before.tscn` 与 `research/before/`，未使用已生成场景作为再次生成的输入。
- 已保留参考图的完整子资源链和16个原始 TileMapLayer 的非布局配置。
- 每图30个无碰撞装饰，容器为 `MapContainer/Decorations`，位于玩家下方。
- 共47组完整4×4障碍；六类原始组合全部使用。硫磺通道较窄，仅放3组，避免挤占中央物资格和桥口。
- 已输出 `research/fire_contact_closed.png`、`research/fire_contact_open.png`、24张单图预览、`research/layouts.json` 与 `research/obstacle_groups.json`。
- 已目视检查无桥和全桥总览。已清除切口产生的孤立角点和一角宽细尾，刷新全部预览。
- 局部自检通过：12图场景UID保留、16个原始图层非布局配置完全匹配参考、全部原始子资源逐块相同、没有缺失资源引用，`git diff --check` 通过。
- 实现代理已经停止写入场景，现可独立审计全部12图；若有修正，需在生成器同步修改并重新生成。
- 不调用 Godot MCP，不启动或停止游戏。最终编辑器加载由主代理负责。

首次生成在写场景前发现硫磺通道一组障碍缺少完整地表，已减少该图一组障碍并重新生成，其他场景没有部分写入。
