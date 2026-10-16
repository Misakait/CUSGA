# 掉落物自动拾取与缩小 —— 执行计划

## 前置门禁

- [x] 任务状态已由 `task.py start` 置为 `in_progress`
- [x] Godot 4.7.1 编辑器已打开并加载 CUSGA：`editor_state` 或 `session_manage(op="list")` 确认
- [x] `git status` 干净，确认本次改动前没有未提交的用户改动
- [x] 已读 `.trellis/spec/backend/gameplay-system-patterns.md` 与 `.trellis/spec/frontend/component-guidelines.md`

## 执行顺序

改动按「表现层 → 资源 → 逻辑层 → 测试 → 文档」推进，每一步都可独立验证，且前一步不依赖后一步。

### 步骤 1：掉落视图缩放与可拾取协议

文件：`scripts/loot_scripts/loot_view.gd`

- [x] 1.1 在 `MotionConfig` 导出下方新增 `LootVisualScale` 导出（中文 `##` 文档注释，说明「命中区域不随本值变化」）
- [x] 1.2 把 `InitializeLoot` 里的 `_base_visual_scale = Vector2.ONE` 改为 `_base_visual_scale = Vector2.ONE * LootVisualScale`，并加行内注释说明为什么改这一处就能覆盖四种表现
- [x] 1.3 新增 `IsPickupAvailable() -> bool`，带 `##` 文档注释说明它挡住的是「`DetachForFlight` 不从 `_active_cards` 移除」导致的二次拾取
- [x] 1.4 确认 `_configure_motion()` 在 `InitializeLoot` 中**位于** `_base_visual_scale` 赋值之后（否则动画轨道会用到旧基准）

验证点：`filesystem_manage(op="scan")` 后无解析错误。

### 步骤 2：命中区域缩放

文件：`scenes/Loot/Loot.tscn`

- [x] 2.1 `RectangleShape2D_interaction` 的 `size` 由 `Vector2(93, 137)` 改为 `Vector2(37.2, 54.8)`
- [x] 2.2 不改 `Loot.tscn` 的节点结构、`collision_layer` / `collision_mask`、动画库与 `MotionConfig` 绑定

> 用编辑器 MCP 改而不是手写文本，避免 Godot 重写文件时产生无关 diff。若手改，改完必须 `filesystem_manage(op="reimport", paths=["res://scenes/Loot/Loot.tscn"])` 并确认编辑器已重载。

### 步骤 3：协调器换触发源

文件：`core/gameflow/world_interaction_coordinator.gd`

- [x] 3.1 在 `InteractionRange` 之后新增 `@export_group("Auto Pickup")` 与 `AutoPickupRange` 导出
- [x] 3.2 把现有 `_process` 的长按取消逻辑**原样**搬进新的 `_process_terrain_hold_input()`，`_process` 改为先调 `_process_auto_pickup()` 再调 `_process_terrain_hold_input()`
- [x] 3.3 新增 `_process_auto_pickup()`：门禁 `_is_run_ending()` / `CanUseWorld()` → 取 `GetActiveCardsSnapshot()` → 逐张卡走 `_should_auto_pickup` → 命中则 `_handle_loot_card_pickup`
- [x] 3.4 新增 `_is_loot_card(card) -> bool`（用 `_read_ref_counted_property(card, "GetLootStackOrNull")`）
- [x] 3.5 新增 `_should_auto_pickup(card) -> bool`：有效 → 是掉落卡 → `IsPickupAvailable`（`has_method` 兼容缺失）→ 在半径内
- [x] 3.6 新增 `_is_loot_within_auto_pickup_range(card) -> bool`
- [x] 3.7 `_on_board_card_clicked`：删除 `GetLootStackOrNull` + `_handle_loot_card_clicked` 分支；在距离判定**之前**插入 `if _is_loot_card(card): return`
- [x] 3.8 `_on_board_card_pressed`：在距离判定**之前**插入 `if _is_loot_card(card): return`
- [x] 3.9 `_handle_loot_card_clicked` 改名为 `_handle_loot_card_pickup`，更新文档注释；函数体语义不变
- [x] 3.10 **逐字复核**以下被契约测试锁定的字面量未被改动：
  - `var range_check: Dictionary = _try_get_interaction_range(card)` —— 必须仍是 **2** 次
  - `var distance: float = _player_char.global_position.distance_to(card.global_position)`
  - `return {"ok": distance <= InteractionRange, "distance": distance}`
  - `card.call("PlayFlyTo", target, Callable(self, "_on_loot_fly_finished").bind(card))`
  - `_board_controller.call("GetActiveCardsSnapshot")`、`_board_controller.call("RemoveCard", card)`
  - 协调器内**不得**出现 `_card_display_name(`

