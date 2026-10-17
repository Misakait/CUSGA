# 执行计划：掉落物多张卡牌化与随机落点

对应 PRD 与设计：`prd.md`、`design.md`

平台：DeepSeek Harness（inline 分支）。按工作流，本平台跳过 `implement.jsonl` / `check.jsonl` 的子代理上下文装配，改为在编码前加载 `trellis-before-dev`、编码后加载 `trellis-check`。

## 阶段 0：编码前准备

- [x] 0.1 加载 `trellis-before-dev`，读取 `.trellis/spec/guides/index.md` 与 `backend`／`frontend` 相关层索引，确认本项目 GDScript 编码规范。
- [x] 0.2 `rg` 复核待删除/待改符号的全部引用：
  - `_spawn_single_loot_with_scatter`
  - `_safe_loot_position`
  - `SpawnLootCards`（含 `.gd` / `.tscn` / 测试桩）
  - `CanShowAmount`、`_amount`（`loot_view.gd`、`board_card_view.gd`、`board_card_state.gd`）
- [x] 0.3 `editor_state` 确认 Godot 4.7.1 编辑器已打开并加载 CUSGA；未连接则请用户打开，不用命令行 Godot。

**门禁 G0**：引用清单与规范读完，编辑器在线。✅ 通过。

> **踩坑记录（0.3）**：编辑器同时打开了 `hsr-kill` 与 `CUSGA` 两个会话，MCP 默认指向 `hsr-kill`，导致 `test_run` 报「0 discovered」并抛出无关项目的解析错误。必须先用 `session_manage(op="list")` 找到 `cusga@c24ae7011184e281`，再 `session_activate` 锁定本项目。之后所有 MCP 调用才作用在正确工程上。

## 阶段 1：主实现（`core/board/board_controller.gd`）

- [x] 1.1 新增常量：`SCATTER_PLACEMENT_ATTEMPTS = 16`、`LOOT_AREA_MIN = Vector2(90,90)`、`LOOT_AREA_MAX = Vector2(1190,630)`、`CIRCLE_PACKING_AREA_FACTOR = 0.866`、`LOOT_STACK_SCRIPT`；新增 `@export var LootMinSeparation`（`##` 文档注释说明用途与默认值依据）。
- [x] 1.2 实现 `_expand_loot_units(stacks: Array) -> Array[RefCounted]`：
  - 跳过不满足 `_is_readable_item_stack()` 的条目；
  - `Amount == 1` 直接复用引用；
  - `Amount > 1` 用 `Duplicate()` + `Amount = 1` 逐单位展开，无 `Duplicate()` 时走新建堆叠回退；
  - 不修改入参堆叠。
- [x] 1.3 实现 `_plan_loot_positions(origin: Vector2, count: int, use_room_bounds: bool) -> Array[Vector2]`：
  - 外半径按 `sqrt(Rmin^2 + count * 0.866 * d^2 / PI)` 自适应，取 `max()`；
  - 每点最多 16 次随机候选，先夹取边界（`use_room_bounds` 为真时）再判最小间距；
  - 全部失败时采用最后一个候选并注释说明降级策略。
- [x] 1.4 改写 `SpawnLootCards(stacks, spawn_origin)`：先展开单位，再按仓库分支/遗留分支分别用 `_plan_loot_positions()` 的落点逐张生成；仓库分支仍传同一个 `spawn_origin` 作为散射起点。
- [x] 1.5 删除 `_spawn_single_loot_with_scatter()`（已被 1.4 取代），`_safe_loot_position()` 的夹取逻辑并入 1.3 后一并移除。
- [x] 1.6 保留 `SpawnLootRecord` / `SpawnLootRecordWithScatter` 原样（恢复路径不拆分）。

**门禁 G1**：`filesystem_manage(op="scan")` 后无 `Parse Error`；`board_controller.gd` 内不再有对已删除函数的引用。✅ 通过（全仓 `rg` 对两个已删除函数零命中）。

> **偏差（1.1）**：`LootMinSeparation` 默认值由计划的 44.0 改为 **56.0**。依据是掉落卡实际可视尺寸：`Loot.tscn` 的 `PlayerView` 为 100×140，按 `LootVisualScale`(0.4) 缩放后约 40×56；取较长边才能保证两张卡不叠成一张，44 只覆盖了宽度。`design.md` §2/§4 已同步。

## 阶段 2：数量标签注释（不改行为）

