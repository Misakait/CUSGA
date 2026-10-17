# 掉落物多张卡牌化与随机落点

状态：用户已确认任务创建与三项范围决策（保证最小间距、数量标签暂时不使用并加注释、拆分方案由实现方定），等待评审规划产出后再 `task.py start`。未开始编码。

## 目标

掉落多个相同物品时，世界里出现的是「实际数量张掉落物卡牌」，而不是「一张卡牌 + 右下角数量标签」。每张卡牌出现在各自随机的落点上，彼此不重叠成一堆。

## 已确认背景

- 掉落数据源头是 `resources/loot/loot_table.gd` 的 `RollLoot()`：每个 `LootDrop` 生成一个 `ItemStack`，数量为 `randi_range(MinAmount, MaxAmount) + yield_growth`。
- `RollLoot()` 目前**只对装备**逐件拆分（每件 `Amount == 1`，各自 `RollRandomStats()`），普通物品仍合并成一个 `Amount == N` 的大堆叠；注释明确写着「普通物品保留原有单堆掉落形状」。
- 所有世界掉落都经 `core/board/board_controller.gd` 的 `SpawnLootCards(stacks, spawn_origin)` 落地：逐堆叠调用 `_safe_loot_position()`（随机角度 + `randf_range(ScatterRadiusMin, ScatterRadiusMax)`，再夹到房间局部 `x∈[90,1190]、y∈[90,630]`），登记 `RoomLootStore.AddLoot()` 后生成一张卡并播放散射动画。
- 生产掉落卡视图是 `scripts/loot_scripts/loot_view.gd`，数量显示在 `_amount`（`$Visuals/PlayerView/Amount`），条件为 `amount > 1`（第 162-164 行）。遗留视图 `core/board/board_card_view.gd` 与状态对象 `core/board/board_card_state.gd::CanShowAmount()` 也持有同一套「数量 > 1 才显示」的语义。
- `core/map/room_loot_store.gd` 一条记录承载一个堆叠：`{id, stack, position}`，快照编码字段为 `amount` 与 `position`，恢复走 `BoardController.SpawnLootRecord()` 直接按记录位置建卡（不播散射）。
- 掉落卡命中形状是 `scenes/Loot/Loot.tscn` 的 `RectangleShape2D_interaction`，尺寸 37.2×54.8，与视觉 `Visuals` 是兄弟节点，不随 `LootVisualScale`(0.4) 缩放。
- `scenes/Main.tscn` 未覆盖 `ScatterRadiusMin/Max`，生产运行时为默认 40/90。
- 掉落卡的消费方只有棋盘：`world_interaction_coordinator.gd`、`building_controller.gd`、怪物掉落事件最终都调 `SpawnLootCards`；拾取入口 `_handle_loot_card_pickup()` 把卡牌堆叠整体交给 `TryAddItemToInventory`。

## 需求

1. 同一物品掉落 N 件时，世界中生成 N 张掉落物卡牌，每张卡牌只承载 1 件物品，不再用右下角数字表示数量。
2. 每张卡牌的落点独立随机，不同卡牌落点两两之间不小于配置的最小间距。
3. 张数较多时随机范围要能容纳下这些卡牌，不能因为散射半径过小而把多张卡牌压在同一个圆环里反复重试失败。
4. 拆分后每张卡牌仍是独立堆叠对象：拾取其中一张只消耗该张的 1 件，其它卡牌不受影响。
5. 装备掉落行为不改变：`RollLoot()` 已经逐件生成，新增逻辑不得二次拆分或破坏其独立洗炼属性。
6. 房间仓库记录与局内存档快照保持「一条记录 = 一张卡」的自洽关系，恢复后卡牌数量与位置与掉落当时一致。
7. 数量标签**暂时不使用**：保留原有显示代码并在注释中说明当前掉落卡恒为单件、该分支作为兜底暂时保留，不删除相关节点与测试契约。
8. 掉落系统对外方法签名保持不变：`SpawnLootCards(stacks: Array, spawn_origin: Vector2) -> void`、`SpawnLootCard`、`SpawnLootRecord`、`SpawnLootRecordWithScatter` 名称与参数不调整，避免影响跨语言调用方与既有测试契约。

## 验收标准

- [x] 单次破坏产出 3 件相同物品时，棋盘出现 3 张该物品卡牌，`Amount` 均为 1，右下角不显示任何数字。
  - 证据：运行期 `game_eval` → `{"added":3,"amounts":"[1, 1, 1]","loot_cards":3,"labels":"[false, false, false]"}`；套件 `test_multi_amount_stack_expands_into_single_unit_stacks`。
- [x] 上述 3 张卡牌落点两两距离不小于配置的最小间距（在房间边界夹取后仍成立）。
  - 证据：运行期记录落点最小两两距离 68.98 与 99.18（均 ≥ 56）；套件 `test_plan_positions_keeps_minimum_separation`、`test_plan_positions_stays_inside_room_bounds`。
- [x] 掉落 1 件时行为与改动前一致：仍是一张卡，位置仍为随机落点并播放散射动画。
  - 证据：运行期 `game_eval` → `{"added":1,"new_amounts":"[1]","loot_cards":1,"labels":"[false]"}`；套件 `test_single_amount_stack_is_reused_without_copying`、`test_scatter_outer_radius_expands_for_many_cards`（count=1 时外半径仍为 90）。