**门禁 1（必须先过）**：`filesystem_manage(op="scan")` → `test_run(suite="world_interaction_coordinator_contract")` 全绿。未过不得继续。

### 步骤 4：契约测试同步

文件：`tests/godot/test_world_interaction_coordinator_contract.gd`

- [x] 4.1 `GD_EXPORTS` 追加 `AutoPickupRange` 的导出字面量，把新参数纳入锁定面
- [x] 4.2 更新 `test_interaction_range_gate` 的注释：说明掉落拾取已改为靠近自动触发，但两个鼠标入口的距离判定与 2 次计数断言不变
- [x] 4.3 **不删除**任何现有断言

### 步骤 5：新增自动拾取契约测试

文件：`tests/godot/test_loot_auto_pickup_contract.gd`（新建，`@tool extends McpTestSuite`）
壳文件：`tests/test_loot_auto_pickup_contract.gd`（新建，**必需**，否则 `test_run` 发现不到）

- [x] 5.1 先写顶层壳文件，只有两行：
  ```gdscript
  @tool
  extends "res://tests/godot/test_loot_auto_pickup_contract.gd"
  ```
- [x] 5.2 `suite_name()` 返回 `"loot_auto_pickup_contract"`（与文件名去掉 `test_` 前缀一致）
- [x] 5.3 套件头注释写明限制：本套件**只做源码形状与场景形状断言**；`loot_view.gd` 与 `world_interaction_coordinator.gd` 都不是 `@tool`，编辑器占位实例方法不可调用，运行期行为由冒烟阶段的 `game_eval` 实证（依据 `testing-guidelines.md:39`）
- [x] 5.4 源码形状断言（全部为**正向存在性**）：
  - `loot_view.gd` 含 `LootVisualScale`、`IsPickupAvailable`
  - `loot_view.gd` 含 `_base_visual_scale = Vector2.ONE * LootVisualScale`
  - `Loot.tscn` 含 `Vector2(37.2, 54.8)`
  - 协调器含 `AutoPickupRange`、`_process_auto_pickup`、`_should_auto_pickup`、`_is_loot_card`、`_is_loot_within_auto_pickup_range`、`_handle_loot_card_pickup`
- [x] 5.5 **不做**对旧标识符（如旧方法名）的 `assert_false(contains(...))` 否定断言：套件里解释「不要再用旧入口」的注释本身会包含该标识符，否定断言必然变红（`testing-guidelines.md:41-49`）。改为在 `game_eval` 里断言点击不产生拾取副作用。
- [x] 5.6 **不**在套件里实例化 `Loot.tscn` 或协调器脚本做运行时断言（非 `@tool` 占位实例方法不可调用）

### 步骤 6：文档同步

文件：`docs/游戏机制与玩法内容.md`

- [x] 6.1 `:31` 附近补 `AutoPickupRange` 的默认值与语义，并说明它与 `InteractionRange` 的分工
- [x] 6.2 `:532` 段落更新：掉落物视觉缩放（`LootVisualScale = 0.4`）、命中区域 `37.2×54.8`、「不再支持点击拾取，改为靠近自动拾取」

### 步骤 7：验证

