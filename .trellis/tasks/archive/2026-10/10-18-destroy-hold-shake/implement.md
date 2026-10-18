# 执行计划：长按破坏时的目标抖动反馈

## 修正记录（第二轮）

第一轮按「只抖贴图节点」实现并已提交/归档（`86f59e5`）。用户验收时指出要抖的是**整张卡牌**，
不是卡里的物品。第二轮据此修正（`8571b54`），下文已改为现行方案：

- 地形卡抖动目标 `Icon` → `Visuals`；建筑仍抖 `Icon`（建筑的可见内容就只有它）。
- `Item.tscn` 的 `ProgressAnchor` 从 `Visuals/PlayerView` 下移到 `Item` 根节点（被抖子树之外）。
- `DestroyShake` 的 `_init(sprite: Sprite2D)` → `_init(target: Node2D)`；
  `static SyncAnchor` → 实例方法 `SyncAnchor`（跨父节点全局换算 + 抵消运行中的抖动）。
- 测试夹具改为跨父节点层级，并新增 `test_anchor_sync_during_shake_does_not_drift`。

## 阶段 0：编码前准备

- [x] 载入 `trellis-before-dev`，读取 `.trellis/spec/backend/gameplay-system-patterns.md`、
      `.trellis/spec/frontend/directory-structure.md`、`.trellis/spec/backend/testing-guidelines.md`。
- [x] 确认 MCP 会话：`session_manage(op="list")` → `session_activate(session_id="cusga@c24ae7011184e281")`。
- [x] `git status` 确认工作区干净，只保留本任务改动。
- [x] 复核调用点现状：确认 `GetProgressAnchor`、`begin_hold`、`begin_timed_hold`、`_clear_active_terrain_hold`、
      `_cancel_demolition` 的全部引用（含 `.tscn` 序列化与测试内的逐行断言）。
      （本机无 `rg`，改用 grep 工具等价检索。）

## 阶段 1：抖动组件（`scripts/anim/DestroyShake.gd`，新增）

- [x] `class_name DestroyShake extends RefCounted`，`##` 文档注释说明参数与返回值。
- [x] `_init(target: Node2D, amplitude: float, step_seconds: float)`；`target` 为空时所有方法安全空转。
      （第二轮由 `sprite: Sprite2D` 改为 `target: Node2D`：抖的是「整个可见节点」，
      地形卡传 `Visuals`、建筑传 `Icon`，用 `Sprite2D` 命名会继续暗示「抖的是贴图/图标」。）
- [x] `Start()`：记录 `target.position` 为静止位置 → `create_tween().set_loops()` →
      `tween_callback(_apply_random_offset)` + `tween_interval(step_seconds)`。已在抖动时直接返回。
- [x] `Stop()`：杀 `Tween` → 精确复位 `target.position = _rest_position` → 清空引用。未抖动时也保证复位。
- [x] `IsRunning() -> bool`。
- [x] `SyncAnchor(icon: Sprite2D, anchor: Node2D) -> void`（**实例方法**）：
      `point = icon.get_global_transform() * icon.get_rect().end`，先扣掉运行中的抖动偏移，
      再 `anchor.position = anchor.get_parent().to_local(point)`；参数为空或不在场景树时直接返回。
- [x] `filesystem_manage(op="scan")` 让新 `class_name` 进全局类表。

## 阶段 2：视图接线

### 2.1 地形卡 `scripts/item_scripts/item_view.gd` + `scenes/ItemTerrian/Item.tscn`

- [x] `Item.tscn` 新增 `Marker2D` 名为 `ProgressAnchor`；第二轮从 `Visuals/PlayerView` 下移到
      `Item` 根节点下（被抖子树之外），序列化坐标按实测的无纹理静止值取 `Vector2(2, 15)`。
- [x] `item_view.gd`：`@onready var _progress_anchor: Marker2D = $ProgressAnchor`。
- [x] `_ready()`：构造 `DestroyShake.new(_visuals, 幅度, 步进)`（幅度/步进取 `MotionConfig`，缺失用默认常量）。
      第二轮由 `_icon` 改为 `_visuals`，这是本次修正的核心一行。
