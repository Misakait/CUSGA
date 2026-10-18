# 执行计划：长按交互在范围内移动不打断

## 阶段 0：编码前准备

- [ ] **重连 Godot 编辑器**：`session_manage(op="list")` 当前返回 `count=0`（编辑器未连接）。
      请用户在 Godot 4.7.1 中打开 CUSGA 项目并启用 Godot AI 插件，再 `session_activate` 到 CUSGA 会话。
      没有编辑器连接不得开始编码与验证。
- [ ] 载入 `trellis-before-dev`，读取 `.trellis/spec/backend/gameplay-system-patterns.md`、
      `.trellis/spec/frontend/directory-structure.md`、`.trellis/spec/backend/testing-guidelines.md`。
- [ ] `git status` 确认工作区干净（HEAD 应为 `16fe926`）。
- [ ] 复核调用点现状：
      - 协调器：`_process_terrain_hold_input`、`_on_board_card_pressed`、`_complete_terrain_hold`、
        `_try_get_interaction_range`、`_report_out_of_range_interaction`、`_clear_active_terrain_hold`。
      - 建筑：`_can_continue_demolition`、`_building_under_pointer`、`_mouse_world_position`、
        `_is_record_in_range`、`_is_record_reachable`、`_show_building_out_of_range`、
        `_cancel_demolition`、`_building_world_position`、`_begin_demolition`。
      - 全仓库确认 `_can_continue_demolition` 只有 `building_controller.gd:262` / `:489` / `:500` 三处引用。
- [ ] 记录改动前的全量 `test_run()` 失败清单，作为回归基线。

## 阶段 1：生产改动 —— 地形卡（`core/gameflow/world_interaction_coordinator.gd`）

- [ ] `_process_terrain_hold_input()`：删掉「按下任意 WASD 即取消」的分支，
      改为 `_try_get_interaction_range(_active_terrain_hold_card)` 复查；超出范围才取消。
- [ ] 取消走 `cancel_hold_for(out_of_range_card)` + `_clear_active_terrain_hold()`，
      随后 `_report_out_of_range_interaction(out_of_range_card, distance)`；
      先固定局部引用再清记录（`_clear_active_terrain_hold` 会置空）。
- [ ] 保留既有的 `_active_terrain_hold_card == null` 与 `is_instance_valid` 两个提前返回分支。
- [ ] 更新该函数的 `##` 注释：从「键盘方向输入优先于正在进行的棋盘地形长按」改为
      「移动不再打断，只有走出 InteractionRange 才取消」，并说明判定与按下门槛同源。
- [ ] `_on_board_card_pressed()`：删除 :728-730 的「方向键已按住就不开始」分支。
- [ ] `_on_board_card_pressed()` 的 `##` 注释（:693-695）：把「玩家移动会被屏蔽，因此完成时仍在同一位置」
      改写为「长按期间走出范围会立即取消，因此能走到完成回调时必定仍在范围内」。
- [ ] `_complete_terrain_hold()`：在 `GetTerrainInstanceOrNull() != terrain` 之后、
      可重复采集复查之前，补一道 `_try_get_interaction_range(card)` 复查；
      超出则 `_report_out_of_range_interaction` 后 return（不消耗行动值、不生成掉落）。
- [ ] 确认未改动 `_cancel_active_hold()`、`_on_board_card_released()`、`_exit_tree()` 的取消路径。

## 阶段 2：生产改动 —— 建筑（`core/building/building_controller.gd`）

- [ ] 新增字段 `_demolition_mouse_screen: Vector2 = Vector2.ZERO`：
      上一次采样的鼠标屏幕坐标，用于区分「玩家自己动了鼠标」与「相机跟随漂移」。