- [x] 7.1 `filesystem_manage(op="scan")` 刷新全部改动脚本
- [x] 7.2 `test_run(suite="loot_auto_pickup_contract")` —— 实测 **3/3 通过、20 项断言**
- [x] 7.3 `test_run(suite="world_interaction_coordinator_contract")` —— 实测 6 通过 / 3 失败 / 1 跳过；**3 项失败全部是上表既有失败**，改动前后完全一致，无新增（`test_production_script_shape` 断言数 49→50，说明新增的 `AutoPickupRange` 导出断言已执行并通过）
- [x] 7.4 `test_run(suite="board_card_view_contract")` —— 实测 **1/1 通过**，证明遗留 `board_card_view.gd` / `BoardCardView.tscn` 未被误伤
- [x] 7.5 `test_run(suite="board_controller_contract")` —— 实测 5 通过 / 1 失败；该失败为既有失败（`board_controller.gd` 不在本次改动列表内，且断言目标文本在 HEAD 与工作区都不存在）
- [x] 7.6 `test_run()` 全量套件 —— 实测 **561 通过 / 12 失败 / 39 跳过**（共 612 项、73 个套件）；12 项失败与实施前基线**逐项一致**，本次改动**未引入任何新失败**，新套件 `loot_auto_pickup_contract` 在通过之列
- [x] 7.7 冒烟：主场景为 `login_menu.tscn`，玩法场景改为直接跑 `project_run(mode="custom", scene="res://scenes/Main.tscn")` → 游戏日志无 `SCRIPT ERROR` / `Parse Error` / `Failed to load script` / 资源加载错误，仅有正常的进入房间日志
- [x] 7.8 `game_eval` 运行时实证（在运行中的游戏里执行；写法约束见下）：
  - 经 `Engine.get_main_loop() as SceneTree` 取 `WorldInteractionCoordinator`、`BoardController`、`PlayerChar`、`RoomLootStore`
  - **判定助手**：构造/取一张掉落卡，把玩家移到半径外 → 断言 `_should_auto_pickup(card)` 为假；移到半径内 → 为真；把该卡 `IsPickupAvailable()` 置假（或取一张正在飞行的卡）→ 为假
  - **靠近入包**：把玩家移到 `AutoPickupRange` 内 → 断言物品入包、`RoomLootStore` 记录被删、掉落卡进入飞入
  - **飞入缩小消失**：对该卡取 `_visuals` 并 `Tween.custom_step()` 推进到 `PickupDuration` 之后 → 断言 `_visuals.scale` 已到 `Vector2.ZERO` 且卡已被 `RemoveCard`（节点失效）
  - **背包满不触发**：把背包填满 → 把玩家移到范围内 → 断言**未**入包、掉落卡仍在原地、`RoomLootStore` 记录仍在
  - **腾出空间后触发**：清出一格 → 再推进一帧 → 断言拾取发生
  - **点击不拾取**：对范围内的掉落卡触发点击入口 → 断言未入包
- [x] 7.9 `editor_screenshot(source="game")` 已截图（`stale_frame: false`），但当前模型无法读取图片内容，因此按 `testing-guidelines.md:73` 改用**几何数据**核验，结果见下方「运行时实证」第 1 组
- [x] 7.10 `project_manage(op="stop")` 停止游戏（**不得**关闭编辑器）
- [x] 7.11 `git status` 复核：只保留本次任务需要的改动，未被 Godot 编辑器改写的无关文件

### `game_eval` 写法约束（`testing-guidelines.md:65-73`）

- **不用 `get_tree()`**：eval 上下文里它返回 `null`。一律 `Engine.get_main_loop() as SceneTree` 再取 `tree.root`。
- **运行期错误会冻结游戏**：helper 仍在注册但不再服务，后续 eval 只拿到 `EVAL_GAME_NOT_READY`；恢复只能 `project_manage(op="stop")` 后重新 `project_run`（`game_manage(op="resume")` 无效）。
- **窗口不能后台化**：主循环冻结时任何 `await` 都挂到 `EVAL_HUNG`，截图会返回 `stale_frame: true`。断言尽量写成同步取值 + 比较。
- **动画时序用 `Tween.custom_step(delta)`**：同步 eval 期间场景树不推进帧，因此推进量完全可控，可精确断言「推进到 `PickupDuration` 之后缩放归零」。
- 一次 eval 只做一组断言，出错时能立刻定位是哪一组。