- [x] 装备掉落仍为逐件独立卡牌，每件洗炼属性互相独立，数量不因新逻辑改变。
  - 证据：`Amount == 1` 的堆叠原引用复用、不创建副本（同上前者用例），`Duplicate()` 保留 `RolledAttributes` 并阻止重随机；`equipment_configuration` 6/6 通过。
- [x] 拾取多张卡牌中的一张，只有该卡消失，其余卡牌保持在场且数量不变。
  - 证据：套件 `test_removing_one_record_keeps_other_cards`（移除中间记录后剩 2 条、其余 id 原样保留、重复移除返回 false）。
- [x] 掉落生成后立即存档快照再恢复，卡牌张数与位置与生成时一致。
  - 证据：套件 `test_snapshot_round_trip_preserves_unit_records`（3 条 → 编码 → 恢复仍 3 条，`Amount` 全为 1，落点逐条 `is_equal_approx`）。
- [x] 房间流式卸载再进入，掉落卡按记录位置重建，不重新随机。
  - 证据：运行期 `game_eval` 直接走恢复入口 `SpawnLootRecord`，落点与记录位置偏差 0（`delta: 0`），标签隐藏；房间流式本身由既有 `room_board_presenter_contract` 覆盖。
- [x] 数量标签代码仍在，但单件掉落时不显示；注释说明「暂时不使用」的原因。
  - 证据：三处仅新增注释（`git diff --numstat` 删除数均为 0）；运行期 4 张卡的数量标签 `visible` 全为 `false`。
- [ ] 既有掉落相关测试（棋盘契约、掉落表契约、房间内容恢复、篝火掉落数量）全部通过。
  - **未达成，且非本次改动引入**：`test_item_room_content` 与 `building_system_tests.tscn` 在改动前即已损坏，详见下方「既有阻塞」。
- [x] Godot 4.7.1 编辑器 MCP 下开启本任务新增测试并通过；主场景与掉落相关场景冒烟无 `SCRIPT ERROR`/`Parse Error`。
  - 证据：`test_run(suite="loot_multi_card_scatter")` → 9 通过 / 0 失败 / 39 断言；`project_run(mode="custom", scene="res://scenes/Main.tscn")` → `status: "live"`，`logs_read(source="game")` 仅 info 行。

## 既有阻塞（改动前即存在，不在本任务范围）

1. `tests/godot/test_item_room_content.gd` 无法实例化：`cannot instantiate — abstract or broken; reload=Parse error, base=none, valid=false`。该文件本次未被修改。
2. `tests/godot/building_system_tests.tscn` 在第 178 行 `var fire: Resource = inputs[1].get("RequiredItem")` 抛 `Out of bounds get index '1' (on base: 'Array[Resource]')`，整个场景中断、零断言执行。根因是 `resources/recipe/res/campfire_recipe.tres` 的 `Inputs` 只有 1 项（树枝），而测试仍按「三树枝 + 一火」的 2 项配方编写；配方最后一次改动是 `31df872 feat:修改篝火配方`。**该崩溃与掉落无关**：`resources/recipe`、`tests/godot/building_system_tests.*`、`core/building`、`core/crafting` 本次均未改动（`git diff HEAD --stat` 为空）。
3. 受第 2 条影响，`building_system_tests` 中的「篝火拆除生成一个掉落堆叠 / 恰好一个配方同源树枝」两条断言本轮**没有执行**。它们断言的是 `building_service` 返回的 `drops` 数组（位于棋盘入口之前），本次改动未触及该层；1 件掉落 → 1 张卡已由上面的运行期与套件证据独立覆盖。
4. `board_controller_contract::test_shared_log_and_error_texts`、`reusable_gathering` 的 2 项、`world_interaction_coordinator_contract` 的 3 项、`gameflow_chain_contract::test_chain_boundaries` 均为改动前既有失败，明细见 `implement.md`。

## 范围

### 本轮包含

- `core/board/board_controller.gd`：按数量展开逐单位堆叠、带最小间距的落点分配、两条生成分支统一。
- 掉落卡视图/状态中数量标签的「暂时不使用」注释说明（不改节点、不删代码路径）。
- 新增/更新 `tests/godot/` 下针对「N 件 → N 张卡 + 最小间距」的契约测试。
- 若拆分后暴露出与 `RoomLootStore` 记录假设的冲突，一并修正并补测试。

### 本轮不包含

- 不修改 `RollLoot()` 的产出形状（普通物品仍返回单个大堆叠），保证掉落表契约与掉落数值玩法不变。
- 不改掉落概率、数量范围、稀有度、洗炼规则等玩法数值。
- 不重做掉落卡美术、待机/悬停/飞行动画参数。
- 不为旧存档中已有的 `amount > 1` 掉落记录做拆分迁移（见设计说明）。
- 不调整自动拾取半径与拾取结算逻辑。

## 待确认 / 实现默认

- 最小间距默认值与散射半径扩张公式由设计文档给出依据；若需要在 Inspector 调整，以 `@export` 暴露，默认值不改动既有场景序列化。
- 旧局快照里 `amount > 1` 的掉落记录保持原样恢复成一张带数量数字的卡（数量标签兜底分支正是为此保留），本轮不做自动拆分。
- 张数上限不额外限制；极大量掉落时以最小间距重试的接受策略保证不卡帧。