- [ ] 新增常量 `DEMOLITION_MOUSE_MOVE_TOLERANCE: float = 0.5`：屏幕位移超过它才算玩家主动移动鼠标。
- [ ] 新增 `_mouse_screen_position() -> Vector2`：
      `return _buildings_root.get_canvas_transform() * _mouse_world_position()`。
      **不要**直接读 `get_viewport().get_mouse_position()`——经 `_mouse_world_position()` 换算可以复用
      回归场景已经覆写的采样接口，不必新增替身接口。
- [ ] 新增 `_is_demolition_target_kept() -> bool`：
      取屏幕采样、与 `_demolition_mouse_screen` 比较、**每帧前移采样基准**；
      位移未超容差直接返回 true；超容差才调 `_building_under_pointer()` 复查，
      要求命中且 id 等于 `_demolition_id`。
- [ ] 新增 `_is_demolition_input_available() -> bool`：抽出两个门禁共用的输入与世界条件
      （`_demolition_id >= 0` + 左键按住 + `_world_available()` + `_placing_data == null`
      + 无界面打开 + `gui_get_hovered_control() == null`）。
- [ ] 新增 `_record_for_instance(instance_id: int) -> Dictionary`：遍历
      `_store.call("GetBuildings", _room)` 按 id 取记录；`_store` 无效或记录已删除时返回 `{}`。
      写法对齐既有的 `_building_world_position()`（:764-770）。
- [ ] 改写 `_can_continue_demolition()`：`_is_demolition_input_available()` +
      `_is_demolition_target_kept()` + `_record_for_instance(_demolition_id)` +
      **`_is_record_in_range(record)`**（只判距离，不判遮挡）；
      并改写其 `##` 注释与 :493 那行「重新命中当前鼠标目标」的注释。
- [ ] 新增 `_can_complete_demolition() -> bool`：同样用输入门禁 + 目标复查 + `_record_for_instance`，
      但距离判定换成 **`_is_record_reachable(record)`**（含遮挡）。
- [ ] `_complete_demolition()` :500 改调 `_can_complete_demolition()`。
- [ ] `_begin_demolition()`：在 `_demolition_id = int(record["id"])`（:474）之后、
      启动抖动与 `begin_timed_hold` 之前，写入首帧基准
      `_demolition_mouse_screen = _mouse_screen_position()`。
- [ ] 新增 `_out_of_range_demolition_record() -> Dictionary`：先确认 `_demolition_id >= 0`
      且左键仍按住，再取记录，只有 `not _is_record_in_range(record)` 时返回该记录。
- [ ] `_process()` 的拆除分支（:259-267）：门禁失败时先取 `_out_of_range_demolition_record()`
      再 `_cancel_demolition()`，非空则 `_show_building_out_of_range(record)`；
      成功分支的提示文案改为「正在拆除 · 松开左键、移开鼠标或走出交互范围取消」，
      并同步 :260 那行注释。
- [ ] 确认 `_building_under_pointer()`（:432）与 `_mouse_world_position()`（:534）**不改**，
      仍被按下路径（:424）与本次复查共用；`_begin_demolition()` 的开始门槛不动。
- [ ] `filesystem_manage(op="scan")` 让两个脚本重新解析。

## 阶段 3：测试

- [ ] 新增 `tests/godot/test_hold_move_within_range.gd`，`suite_name()` 返回本套件名。
- [ ] 新增 2 行壳 `tests/test_hold_move_within_range.gd`
      （`@tool` + `extends "res://tests/godot/test_hold_move_within_range.gd"`）。
- [ ] 地形卡：真实协调器脚本 `load(...).new()` + 内部类桩（`StubHold` / `StubFloatingText` / `StubCard`）
      注入内部字段，断言范围内不取消、超出范围取消一次且飘字一次、`is_instance_valid` 分支走无条件取消、
      按住方向键不再取消、完成入口在超出范围时不进入交互。
