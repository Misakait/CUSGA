# 金生态绘制进度

实现代理：`/root/gold_implement`。12张gold场景绘制完成，已停止写入，等待独立审查。

- 独立生成器：本任务`paint_gold.py`；仅复用已验证的几何与桥口数学，不依赖其他任务脚本。
- 12种全新轮廓和地表：铜锈双环、齿轮环台、金沙条带、斜向铁脊峡谷、磁铁矿洞、钢穹交换广场、斜向合金裂谷、菱形磁铁双丘、分叉矿脉、锈蚀浅滩、冶炼遗迹与钢穹门庭。
- 输入固定`research/before/`和`copper_rust_forest.before.tscn`，不以生成结果作下次输入。
- 16个原始TileMapLayer的非布局配置及完整原始子资源与参考逐层逐块相同，保留原右侧微小旋转。
- 所有Obstack图层为空，未使用障碍素材或新增障碍碰撞。
- 每图30个无碰撞金生态装饰，共360个。容器`MapContainer/Decorations`，Z=-1位于玩家下方。
- 已保存`gold_contact_closed.png`、`gold_contact_open.png`、24张单图预览和`layouts.json`。
- 已目视无桥/全桥总览，12图UID、16层非布局配置、全部子资源、空障碍、外部引用存在性和`git diff --check`通过。
- 未访问Godot或启动游戏；编辑器加载由根代理负责，游玩由用户验证。

如果独立审查需要修正，统一回到`paint_gold.py`修正再生成，不能直接更改场景使生成器失去同步。