- [x] `GetProgressAnchor()` 返回 `_progress_anchor`；更新 `##` 注释为「不随破坏抖动移动的进度锚点」。
- [x] `RefreshView()` 设置 `_icon.texture` 之后调用 `_shake.SyncAnchor(_icon, _progress_anchor)`
      （第二轮由静态调用改为实例调用，并加 `_shake != null` 守卫）。
- [x] 新增公开幂等入口：
      `## 切换「正在被破坏」的抖动表现。` / `func SetDestroying(destroying: bool) -> void`，
      委托 `_shake.Start()` / `_shake.Stop()`；`_shake == null` 时安全返回。
- [x] `_exit_tree()` 调用 `_shake.Stop()`。

### 2.2 建筑 `core/building/building_view.gd` + `scenes/building/building_view.tscn`

- [x] `building_view.tscn` 新增 `Marker2D` 名为 `ProgressAnchor`。
- [x] `building_view.gd`：新增 `@export var MotionConfig: Resource = preload("res://resources/interaction/item_motion_config.tres")`。
- [x] `Configure()` 设置 `icon.texture` 与 `icon.scale` 之后调用 `_shake.SyncAnchor(icon, _progress_anchor)`。
- [x] 新增 `SetDestroying(destroying: bool) -> void`（同上，抖 `Icon`——建筑的可见内容就只有它，
      没有卡框这一层，所以「整卡抖动」的修正不改变建筑的目标节点）。
- [x] `_exit_tree()` 调用 `_shake.Stop()`。
- [x] 补充 `_ready()`：解析 `Icon` / `ProgressAnchor` 并按 `MotionConfig` 构造抖动
      （原计划未列出，但 `building_view.gd` 原本没有 `_ready()`，不补则组件与锚点都拿不到）。

### 2.3 参数 `resources/interaction/item_motion_config.gd`

- [x] 新增 `DestroyShakeAmplitude: float = 3.0`、`DestroyShakeStepSeconds: float = 0.045`，带 `@export_range` 与 `##` 注释。
- [x] 确认 `resources/interaction/item_motion_config.tres` 无需手改（缺字段时脚本默认值生效）；
      编辑器没有把新字段写回 `.tres`（`git status` 中该文件未被修改）。

## 阶段 3：调用点接线

### 3.1 地形卡 `core/gameflow/world_interaction_coordinator.gd`

- [x] `_on_board_card_pressed()`：在 `_active_terrain_hold_card = card` 之后、`begin_hold` **之前**
      调用 `card.call("SetDestroying", true)`（必须在 `begin_hold` 前，覆盖零时长即时完成路径）。
- [x] `_clear_active_terrain_hold()`：在把 `_active_terrain_hold_card` 置空前先取局部引用，
      再 `card.call("SetDestroying", false)`（该函数是释放/取消/完成/移动打断的唯一汇合点）。
- [x] 保持既有逐行断言的字面量不变：`card.call("SetInteractionDisabled", ...)`、`"begin_hold",`、
      `_hold_interaction_controller.call("cancel_active_hold")` 等。

### 3.2 建筑 `core/building/building_controller.gd`

- [x] `_begin_demolition()`：`_demolition_id = int(record["id"])` 之后、`begin_timed_hold` **之前**
      调用 `view.call("SetDestroying", true)`。
- [x] `_cancel_demolition()`：在 `_demolition_id = -1` **之前**取 `_views.get(_demolition_id)` 并
      `view.call("SetDestroying", false)`，再走原有 `cancel_hold_for`。
- [x] `_begin_demolition()` 里 `progress_target` 由 `view.get_node("Icon")` 改为锚点；
      实现为 `view.get_node_or_null("ProgressAnchor")`，缺失时回退 `Icon`
      （`building_data.gd` 允许 `WorldScene` 提供自定义表现场景，旧场景可能没有锚点）。

## 阶段 4：测试

- [x] 新增 `tests/godot/test_destroy_hold_shake.gd`，`suite_name()` 返回本套件名。
- [x] 新增 2 行壳 `tests/test_destroy_hold_shake.gd`（`@tool` + `extends "res://tests/godot/test_destroy_hold_shake.gd"`）。
- [x] `filesystem_manage(op="scan")` 后 `test_run(suite="destroy_hold_shake")`。
- [x] 断言内容见「验证证据 / 新增契约测试」。

