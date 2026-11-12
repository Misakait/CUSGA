# 物品交互时移动速度降低80% — 执行记录

## 行为边界

- 只覆盖棋盘地形卡的持续长按（采集、破坏）；掉落自动拾取、建筑 F/拆除、地图长按与 UI 不减速。
- 键盘 `move_player` 与鼠标 `ClickWalk` 共用 `PlayerChar.get_effective_walk_speed()`。
- 交互期间有效速度为 `walk_speed × 0.2`；默认倍率在玩家 Inspector 导出，可在 0～1 调整。
- 减速是玩家节点运行时状态，不写 `PlayerData.tres`、不写存档。

## 实现

- `scripts/player_scripts/PlayerChar.gd`：新增 `item_interaction_speed_multiplier`、`BeginItemInteraction()`、`EndItemInteraction()`、`get_effective_walk_speed()`；`move_player` 改用有效速度。
- `scripts/player_scripts/states/ClickWalk.gd`：目标速度与加速量改用有效速度，兼容没有该协议的旧玩家替身。
- `core/gameflow/world_interaction_coordinator.gd`：新增 `_set_player_item_interaction_slowed()`；在有效地形长按 `begin_hold` 前开始，在统一清理出口 `_clear_active_terrain_hold()` 结束。
- `tests/test_item_interaction_move_slowdown.gd` 与 `tests/godot/test_item_interaction_move_slowdown.gd`：同一份回归套件，覆盖 20% 速度、倍率可配置、两条移动路径、协调器开始/清理与重复清理。
- `docs/游戏机制与玩法内容.md` 与 `.trellis/spec/backend/gameplay-system-patterns.md`：同步机制口径与单一速度来源约束。

## 验证

- `item_interaction_move_slowdown`：4/4 通过。
- `player_movement_input_contract`：1/1；`hold_move_within_range`：4/4；`loot_auto_pickup_contract`：3/3；`player_contract`：6/6；`destroy_hold_shake`：7/7；`map_world_contract`：8/8（2 跳过）。
- 运行期 `PlayerChar.tscn`：基础有效速度 500 → 交互中 100 → 结束 500；重复开始/结束不叠乘、不残留。
- 运行期实际按键行走：基础速度约 499.99，交互中约 99.99，结束后约 499.99。
- 既有问题：`test_item_room_content.gd` Parse Error；`world_interaction_coordinator_contract` / `gameflow_chain_contract` 对 `_run_screen_transition` 的旧签名断言失败，均与本次改动无关。
- `git diff --check` 通过；游戏已停止，编辑器保持打开。

## 未做

- 未提交、未推送、未归档 Trellis 任务。
- 未修改建筑、地图、自动拾取、背包/仓库 UI 的既有行为。