- [ ] 建筑：复用 `building_system_tests.gd` 里既有的
      `ControllerInputProbe extends "res://core/building/building_controller.gd"` 夹具思路，断言：
      - 注入鼠标位置**不变**、只改玩家位置（模拟相机漂移）→ `_can_continue_demolition()` 仍为 true。
      - 注入鼠标位置改到另一栋建筑 → 为 false（切换目标仍取消）。
      - 注入鼠标位置改到空白处 → 为 false（移开鼠标仍取消）。
      - 走出 `InteractionRadius` → 为 false。
      - 有遮挡时 `_can_continue_demolition()` 为 true，而 `_can_complete_demolition()` 为 false。
- [ ] 形状断言：协调器 `_process_terrain_hold_input` 不再含 `Input.get_vector`；
      建筑 `_can_continue_demolition` 含 `_is_record_in_range` 且**不含** `_is_record_reachable`；
      `_can_complete_demolition` 含 `_is_record_reachable`；`_is_demolition_target_kept` 含
      `_building_under_pointer`；提示文案含「走出交互范围」。
- [ ] `tests/godot/building_system_tests.gd:443` 的断言**保持不变**（新逻辑下仍取消），
      在其后补一条新覆盖：鼠标不动、只改玩家位置时 `hold.get("is_holding")` 仍为 true。
- [ ] 同步 `tests/godot/building_system_tests.gd:90` 的覆盖说明文案。
- [ ] 调整 `tests/godot/test_world_interaction_coordinator_contract.gd::test_interaction_range_gate`
      的 `_count_occurrences(...) == 2` 为 `3`，理由更新为「点击、长按开始、长按完成三个入口」。
- [ ] `filesystem_manage(op="scan")` 后 `test_run(suite="hold_move_within_range", verbose=true)`。

## 阶段 4：运行时验证

- [ ] `project_run(mode="custom", scene="res://tests/godot/building_system_tests.tscn")`，
      确认 :443「移开鼠标必须取消」与 :458「走远必须取消」都仍然通过，且新增覆盖通过。
      **预期会看到与本次无关的既有崩溃**：`:178` 读 `inputs[1].get("RequiredItem")`，
      而 `resources/recipe/res/campfire_recipe.tres` 的 `Inputs` 只有 1 项（3 树枝、无火）。
      `_check` 只累加失败不中断，且 `_ready()` 里该函数是同步调用，拆除用例仍会执行。
      **只报告，不在本任务修复。**
- [ ] `project_run(mode="custom", scene="res://scenes/Main.tscn")`，
      `logs_read(source="game")` 确认无 `SCRIPT ERROR` / `Parse Error`。
- [ ] 地形卡：真实长按 + `Input.action_press("move_right")` 后推进若干帧，
      断言长按仍在、`_active_terrain_hold_card` 未变、圆环仍可见；记得 `Input.action_release`。
- [ ] 地形卡：移出 `InteractionRange` 后推进一帧，断言长按被取消、圆环隐藏、
      `SetDestroying(false)` 已调用、飘字入口被调用。
- [ ] 地形卡完成入口：移出范围后直接调 `_complete_terrain_hold`，断言未进入 `_execute_terrain_interaction`。
- [ ] 建筑：放置一栋篝火，真实 `_begin_demolition` 后**不碰鼠标**、只把玩家在范围内移动若干帧，
      断言 `_can_continue_demolition()` 为 true、`_demolition_id` 未变、圆环仍可见。
- [ ] 建筑：把玩家移出该建筑 `InteractionRadius`，推进一帧后断言 `_demolition_id == -1`、
      建筑仍在、无掉落、飘字入口被调用。
- [ ] 建筑：重新开始拆除后把鼠标移到另一栋建筑 / 空白处，断言 `_demolition_id == -1`。
- [ ] 建筑遮挡：把玩家移到范围内但有墙遮挡的位置，断言每帧门禁仍为 true，
      而直接调 `_complete_demolition()` 不结算、建筑保留。
- [ ] `project_manage(op="stop")`；**不关闭 Godot 编辑器**。
- [ ] `git status` 确认编辑器没有改写无关文件。

## 阶段 5：文档与 spec