## 阶段 5：运行时验证

- [x] `project_run(mode="main")`，`logs_read(source="game")` 确认无 `SCRIPT ERROR` / `Parse Error`。
- [x] `game_eval` 采样：真实按下并保持一张地形卡，跨帧比较被抖节点位置、锚点位置、`tree.paused`。
      第二轮改用**世界坐标**判定锚点恒定：世界坐标不含相机变换，可避开玩家移动导致相机跟随、
      屏幕坐标整体漂移的混淆（第一轮曾把 16px 的相机位移误读成锚点漂移）。
- [x] `game_eval` 验证建筑拆除路径（真实 `building_view.tscn` + `Configure(building_data.gd 实例)`）。
- [x] `game_eval` 验证地图方向长按不产生抖动（R5）。
- [x] `project_manage(op="stop")`；**未关闭 Godot 编辑器**。
- [x] `git status` 确认编辑器没有改写无关文件（第一轮发现并还原了一次对 `login_menu.tscn` 的无关改写；
      第二轮复查工作树只剩本任务改动的 7 个文件）。

## 阶段 6：质量检查与收尾

- [x] 载入 `trellis-check`，跑全量 `test_run` 并与「改动前失败清单」对比，确认没有新增失败（两轮各做一次）。
- [x] `trellis-update-spec`：把「圆环锚点必须落在**被抖子树之外**」这条契约写进
      `.trellis/spec/backend/gameplay-system-patterns.md`；把编辑器测试的两条新坑写进
      `.trellis/spec/backend/testing-guidelines.md`（`tree_paused` 冻结 `Tween` 的坑已存在，未重复添加）。
      第二轮把该 spec 里「只抖贴图节点 / 锚点与图标同级」的错误表述改成现行方案，
      并补记「`Visuals/PlayerView` 是 `Control`，`as Node2D` 会静默得到 `null`」这个坑。
- [x] 更新 `docs/游戏机制与玩法内容.md`（第一轮第 23、25、542 行三处；第二轮按「抖整张卡牌」重写这三处）。
- [x] 提交：`86f59e5`（第一轮特性）→ `ca095ac`（归档）→ `b1799b9`（日志）→
      `8571b54`（第二轮修正）→ `33d94b0`（日志）。
- [x] 归档：`task.py archive 10-18-destroy-hold-shake --skip-branch-validation`（本仓库 trunk-based，
      `branch == base_branch == "main"`，必须加该开关）。

## 验证证据

### 新增契约测试

`test_run(suite="destroy_hold_shake", verbose=true)` → **7/7 通过，77 项断言**：

| 用例 | 断言数 | 覆盖 |
|---|---|---|
| `test_source_contracts` | 20 | 源码与场景文本形状（下述 1~7） |
| `test_card_shakes_as_a_whole` | 23 | 整卡抖动：卡牌节点 + 卡框 + 卡内图标三者全动、偏移不超幅度、精确复位 |
| `test_anchor_stays_still_while_card_shakes` | 17 | 锚点逐帧静止（精确相等）+ 卡牌确实在抖 |
| `test_anchor_reproduces_icon_rest_bottom_right` | 3 | 锚点复刻静止右下角（屏幕 + 跨父节点本地）+ 跨父节点前提 |
| `test_anchor_sync_during_shake_does_not_drift` | 9 | 抖动期间重算锚点不把当前偏移烘进锚点 |
| `test_shake_lifecycle_is_idempotent` | 3 | 重复启停幂等、未抖动时 Stop 不覆盖坐标 |
| `test_destroy_shake_ignores_out_of_tree_target` | 2 | 不在场景树时不建 Tween、不改坐标 |

源码形状（1~7）：

1. `item_view.gd` 含 `func SetDestroying(` 且 `GetProgressAnchor()` 返回锚点而非 `_icon`。
2. `item_view.gd` 的抖动目标必须是 `_visuals` 而不是 `_icon`——用正则
   `_shake = DestroyShake\.new\(\s*_visuals,` 容忍缩进差异。这是第二轮修正的核心断言。