## 运行时实证（`game_eval`，Godot 4.7.1 / `res://scenes/Main.tscn`）

以下结果全部取自**运行中的游戏**，不是编辑器内的占位实例。

### 1. 掉落物缩到 40% 且命中区域同步

> 本节数值在 20% → 40% 调整后**重新真机实测**（`game_eval`），不是按比例推算填入的。

| 观测项 | 实测值 | 期望 |
| --- | --- | --- |
| `LootVisualScale` 导出 | `0.4` | 0.4 |
| `_base_visual_scale` | `(0.4, 0.4)` | 0.4 |
| `InitializeLoot` 后 `Visuals.scale` | `(0.4, 0.4)` | 0.4 |
| 命中形状 `RectangleShape2D.size` | `(37.2, 54.8)` | 93×137 的 40% |
| `Idle` 轨道关键帧 | `0.4 → 0.412 → 0.4` | 由 0.4 派生 |
| `Hover` 轨道关键帧 | `0.4 → (0.368,0.432) → (0.432,0.38) → (0.416,0.416)` | 由 0.4 派生 |
| 掉落物 `Visuals/PlayerView` 全局矩形 | `40 × 56` | — |
| 未缩放地形卡同节点全局矩形 | `100 × 140` | — |
| **两者比值** | **`0.400 / 0.400`** | **恰好 40%** |

`Idle` 与 `Hover` 的关键帧都由 `_base_visual_scale` 派生，因此不存在「待机变小但悬停弹回 100%」的基准不一致。

### 2. 靠近自动拾取与飞入缩小消失

单次 eval 内完成（同步执行期间场景树不推进帧，飞行时序完全可控）：

| 阶段 | 观测项 | 实测值 |
| --- | --- | --- |
| 生成掉落 | 房间记录数 | `1` |
| **玩家在 200px 外** | 记录数 / `IsPickupAvailable` / `_flight_target` | `1` / `true` / `false` —— 不拾取 |
| **玩家靠近到 20px** | 记录数 / `IsPickupAvailable` / `_flight_target` | `0` / `false` / 非空 —— 已入包并开始飞入 |
| 飞入中 | 是否仍在棋盘快照 | `true` —— 印证 `DetachForFlight` 不从 `_active_cards` 移除 |
| 飞行中重复扫描 2 次 | 记录数 | `0` —— 无重复入包 |
| `_process(0.15)` | `Visuals.scale` | `(0.2, 0.2)` —— 恰好半个基准 |
| `_process(0.20)` | `Visuals.scale` | `≈ (0.00001, 0.00001)` —— 缩到视觉零 |
| 飞行结束 | `_flight_target` / 快照 | 已清空 / 已移除 |

游戏日志同时出现 `Removing card: 斧头` / `Removed card: 斧头`，印证飞入完成后由 `RemoveCard` 删卡。

### 3. 判定助手（远 / 近 / 边界 / 飞行中 / 非掉落物）

| 场景 | `_should_auto_pickup` |
| --- | --- |
| 200px（远超） | `false` |
| 30px | `true` |
| 恰好 60px（等于 `AutoPickupRange`） | `true` —— `<=` 语义 |
| 60.5px | `false` |
| 飞行中（`IsPickupAvailable` 为假） | `false` |
| 未绑定堆叠的掉落视图 | `false` |
| 真实地形卡（`item_view.gd`） | `false` |

### 4. 背包满不触发拾取

先把 27 个槽位全部塞满（`CanAddItemStack` 由 `true` 变 `false`，空槽 0、可用空间 0）：

| 阶段 | 记录数 | `IsPickupAvailable` | 飞行中 | 卡牌位置 | `Visuals.scale` |
| --- | --- | --- | --- | --- | --- |
| **背包满，玩家靠近 20px** | `1`（保留） | `true` | `false` | 未移动 | `(0.4, 0.4)` 未缩小 |
| 腾出 1 格后再扫描 | `0`（已移除） | `false` | `true` | — | — |

