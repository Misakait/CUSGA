# 长按交互在范围内移动不打断

## Goal

地形卡长按与建筑拆除期间，玩家在交互范围内移动都不再打断交互；只有移动出各自的交互范围才取消。
让「按住左键挪一步」不再把已经填了一半的进度环打回原点。

## Background（已确认事实）

### 地形卡当前中断链路（`core/gameflow/world_interaction_coordinator.gd`）

| 位置 | 行为 | 本次 |
|---|---|---|
| `_process_terrain_hold_input()` :245-260 | **每帧**检查，只要按下任意 WASD 方向键就 `cancel_hold_for` + `_clear_active_terrain_hold()` | **改** |
| `_on_board_card_pressed()` :728-730 | 按下瞬间若方向键已按住，直接 `_clear_active_terrain_hold()` 并 return，长按根本不开始 | **改** |
| `_on_board_card_pressed()` :708-711 | 按下瞬间超出范围 → `_report_out_of_range_interaction()` 后 return | 保留 |
| `_on_board_card_pressed()` :727 | `_set_player_mouse_movement_blocked(true)` 屏蔽鼠标移动 | 保留 |
| `_complete_terrain_hold()` :840-863 | 完成入口**不**复查距离（注释 :693-695 的理由是「玩家移动会被屏蔽」） | **改** |
| `_unhandled_input()` :302-306 / `_on_board_card_released()` :748-752 / `_exit_tree()` :281 / :1168 / :1228 | 松键、抬起、退出、过场、结算取消 | 保留 |

长按开始之后**没有任何范围复查**。范围只在按下瞬间判一次，之后玩家实际上被「钉」在原地：
鼠标移动被屏蔽，键盘一动就取消。所以「移动」在当前实现里只有两种结局：不动，或打断。

### 建筑当前中断链路（`core/building/building_controller.gd`）

| 位置 | 行为 | 本次 |
|---|---|---|
| `_can_continue_demolition()` :489-495 | **每帧**要求 `_building_under_pointer()` 重新命中**同一栋**建筑，并要求 `_is_record_reachable` | **改** |
| `_process()` :259-267 | 门禁失败即 `_cancel_demolition()`；提示「正在拆除 · 松开左键或移开鼠标取消」 | **改** |
| `_complete_demolition()` :499-517 | 完成瞬间调 `_can_continue_demolition()` 再校验 | **改** |
| `_begin_demolition()` :447-485 | 开始时按光标选中 + `_is_record_reachable` 门槛 | 保留 |
| 右键 / Esc / 失焦 / 暂停 / 切房间 / 世界门禁 | 取消 | 保留 |

建筑**没有**键盘检查，但它被「移动」打断的原因是 `_building_under_pointer()`（:432-443）
用 `_mouse_world_position()` = `_buildings_root.get_global_mouse_position()` 把**屏幕光标**换算到世界坐标。
相机跟随玩家平移时，光标下的世界点随相机一起漂移，于是玩家只在范围内挪一步，光标也会离开建筑占地
→ 门禁返回 false → 取消。这就是建筑侧「移动打断」的根源，和键盘无关。

**关键推论**：区分「玩家自己动了鼠标」与「相机跟随漂移」的判据是鼠标的**屏幕**坐标。
相机平移不改变屏幕光标位置，所以「玩家没碰鼠标」时屏幕采样逐帧恒定；
玩家真的把鼠标移到空白处或另一栋建筑时，屏幕采样一定会变。

### 可复用的既有单一来源

- `_try_get_interaction_range(card)` :454-461 → `{"ok": distance <= InteractionRange, "distance": distance}`，
  `InteractionRange` 导出默认 `160.0`。距离口径是「玩家节点中心 → 卡牌中心」的世界坐标距离。
- `_report_out_of_range_interaction(card, distance)` :469-474 → 含真实距离的调试日志 +
  `_show_out_of_range_floating_text(card)`（「距离不够！」飘字 + 半径 `InteractionRange` 的提示圈）。