3. `item_view.gd` 含 `@onready var _progress_anchor: Marker2D = $ProgressAnchor`（锚点挂根节点）。
4. `Item.tscn` 含 `[node name="ProgressAnchor" type="Marker2D" parent="."`，且**不含**
   `name="ProgressAnchor" ... parent="Visuals`；另断言 `[node name="Visuals" type="Sprite2D" parent="."`
   存在。`building_view.tscn` 含 `parent="."`。
5. `building_view.gd` 含 `func SetDestroying(` 与 `MotionConfig` 导出。
6. `world_interaction_coordinator.gd` 含 `card.call("SetDestroying", true)` 与
   `released_card.call("SetDestroying", false)`。
7. `building_controller.gd` 含 `view.call("SetDestroying", true)`、
   `cancelled_view.call("SetDestroying", false)`、`get_node_or_null("ProgressAnchor")`。
8. `item_motion_config.gd` 含 `DestroyShakeAmplitude` 与 `DestroyShakeStepSeconds`。
9. **额外**：共享长按端口 `world_hold_interaction_controller.gd` 的
   `begin_timed_hold(hold_owner, duration_seconds, on_completed, progress_target)` 签名逐字未变。

运行时行为：

- 抖动把**卡牌节点**推离静止位置，偏移始终 ≤ 配置幅度；`Stop()` 后 `Visuals.position` **精确等于**静止坐标。
- 抖动期间**卡牌节点、卡框、卡内图标三者的屏幕位置都在变**——三条断言一起才证明「整张卡牌在抖」，
  而不是只有卡里的物品在抖。
- 抖动期间锚点 `get_screen_transform().origin` 逐帧**精确相等**（用 `==` 而不是 `is_equal_approx`，16 步）——**R3 核心断言**。
- 锚点屏幕位置 == `icon.get_screen_transform() * icon.get_rect().end`（指示器旧公式），
  且锚点本地坐标 == `root.to_local(icon.get_global_transform() * icon.get_rect().end)`（跨父节点换算）。
- 断言锚点与图标**不在同一父节点**下，否则「跨父节点换算正确」会退化成同父节点的巧合。
- 抖动期间反复调用 `SyncAnchor`（模拟长按中刷新视图）不改变锚点屏幕位置（8 步）。
- `SetDestroying(true)` 连调两次、`SetDestroying(false)` 连调两次均幂等；未抖动时 Stop 不写坐标。
- 不在场景树中的节点不创建 Tween，也不被 Stop 改写坐标。

> **相对计划的一处偏差**：计划原文写的是「`Item.tscn` 实例化后」断言。实测在编辑器测试运行器里
> `Item.tscn` 的根脚本 `item_view.gd` 不是 `@tool`，实例化得到的是 placeholder instance，
> `SetDestroying` 不可调用；`building_view.tscn` 还被 `building_controller.gd` 的 `preload` 缓存，
> 场景改动在同一进程内不可见。因此套件改为用**等价层级的最小夹具**直接驱动生产组件 `DestroyShake`：
> 根节点下是被抖的卡牌节点，卡牌节点下是卡框，卡框下是图标（坐标与缩放复刻生产值），
> 锚点则挂在**根节点**下、位于被抖子树之外——这正是圆环不随整卡抖动的前提。
> 卡框用 `Node2D` 而不是生产里的 `Button`：Control 的位置由锚点布局推导，会引入与被测换算无关的
> 布局依赖。真实场景的实例化行为全部移到运行期 `game_eval` 验证（见下）。
> 场景结构则用文件文本断言，规避缓存。

### 运行期验证（`scenes/Main.tscn` + `game_eval`）

> 第一轮那些「图标位移 / 锚点屏幕坐标」的采样是针对**已作废的只抖图标方案**，结论不再适用；
> 下面只保留第二轮（现行方案）的证据。第二轮改用**世界坐标**判定锚点恒定：世界坐标不含相机变换，
> 可以避开玩家移动导致相机跟随、屏幕坐标整体漂移的混淆。

- **真实地形卡整卡抖动**（`resources/map/terrain/wood_terrain.tres` 的浆果丛条目，`InitializeTerrain`）：
  一次 eval 内连续 200 次 `_apply_random_offset` → `target_is_visuals == true`、
  `anchor_under_visuals == false`、`card_moved == true`、`frame_moved == true`（卡框在动）、
  `icon_moved == true`（卡内图标在动）——三者同时为真才说明抖的是整张卡牌；
  `max_shift == 2.4179 ≤ amplitude 3.0`；`root_unmoved == true`（根节点没被碰）。
  真实纹理下 `icon_rect == Rect2(-16, -16, 32, 32)`、`anchor_pos == (32, 45)`。