背包满时**完全没有副作用**：不入包、不删仓库记录、不关闭命中、不飞入、不缩小；腾出空间后**无需走开再回来**即自动拾取。

### 5. 点击不再拾取，且地形卡未受影响

当时背包确认有空间（`CanAddItemStack` 为 `true`），玩家站在 400px 外：

| 操作 | 记录数 | 飞行中 | `IsPickupAvailable` | 飘字子节点数 |
| --- | --- | --- | --- | --- |
| `_on_board_card_clicked` 掉落卡 | `1`（保留） | `false` | `true` | `1 → 1`（未新增） |
| `_on_board_card_pressed` 掉落卡 | `1`（保留） | `false` | — | — |

地形卡回归：`_try_get_interaction_range` 在 600px 返回 `{ok: false, distance: 600}`、20px 返回 `{ok: true, distance: 20}`，游戏日志出现

`[WorldInteraction] 拒绝超出范围的交互：目标 浆果丛，距离 600.0 像素，当前 InteractionRange = 160.0 像素。`

——地形卡的距离门禁与飘字路径**未被掉落物的提前返回误伤**；同时 `_should_auto_pickup` 对地形卡返回 `false`。

### 6. 观察到的一个既有现象（与本次改动无关）

直接以 `project_run(mode="custom", scene="res://scenes/Main.tscn")` 启动时，`SceneTree.paused` 初始为 `true`，导致 `CanUseWorld()` 为假、自动拾取被门禁拦下。确认与本次改动无关：本次改动不触碰任何 `paused` 写入点（`paused = true` 只出现在 `settlement_manager.gd`、`pause_menu.gd`、`UILargeMap.gd`）。在 eval 中置 `tree.paused = false` 后 `CanUseWorld()` 立即为 `true`，上述全部实证即在此状态下取得。

暂停时不拾取本身就是期望行为——暂停中不应发生任何世界结算。

### `game_eval` 踩坑记录

- **不能声明函数**：`func ...` 与多行 lambda 都导致 `EVAL_COMPILE_ERROR`，脚本必须写成线性语句。
- **编译错误会冻结游戏**：之后只能拿到 `EVAL_GAME_NOT_READY`，必须 `project_manage(op="stop")` 后重新 `project_run`；`game_manage(op="resume")` 无效。
- **运行时错误同样冻结**：例如对 `Nil` 调用 `.get()`。访问可能为空的引用前必须先判空，否则一次笔误就要重启一轮。
- **不用 `get_tree()`**：eval 上下文里返回 `null`，一律用 `Engine.get_main_loop() as SceneTree`。
- **缩进必须是制表符**：混用空格会静默变成 `EVAL_COMPILE_ERROR`。

## 既有失败基线（实施前已存在，不属本次改动）

实施前全量 `test_run()`：**561 通过 / 12 失败 / 39 跳过，共 612 项断言、73 个套件**。
这 12 项失败全部先于本次改动存在，逐项已用「断言目标字符串在 `git show HEAD:<file>` 与工作区的存在性是否一致」证明：

| 套件 | 失败断言 | 证明 |
| --- | --- | --- |
| `board_controller_contract` | 缺少报错文本 `BoardController.CardViewScene 未设置` | `board_controller.gd` 未被本次改动触及；该文本在 HEAD 与工作区都不存在 |
| `world_interaction_coordinator_contract` ×3 | `fade_complete`、`_run_screen_transition` 旧 2 参数签名、`无法加载战斗背景解析器` | 三个目标字符串在 HEAD 与工作区存在性完全一致 |
| `gameflow_chain_contract` | 同一处 `_run_screen_transition` 旧 2 参数签名 | 同上；生产脚本已演进为 3 参数（`arguments: Array = []`），测试未同步 |
| `final_migration_audit_contract` ×2 | 缺少 `func _duplicate_current_background(`；campfire.tres 元数据 UID 不一致 | 前者在 HEAD 与工作区都不存在；后者的 4 项禁用字面量断言全部执行并通过，我的新增行未引入任何禁用字面量 |
| `crafting_recipe_contract`、`inventory_component_contract`、`map_ui_contract`、`reusable_gathering` ×2 | 制作脚本、装备兜底、地图面板、`items/tool/Ax.tres` | 对应生产文件均不在本次改动列表内 |