- [ ] `docs/游戏机制与玩法内容.md:15`：把「按下键盘方向键会取消尚未完成的地形长按」改写为
      「范围内移动不打断，超出 `InteractionRange` 才取消并给出距离不足反馈」。
- [ ] `docs/游戏机制与玩法内容.md:25`：取消触发条件列表加入「移动出交互范围」，
      并说明「拖出目标后松开」不再单独成立（松键本身就取消）。
- [ ] `docs/游戏机制与玩法内容.md:59`：拆除取消列表**保留**「移开鼠标、切换目标」，
      但补一句「相机跟随玩家造成的建筑位移不算移开鼠标」；把「出现遮挡」从取消条件挪到
      「完成瞬间拦截」，并加入「走出该建筑的 `InteractionRadius`」。
- [ ] `docs/建筑系统.md:15`：同上——保留移开鼠标/切换目标，写明判据是鼠标自己动了，
      遮挡只在完成瞬间拦，走出交互范围即取消。
- [ ] `docs/建筑系统.md:90`：覆盖说明补「鼠标不动时的相机漂移不取消」。
- [ ] `.trellis/spec/backend/gameplay-system-patterns.md` 的「交互与时间」补条目：
      - 长按期间「移动」不是取消条件，只有离开交互范围才是。
      - 需要按光标判定的长按（建筑）必须用**鼠标屏幕坐标**是否变化来区分玩家操作与相机漂移，
        不能每帧按世界坐标重新命中。
      - 每帧门禁与完成门禁必须拆开：每帧判距离，完成判可达性（含遮挡）。
      - 两条长按的完成入口都要按同一判定再复查一次（Tween 可能比每帧门禁先结算）。
      - 取消走按拥有者的 `cancel_hold_for`，不要无条件取消。

## 阶段 6：质量检查与收尾

- [ ] 载入 `trellis-check`，跑全量 `test_run` 并与改动前失败清单对比，确认零新增失败。
- [ ] 载入 `trellis-update-spec` 落盘阶段 5 的 spec 条目。
- [ ] 提交：`<work commit>` → `chore(task): archive 10-18-hold-move-within-range` → `chore: record journal`。
- [ ] 归档：`task.py archive 10-18-hold-move-within-range --skip-branch-validation`
      （本仓库 trunk-based，`branch == base_branch == "main"`，必须加该开关）。

## 验证证据

### 新增契约测试

`tests/godot/test_hold_move_within_range.gd`（壳：`tests/test_hold_move_within_range.gd`），
`test_run(suite="hold_move_within_range", verbose=true)` → **4 passed / 0 failed / 36 assertions**：

| 用例 | 断言 | 覆盖 |
|---|---|---|
| `test_source_contracts` | 19 | `_process_terrain_hold_input` 不读任何 `Input.`；范围复查复用 `_try_get_interaction_range`；`cancel_hold_for` + `_report_out_of_range_interaction`；`_complete_terrain_hold` 含 `_try_get_interaction_range(card)`；`_can_continue_demolition` 含 `_is_record_in_range` + `_is_demolition_target_kept` 且**不含** `_is_record_reachable`；`_can_complete_demolition` 含 `_is_record_reachable` + `_record_for_instance`；`_is_demolition_target_kept` 含 `_mouse_screen_position` + `DEMOLITION_MOUSE_MOVE_TOLERANCE` + `_building_under_pointer`；`_mouse_screen_position` 用 `get_canvas_transform()` 而非 `get_mouse_position()`；`_begin_demolition` 记录屏幕基准；`_out_of_range_demolition_record` 用 `_is_record_in_range` |
| `test_terrain_hold_survives_in_range_movement` | 5 | 范围内移动不清记录、不取消、不提示、不复位抖动 |
| `test_terrain_hold_cancels_when_leaving_range` | 9 | 越界走 `cancel_hold_for(card)`、清记录、飘「距离不够！」+ 半径 160、`SetDestroying(false)`、`EndWorldInteraction` |
| `test_terrain_hold_completion_rechecks_range` | 3 | 完成入口复查越界后不结算并给反馈 |