- **锚点解耦（决定性证据）**：同样 200 步内用**精确 `!=`**（非近似）比较锚点**世界**坐标 →
  `anchor_bit_identical_over_200_steps == true`；`anchor_matches_legacy_formula == true`
  （锚点屏幕位置仍等于旧的「锚定图标」公式 `icon.get_screen_transform() * icon.get_rect().end`）；
  `anchor_still_ok_after_stop == true`；`restored_exactly == true`。
- **真实长按链路**：走真实 `_on_board_card_pressed(card)` / `_on_board_card_released(card)` →
  `running_after_press == true`、`ring_visible == true`、`ring_target_is_anchor == true`；
  保持期间 40 帧（约 0.8 秒）采样 `anchor_global_bit_identical == true` 且 `card_moved_during_hold == true`；
  释放后 `running_after_release == false`、`ring_cleared == true`、`restored_exactly == true`。
- **建筑拆除**：真实 `building_view.tscn` + `Configure(building_data.gd 实例, CardIcon=卡牌模板, Footprint=96×96)` →
  `target_is_icon == true`（建筑的可见内容就只有 `Icon`，修正不改变其目标节点）、
  `icon_rect == Rect2(-350, -70, 700, 140)`、`icon_scale == 0.1371`、
  `anchor_pos == (48, 9.6)`（精确等于图标静止右下角）、`anchor_matches_legacy_formula == true`、
  200 步 `anchor_bit_identical_over_200_steps == true` 且 `icon_moved == true`、
  `max_shift == 2.9976 ≤ 3.0`、`restored_exactly == true`、`anchor_still_ok_after_stop == true`。
- **R5（地图方向长按不抖）**：`BeginWorldHoldForMap(card, 10, marker)` 期间
  `map_hold_shakes_card == false`、`visuals_unmoved == true`（卡牌视觉纹丝不动），
  而 `map_ring_target_is_marker == true` —— 证明共用同一圆环端口但完全不触发抖动。
- **锚点静止坐标复核**：场景序列化的 `ProgressAnchor.position` 已按 `_ready()` 实测值改为
  `Vector2(2, 15)`。注意无纹理 `Sprite2D.get_rect()` 返回 `Rect2(0, 0, 1, 1)`（**不是**居中矩形），
  且 `PlayerView` 在 `Visuals` 内的真实原点是 `(-50, -70)`（不是 `(-50.5, -70.5)`）——
  第一轮按推测写下的 `(0.5, 13.5)` 就是这样算错的。
- 场景冒烟：`project_run(mode="custom", scene="res://scenes/Main.tscn")` 运行 4 次（含踩坑重启），
  游戏日志只有 info（`[RoomBoardPresenter] Enter room ...`），无 `SCRIPT ERROR` / `Parse Error`；
  编辑器日志游标 201 之后零新增。`DestroyShake` 已进全局类表。
- 三次踩坑导致的游戏 break 均为 **eval 脚本自身**问题，不是生产代码问题，已按规范
  `project_manage(op="stop")` 后重启复测：
  1. `campfire_rest.tres` 其实是交互策略资源（`rest_building_interaction.gd`），不是建筑数据，
     `Configure` 取 `Footprint` 得到 `null`；
  2. `PlayerView` 是 `Button`（`Control`），`as Node2D` 静默得到 `null`；
  3. `Visuals` 是子节点，要用 `get_node("Visuals")` 而不是 `get("Visuals")`。

### 既有套件回归（改动后）

全量 `test_run()` → **580 通过 / 12 失败 / 40 跳过 / 632 总 / 75 套件**。