- `_clear_active_terrain_hold()` :434-443 → 地形长按的**唯一**停止汇合点：清记录、`SetDestroying(false)`、
  解除鼠标移动屏蔽。
- `_is_record_in_range(record)`（建筑 :379-382）→ 距离 ≤ 该建筑自己的 `InteractionRadius`；
  `_is_record_reachable(record)` :386-402 = `_is_record_in_range` + 视图可见 + 射线无遮挡。
- `_show_building_out_of_range(record)` :741-743 → 「距离不够！」飘字 + 半径取该建筑自己的
  `InteractionRadius` 的提示圈，注释明确「与 `_is_record_in_range` 的判定口径完全一致」。
- `_cancel_demolition()` :521-530 → 建筑长按的**唯一**停止汇合点：先取视图再清 `_demolition_id`、
  `SetDestroying(false)`、按拥有者 `cancel_hold_for`。
- `_mouse_world_position()` :534-535 → 已被回归场景 `ControllerInputProbe` 覆写的鼠标采样接口。

### 被既有契约锁定的形状（改这些会连带改测试与文档）

- `tests/godot/test_loot_auto_pickup_contract.gd:85` 锁定 `func _process_terrain_hold_input() -> void:` 必须存在
  → 保留方法名。
- `tests/godot/test_world_interaction_coordinator_contract.gd:459-479` 锁定 `InteractionRange` 的导出声明、
  `_try_get_interaction_range` 的签名与返回形状、以及距离表达式 → 复用而不改助手。
- 同一套件 :484-488 锁定 `var range_check: Dictionary = _try_get_interaction_range(card)` 出现**恰好 2 次**
  → 本次会变成 3 次，断言与理由必须同步更新。
- `tests/godot/test_floating_text_contract.gd:372` 锁定飘字入口传 `FAILURE_TEXT_COLOR, InteractionRange`
  → 复用现有飘字漏斗，不新增半径来源。
- `tests/godot/building_system_tests.gd:443` 锁定 `_check(not hold.get("is_holding"), "移开鼠标或换目标必须取消拆除")`
  → **本次行为保留**，该断言不变（它显式改了注入的鼠标位置，等价于玩家真的动了鼠标）。
- `tests/godot/building_system_tests.gd:458` 锁定「长按中走远必须取消拆除」→ 保留。
- 相关文档：`docs/游戏机制与玩法内容.md:15`、`:25`、`:59`；`docs/建筑系统.md:15`、`:90`。

## Requirements

- **R1 范围内移动不打断（两条长按统一）**：地形卡长按期间键盘方向输入（WASD）不再取消；
  建筑拆除期间**玩家自己没动鼠标**时光标漂移不再取消。两条长按都允许「边保持左键边移动」。
- **R2 只有超出交互范围才取消**：
  - 地形卡：每帧按 `_try_get_interaction_range` 复查，距离 > `InteractionRange` 即取消。
  - 建筑：每帧按 `_is_record_in_range` 复查，距离 > 该建筑 `InteractionRadius` 即取消。
  - 各自复用既有判定，不引入第二处距离来源、不加迟滞容差。
- **R3 取消时说明原因**：两条长按因走出范围取消时，都给出「距离不够！」飘字 +
  各自的所需范围提示圈（地形卡半径 `InteractionRange`，建筑半径该建筑 `InteractionRadius`），
  并输出含真实距离的调试日志。暂停、界面、战斗、松键等原因保持静默。
- **R4 开始门槛只由距离与目标决定**：地形卡按下瞬间在范围内就一定能开始长按，不再因为「方向键已按住」而不开始；
  建筑按下瞬间仍须命中建筑且可达。两者「按下瞬间就在范围外」的拒绝行为不变。
- **R5 建筑每帧门禁不含遮挡，遮挡只在完成瞬间拦**（用户决策）：长按期间走到墙后不取消；
  但进度填满时仍不能隔墙远程拆除，因此完成门禁保留 `_is_record_reachable`。