键盘路径无法在本运行器模拟：`move_*` 只写在 `project.godot`，编辑器进程的 `InputMap` 里没有它们
（`input_map_manage(op="list")` 的 `loaded_in_input_map` 全为 false），`Input.action_press` 会直接报错。
因此「键盘不再打断」由「该函数不读任何输入」的形状断言承担，语义面由范围内移动存活用例承担。

### 建筑回归场景

`tests/godot/building_system_tests.gd` 新增断言：「鼠标不动时在范围内移动不得取消拆除」
（`pointer` 保持 `Vector2(300, 200)`，`body.position` 移到 `Vector2(240, 220)`，`_process(0.01)`，
断言 `hold.get("is_holding")`），并把探针文档改为说明「`pointer` 不动 = 只有相机在漂移」。
`:443` 原有的「移开鼠标或换目标必须取消拆除」保持不变——它改 `pointer`，等价于玩家自己动了鼠标。

**该断言未能执行**：场景在 `_ready()` 一开始就被既有缺陷打断（见文末），游戏停在断点、
主循环不再推进，一项断言都不会执行（`game_status.status = "break"`、
`logs_read(source="game")` 为空）。同语义已在下面「运行期验证」的 Main 场景 `game_eval` 中实证。

### 运行期验证

`project_run(mode="custom", scene="res://scenes/Main.tscn")` + `game_eval`（真实场景、真实
`BuildingController` / `WorldInteractionCoordinator` / `RoomBuildingStore` / 棋盘卡 / 飘字服务）。
前置：隐藏开局 `SkillCardDraftScreen` 并 `tree.paused = false`，否则 `CanUseWorld()` 为 false；
用 `input_mouse` 真实按住左键，并把光标移出 `PlayerView`，否则 `gui_get_hovered_control()` 非空。

建筑（在 `player+(80,0)` 放一栋 `InteractionRadius = 120` 的篝火）：

| 组 | 结果 |
|---|---|
| 基础面 | `_mouse_screen_position()` 与 `canvas × get_global_mouse_position()` **逐位相同**；`_begin_demolition` 成功、`is_holding = true`；`_record_for_instance` 命中、`_is_record_in_range` / `_is_record_reachable` 均为 true |
| 漂移免疫 | 光标**不在**建筑上（`_building_under_pointer()` 为空）、玩家在范围内移动、`_process(0.01)` 后 `_demolition_id` 仍为 1、`is_holding` 仍为 true（旧实现必然在此取消） |
| 移开鼠标 | 把屏幕基准人为前移 200px → `_is_demolition_target_kept()` 由 true 变 false（基准每帧前移，所以 `_can_continue_demolition` 的第二次调用已看不到该位移——符合「每帧消费一次位移」的设计） |
| 走出范围 | 距离 440 > 120 → `_is_record_in_range = false`、`_out_of_range_demolition_record` 命中、`_process` 取消、建筑保留（`GetBuildings` 仍为 1） |
| 反馈 | 范围内移动飘字宿主子节点 0 → 0；越界后 0 → **2**（范围圈 + 「距离不够！」），半径取该建筑的 `InteractionRadius` |
| 遮挡只在完成拦 | 隐藏视图后 `_is_record_in_range = true` 但 `_is_record_reachable = false`；`_can_continue_demolition() = true`、`_process` 后仍为 1；`_complete_demolition()` 后为 -1 且建筑仍在（未结算） |

地形（真实 `scenes/ItemTerrian/Item.tscn` + `wood_terrain.tres` 的「浆果丛」，`InteractionRange = 160`）：