**验收口径因此定为：本次改动不得引入任何新的失败。** 上表的 12 项在改动前后完全一致。

## 验证命令速查

| 目的 | 命令 |
| --- | --- |
| 刷新脚本 | `filesystem_manage(op="scan")` |
| 单套件 | `test_run(suite="<name>")` |
| 全量套件 | `test_run()` |
| 冒烟主场景 | `project_run(mode="main")` |
| 游戏日志 | `logs_read(source="game")` |
| 编辑器错误 | `logs_read(source="editor")` |
| 运行时断言 | `game_eval(code="...")` |
| 停止游戏 | `project_manage(op="stop")` |

## 审查门禁

| 门禁 | 位置 | 通过条件 |
| --- | --- | --- |
| 门禁 1 | 步骤 3 之后 | `world_interaction_coordinator_contract` 全绿（锁定字面量未漂移） |
| 门禁 2 | 步骤 5 之后 | 新套件全绿 + 全量套件 0 失败 |
| 门禁 3 | 步骤 7.8 之后 | `game_eval` 四条运行时断言全部成立 |
| 门禁 4 | 步骤 7.11 之后 | `git status` 只含本任务改动 |

## 回滚点

| 回滚点 | 位置 | 回滚动作 |
| --- | --- | --- |
| R1 | 步骤 1-2 之后 | `git checkout -- scripts/loot_scripts/loot_view.gd scenes/Loot/Loot.tscn` |
| R2 | 步骤 3 之后 | `git checkout -- core/gameflow/world_interaction_coordinator.gd`（表现层改动可保留，二者独立） |
| R3 | 步骤 4-6 之后 | `git checkout -- tests/ docs/`，逻辑改动仍可用 |

改动无数据迁移、无存档格式变化、无场景节点增删，回滚只需还原文件。

## 风险与对策

| 风险 | 触发条件 | 对策 |
| --- | --- | --- |
| 锁定字面量漂移导致契约测试红 | 步骤 3 手滑改了 `_try_get_interaction_range` 或其调用行 | 步骤 3.10 逐字复核 + 门禁 1 |
| 缩放基准不一致 | `_configure_motion()` 在 `_base_visual_scale` 赋值**之前**调用 | 步骤 1.4 检查调用顺序；AC-1 目视确认悬停不弹回 100% |
| 二次拾取 | `IsPickupAvailable` 漏判 `_flight_target` | 步骤 5.3 断言 + 7.8 运行时断言 |
| 点击掉落物仍弹「距离不够！」 | `_is_loot_card` 放在了距离判定**之后** | 步骤 3.7 / 3.8 明确要求放在之前；7.8 点击断言 |
| 编辑器重写场景产生无关 diff | 手改 `.tscn` 后编辑器重新序列化 | 优先用编辑器 MCP 改；7.11 复核 `git status` |
| 背包满时每帧调用入包 | 轮询设计使然 | 已确认 `CanAddItemStack` 只读（`inventory_component.gd:322`）；不做节流以免破坏 AC-10 |
| 新套件 `test_run` 报未注册 | 漏写 `tests/` 顶层壳文件 | 步骤 5.1 先建壳文件；补壳后必须重新 `filesystem_manage(op="scan")`（重载插件不刷新缓存） |
| 否定断言被注释内容判红 | 套件里写了「不要再用旧入口」并 `assert_false(contains(旧名))` | 步骤 5.5 只做正向存在性断言；否定语义交给 `game_eval` |
| 编辑器里伪造实例导致假通过 | 试图在套件里实例化非 `@tool` 脚本 | 步骤 5.6 明确禁止；运行期行为只在 `game_eval` 里验证 |
| `game_eval` 冻结游戏 | eval 里出错或用 `get_tree()` | 按「`game_eval` 写法约束」执行；冻结后必须 `project_manage(op="stop")` 重开 |