- **R6 建筑的「移开鼠标」与「切换目标」依旧取消**（用户决策）：判据改为鼠标**屏幕**坐标是否变化。
  玩家主动移动鼠标时仍按 `_building_under_pointer()` 复查，光标不在本次目标建筑上就取消；
  玩家没动鼠标时（含相机跟随造成的世界坐标漂移）不做该复查，只判距离。
- **R7 其余取消路径不变**：松键、按下另一项交互、目标失效、暂停、失焦、右键 / Esc、
  打开界面、进入战斗、切换房间、场景退出仍然取消；建筑仍不允许一次按住连拆两栋。
- **R8 契约与文档同步**：受影响的契约测试、`building_system_tests.gd` 的新增覆盖、
  `docs/游戏机制与玩法内容.md`、`docs/建筑系统.md` 与
  `.trellis/spec/backend/gameplay-system-patterns.md` 一并更新。

## Acceptance Criteria

1. 地形卡长按期间按住 WASD 并在范围内移动：长按**不取消**，圆环继续填满并正常完成。
2. 建筑拆除期间玩家按住左键但**不碰鼠标**，角色在范围内移动（相机跟随、建筑在屏幕上移位）：
   **不取消**，圆环继续填满并正常完成。
3. 建筑拆除期间玩家**主动把鼠标移到空白处**：取消（行为与改动前一致）。
4. 建筑拆除期间玩家**主动把鼠标移到另一栋建筑**：取消（行为与改动前一致）。
5. 地形卡长按期间移动出 `InteractionRange`：**立即取消**，圆环隐藏、抖动停止复位、
   不消耗行动值、不生成掉落、不触发遭遇。
6. 建筑拆除期间走出该建筑 `InteractionRadius`：**立即取消**，圆环隐藏、抖动停止复位、建筑保留、不生成掉落。
7. 两种取消都显示「距离不够！」飘字与各自半径的提示圈，并输出含真实距离的调试日志。
8. 建筑长按期间走到墙后（范围内但有遮挡）：**不取消**；进度填满时**仍不结算**，建筑保留、无掉落。
9. 按下瞬间就在范围外：两条长按行为都与改动前一致（拒绝 + 对应反馈）。
10. 地形卡按下瞬间方向键已按住但在范围内：长按正常开始（改动前不会开始）。
11. 建筑拆除的其它取消路径不变：松键、右键 / Esc、失焦、暂停、打开界面、进入战斗、切房间、
    一次按住不连拆第二栋。
12. 长按期间的鼠标移动屏蔽保持不变；地形交互完成或取消后解除屏蔽，且不恢复旧的鼠标目标。
13. 受影响契约测试与 `building_system_tests.gd` 通过；全量 `test_run` 未引入新的失败。

## Out of Scope

- 地图方向长按（`BeginWorldHoldForMap`）的取消口径：它是地图 UI 上的按钮长按，
  由 `map_button.gd` 的按钮抬起驱动，玩家此时不在世界里走动。
- 是否解除地形长按期间的鼠标移动屏蔽：点击移动已由 `ClickWalk.CLICK_MOVEMENT_ENABLED = false` 全局停用，
  屏蔽当前是惰性的，保持最小改动。
- 走出范围后回到范围内是否**恢复**已填进度：取消即终结，不恢复（R2）。
- 给取消阈值加迟滞/容差：取消是终态、不会反复，精确等于各自半径即可与开始门槛同源。
- 建筑「不允许隔墙远程破坏」的规则本身：只是把判定时机从每帧挪到完成瞬间（R5）。
- 建筑**按下瞬间**的门槛（`_begin_demolition` 仍须光标命中建筑）：本次只放宽长按期间，不放宽按下瞬间。
- 地形卡的「切换目标」语义：它由「按下另一张卡」实现，仍走 `begin_hold` 换 owner 取消，不变。