| 阶段 | 结果 |
|---|---|
| 起长按（距离 60） | `_active_terrain_hold_card` 记录该卡、共享长按 `is_holding = true`、ClickWalk `_world_interaction_active = true` |
| 范围内移动（距离 84.85） | 记录仍在、`is_holding` 仍为 true、飘字宿主 0 个子节点、`_world_interaction_active` 仍为 true |
| 走出范围（距离 540） | 记录清空、`is_holding = false`、飘字宿主 **2** 个子节点、`_world_interaction_active = false`、`IsHarvested` 仍为 false |
| 完成入口正/负对照 | 越界卡：`_try_get_interaction_range` 为 false → 结算被拦（`IsHarvested = false`）、给出反馈（宿主 +2）、记录清空、交互状态释放。范围内卡：`_try_get_interaction_range` 为 true → **照常结算**（`IsHarvested = true`）、无越界反馈（宿主 +0）。同一调用、同一地形，只差距离 |

### 既有套件回归

`test_run()` 全量：**585 passed / 12 failed / 39 skipped / 636 total / 76 suites**。
改动前基线为 581 / 12 / 39 / 632 / 75 —— 增量正好是本任务新增的 1 个套件 4 条用例，
**失败集合与基线逐条一致，零新增失败**。
`test_run(suite="world_interaction_coordinator_contract")` 的 3 条既有失败未增加。
`filesystem_manage(op="scan")` 后编辑日志中 26 条「新错误」全部来自既有测试噪声
（`test_item_room_content` 解析错误、`DayNightFilter` / 按键绑定回退警告、
`room_terrain_store` / `run_start_initializer` 负路径 `push_error`），
**没有一条来自本次改动的两个生产脚本或新测试文件**。
`git status` 复查：只有本任务需要的 4 个改动文件 + 4 个新增文件，编辑器未改写任何文件。

### 与本次无关的既有失败（只报告）

- `tests/godot/building_system_tests.gd:181`：`campfire_recipe.tres` 的 `Inputs` 只有 1 项（3 树枝），
  测试仍读 `inputs[1]`（火），`Out of bounds get index '1'`。在启用「出错时中断」的编辑器里，
  该错误会让游戏停在断点、**整个建筑回归场景一项断言都不执行**（`game_status.status = "break"`）。
  资源改过、测试没跟上，属独立任务；本次未修改，已在 `docs/建筑系统.md` 记录。
- `tests/godot/test_item_room_content.gd` 无法实例化（`Parse error, base=none`）：
  :42 / :47 调用 `get_tree()`，而 `McpTestSuite extends RefCounted` 没有该方法。
- 其余 12 条全量失败均为既有的 C#→GDScript 迁移审计类断言
  （`board_controller_contract`、`crafting_recipe_contract`、`final_migration_audit_contract` ×2、
  `gameflow_chain_contract`、`inventory_component_contract`、`map_ui_contract`、
  `reusable_gathering` ×2、`world_interaction_coordinator_contract` ×3）。

## 回滚点

| 回滚点 | 内容 | 恢复方式 |
|---|---|---|
| R-A | 阶段 1 完成后 | `git checkout -- core/gameflow/world_interaction_coordinator.gd` |
| R-B | 阶段 2 完成后 | `git checkout -- core/building/building_controller.gd` |
| R-C | 阶段 3 完成后 | 删除新套件与其壳文件，并还原计数断言 |
| R-D | 全部完成后 | `git revert` 本任务提交 |

## 验证命令速查

```bash
# 刷新脚本
filesystem_manage(op="scan")
# 新增套件（先确认 2 行壳存在）
test_run(suite="hold_move_within_range", verbose=true)
# 受影响的既有套件
test_run(suite="world_interaction_coordinator_contract", verbose=true)
# 全量回归
test_run()
# 建筑回归场景 + 主场景冒烟
project_run(mode="custom", scene="res://tests/godot/building_system_tests.tscn")
project_run(mode="custom", scene="res://scenes/Main.tscn")
logs_read(source="game")
game_eval(code="...")           # 地形卡 / 建筑漂移 / 切换目标 / 遮挡 四组断言
project_manage(op="stop")       # 只停游戏，不关编辑器
git status
```