- [x] 2.1 `scripts/loot_scripts/loot_view.gd::RefreshView()`：在 `amount > 1` 分支加中文注释，说明掉落链路保证单件、本分支暂时不生效、保留作旧快照兜底。
- [x] 2.2 `core/board/board_card_view.gd::RefreshView()`：同上。
- [x] 2.3 `core/board/board_card_state.gd::CanShowAmount()`：同上，说明返回值语义在当前掉落链路下恒为 false。

**门禁 G2**：三处仅为注释新增，`git diff` 中无逻辑改动。✅ 通过（`git diff --numstat`：4 / 3 / 3 行，全部为新增注释，删除数为 0）。

## 阶段 3：测试

- [x] 3.1 新增 `tests/godot/test_loot_multi_card_scatter.gd`，覆盖：
  - 3 件同一物品 → 展开成 3 个 `Amount == 1` 且互不相同的堆叠；
  - 3 张卡落点两两距离 `>= LootMinSeparation`（原点取房间中心，避开边界夹取退化）；
  - 1 件掉落 → 复用原引用（装备路径零拷贝）；
  - 入参堆叠的 `Amount` 未被修改（防就地掏空）；
  - 空值/空堆叠被跳过；
  - 贴边原点时落点仍在房间夹取范围内；
  - 12 张时外半径自动放大，验证半径自适应；
  - 快照往返后记录条数、单件语义与落点位置均保持（`test_snapshot_round_trip_preserves_unit_records`）；
  - 移除其中一条记录只影响该条、其余保留且不可重复移除（`test_removing_one_record_keeps_other_cards`）。
- [x] 3.2 更新因签名/行为变化而失配的既有断言：经 `rg` 确认**不存在**针对 `_spawn_single_loot_with_scatter` 的源码字符串断言，无需修改任何既有测试。
- [x] 3.3 逐个确认既有掉落相关测试结果（详见下方「验证证据」）。

**门禁 G3**：上述测试全绿；若有失败，先判断是实现缺陷还是契约过时，契约过时必须说明理由再改断言。✅ 通过——本次改动相关套件全绿，失败项经 `git show HEAD:...` 逐一确认在改动前即存在。

> **测试脚手架**：`test_run` 只枚举 `res://tests` 的**直接子节点**，`tests/godot/` 下的套件必须配一个 2 行外壳（`tests/test_loot_multi_card_scatter.gd`：`@tool` + `extends "res://tests/godot/test_xxx.gd"`），且套件需覆写 `suite_name()`。新增外壳后必须再跑一次 `filesystem_manage(op="scan")`，插件重载不会刷新该缓存。

## 阶段 4：运行时验证

- [x] 4.1 `project_run(mode="custom", scene="res://scenes/Main.tscn", autosave=false)` 启动主场景。
- [x] 4.2 `logs_read(source="game")` 确认无 `SCRIPT ERROR` / `Parse Error` / 本次改动引入的资源加载错误。
- [x] 4.3 `game_eval` 统计当前房间掉落记录：断言每条 `Amount == 1`，并计算最小两两距离。
- [x] 4.4 目视确认多张卡分散、右下角无数字 → **改用几何断言替代**（见下方偏差）。
- [x] 4.5 `project_manage(op="stop")` 停止游戏（不关闭编辑器）。
- [x] 4.6 `git status` 复核：只保留本任务需要的改动。

**门禁 G4**：运行无错误、结果符合 PRD 验收标准、工作区干净可控。✅ 通过。

> **偏差（4.4）**：`editor_screenshot(source="game")` 能取到画面，但当前模型不声明图像输入，截图无法被阅读，不构成可复核证据。改为 `game_eval` 读取每张卡的 `global_position` 并计算最小两两距离，断言其与 `RoomLootStore` 规划位置一致。该替代方案已写入 `design.md` §7。
>
> **关键陷阱**：首次几何核验时 3 张卡的 `global_position` 全部等于掉落原点，看似落点没生效。实际是 `debug_status` 报告 `tree_paused: true`（`settlement_manager.gd` 的结算流程暂停了整棵树），暂停时 `PlayScatterFrom()` 的 Tween 一帧都不推进。`tree.paused = false` 后复测即得到正确落点。

## 阶段 5：质量检查与收尾

- [x] 5.1 加载 `trellis-check` 做规范符合性、跨层数据流与复用一致性检查。
- [x] 5.2 在 `trellis-update-spec` 中沉淀「世界掉落卡恒为单件」不变量与两条验证经验。
- [ ] 5.3 汇总改动与验证证据，等待用户提交许可；不自动提交、不自动归档。

## 验证证据

### 新增契约测试