第二轮修正后再跑一次，结果是**同一组 12 个失败、同一组通过数**，零新增失败；
总数 631 → 632、通过数不变，是因为本轮给 `destroy_hold_shake` 增加了 1 个用例
（`test_anchor_sync_during_shake_does_not_drift`），而**跳过数 39 → 40 属环境差异、不是回归**：
`test_vital_component_contract.gd:112` 有 `skip("当前没有打开的场景，无法验证 _ready 补满行为。")`，
第一轮全量时编辑器里开着 `login_menu.tscn`（`edited_scene` 非空），第二轮是 `<none>`，
该用例于是走 skip 分支。若需要与第一轮严格同口径对比，先在编辑器里打开
`res://scenes/main_menu_scenes/login_menu.tscn` 再跑全量。

`destroy_hold_shake` 在全量运行中同样全绿。计划要求「必须保持全绿」的
`dev_settings_contract`、`board_card_view_contract`、`shared_gathering_effects` 均通过。

12 个失败逐条核对，**全部与本改动无关**（失败消息指向的符号/文件均不在本 diff 中）：

| 套件::用例 | 失败指向 | 归因 |
|---|---|---|
| `board_controller_contract::test_shared_log_and_error_texts` | `BoardController.CardViewScene` | 既有 |
| `reusable_gathering::test_production_plain_item_assets_use_gdscript_item_data` | `items/tool/Ax.tres` | 既有 |
| `reusable_gathering::test_production_tool_assets_use_gdscript` | `items/tool/Ax.tres` | 既有 |
| `world_interaction_coordinator_contract::test_cross_language_boundaries` | `fade_complete` 信号 | 既有 |
| `world_interaction_coordinator_contract::test_production_script_shape` | 缺 `_run_screen_transition` | 既有 |
| `world_interaction_coordinator_contract::test_shared_log_and_error_texts` | 缺「无法加载战斗背景解析器：」 | 既有 |
| `gameflow_chain_contract::test_chain_boundaries` | 缺 `_run_screen_transition` | 既有 |
| `crafting_recipe_contract::test_production_scenes_avoid_csharp_crafting_scripts` | `player.tscn` 缺 `crafting_recipe.gd` | 既有 |
| `final_migration_audit_contract::test_custom_type_script_metadata_matches_attached_script` | `items/environment/campfire.tres` 元数据 | 既有 |
| `final_migration_audit_contract::test_inlined_host_exposes_named_replacements` | 缺 `_duplicate_current_background` | 既有 |
| `inventory_component_contract::test_equipment_component_production_tool_contract` | 斧头槽位兜底规则 | 既有 |
| `map_ui_contract::test_map_interaction_and_option_panel_contracts` | `open_map` 键位 / `UILargeMap.gd` | 既有 |

加载错误 1 条，同样既有：`tests/godot/test_item_room_content.gd` 无法实例化。根因已定位——
该套件从旧 `SceneTree` 风格迁移到 `McpTestSuite`（`extends RefCounted`）时漏改了第 42、47 行的
`get_tree()`，`RefCounted` 没有该方法，因此解析失败。**本任务未修复它**（超出范围），
但已确认它与本改动无关：本任务没有新增任何 `AnimationPlayer` 轨道，
该套件守护的「Idle/Hover 只驱动 `Visuals:` 子树」契约在 diff 层面依然成立。

## 回滚点

| 回滚点 | 内容 | 恢复方式 |
|---|---|---|
| R-A | 阶段 1 完成后 | 删除 `scripts/anim/DestroyShake.gd` 与其 `.uid` |
| R-B | 阶段 2 完成后 | 还原两个场景与两个视图脚本（`git checkout`） |
| R-C | 阶段 3 完成后 | 还原两个调用点；锚点返回值改回 `_icon`、建筑锚点改回 `view.get_node("Icon")` |
| R-D | 全部完成后 | `git revert` 本任务提交 |
| R-E | 第二轮修正后 | `git revert 8571b54`；若只想回退「整卡抖动」这一项，把 `_visuals` 改回 `_icon`、并把 `ProgressAnchor` 移回 `Visuals/PlayerView` 即可（其余改动对旧方案同样成立） |

## 验证命令速查

```bash
# 刷新脚本与全局类表
filesystem_manage(op="scan")
# 新增套件（先确认 2 行壳存在）
test_run(suite="destroy_hold_shake", verbose=true)
# 全量回归
test_run()
# 主场景冒烟
project_run(mode="main")
logs_read(source="game")
game_eval(code="...")           # 采样抖动与锚点
project_manage(op="stop")       # 只停游戏，不关编辑器
git status
```