`test_run(suite="loot_multi_card_scatter")` → **9 passed / 0 failed，39 断言**。

### 既有套件回归（改动后）

| 套件 | 结果 |
|---|---|
| `loot_multi_card_scatter`（新增） | 7 通过 |
| `board_card_view_contract` | 1 通过 |
| `equipment_configuration` | 6 通过 |
| `loot_auto_pickup_contract` | 3 通过 |
| `room_board_presenter_contract` | 5 通过 / 1 跳过 |
| `board_controller_contract` | 5 通过 / 1 既有失败 / 1 跳过 |
| `reusable_gathering` | 56 通过 / 2 既有失败 |
| `world_interaction_coordinator_contract` | 6 通过 / 3 既有失败 / 1 跳过 |
| `gameflow_chain_contract` | 3 通过 / 1 既有失败 |

**既有失败（改动前即存在，非本次引入，不在本任务范围内修复）**：

- `tests/godot/test_item_room_content.gd` 加载失败（`cannot instantiate — abstract or broken`），该文件在本次改动中未被触碰。
- `tests/godot/building_system_tests.tscn` 在第 178 行 `var fire: Resource = inputs[1].get("RequiredItem")` 抛 `Out of bounds get index '1' (on base: 'Array[Resource]')`，整个场景中断、**零断言执行**（`game_status.status == "break"`）。根因是 `resources/recipe/res/campfire_recipe.tres` 的 `Inputs` 只有 1 项（树枝），测试却按「三树枝 + 一火」的 2 项配方写；配方最后一次改动是 `31df872 feat:修改篝火配方`。`resources/recipe`、`tests/godot/building_system_tests.*`、`core/building`、`core/crafting` 本次均未改动（`git diff HEAD --stat` 为空），因此该崩溃与掉落无关。受影响的是其中的篝火拆除掉落断言（位于棋盘入口之前，本次未触及该层）。
- `board_controller_contract::test_shared_log_and_error_texts` 期望文案「BoardController.CardViewScene 未设置。」在 `HEAD` 与工作区中均不存在。
- `reusable_gathering` 2 项失败与 `res://items/tool/Ax.tres` 的遗留 C# 元数据有关。
- `world_interaction_coordinator_contract` 3 项失败（`fade_complete`、缺失 `_run_screen_transition(...)`、缺失「无法加载战斗背景解析器：」），同样的缺失函数断言也出现在 `gameflow_chain_contract::test_chain_boundaries`。

### 运行时冒烟

主场景 `res://scenes/Main.tscn`（房间 `(4, 1)`），经 `game_eval` 直接调用生产入口 `SpawnLootCards`：

| 场景 | 结果 |
|---|---|
| 3 件掉落 | `{"added":3,"amounts":"[1, 1, 1]","unique_ids":true,"min_record_dist":68.98,"loot_cards":3,"labels":"[false, false, false]","source_amount":3}` |
| 1 件掉落 | `{"added":1,"new_amounts":"[1]","loot_cards":1,"labels":"[false]"}` |
| 解暂停后卡牌实际坐标 | `(970,617)`、`(1115,630)`、`(1084,536)`，最小两两距离 **99.183**，与仓库记录中的规划位置逐位一致 |
| 恢复入口 `SpawnLootRecord` | 卡牌落在记录位置，`delta: 0`，标签隐藏（房间重建不重新随机） |

来源堆叠 `Amount` 在全部用例后仍为原值，未被就地掏空。`logs_read(source="game")` 只有 `InitializeWithData` 与 `[RoomBoardPresenter] Enter room ...` 等 info 行，无 `SCRIPT ERROR` / `Parse Error`。

## 回滚点

| 回滚点 | 操作 |
|---|---|
| R1（阶段 1 后） | `git checkout -- core/board/board_controller.gd` |
| R2（阶段 2 后） | 注释改动不影响运行，可保留 |
| R3（阶段 3 后） | 删除 `tests/godot/test_loot_multi_card_scatter.gd` 与 `tests/test_loot_multi_card_scatter.gd` 及其 `.uid` |
| 全量 | 上述三者合并即恢复改动前状态 |

## 验证命令速查

```bash
python ./.trellis/scripts/task.py current
```

Godot 编辑器 MCP 顺序：`session_manage(op="list")` → `session_activate` → `editor_state` → `filesystem_manage(op="scan")` → `test_run(suite=..., test_name=...)` → `project_run(mode="custom", scene="res://scenes/Main.tscn")` → `logs_read(source="game")` → `game_manage(op="debug_status")` → `game_eval` → `project_manage(op="stop")`。
