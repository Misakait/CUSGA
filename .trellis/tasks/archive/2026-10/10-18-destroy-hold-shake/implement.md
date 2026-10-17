# 执行计划：长按破坏时的目标抖动反馈

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
- [x] `_init(sprite: Sprite2D, amplitude: float, step_seconds: float)`；`sprite` 为空时所有方法安全空转。
- [x] `Start()`：记录 `sprite.position` 为静止位置 → `create_tween().set_loops()` →
      `tween_callback(_apply_random_offset)` + `tween_interval(step_seconds)`。已在抖动时直接返回。
- [x] `Stop()`：杀 `Tween` → 精确复位 `sprite.position = _rest_position` → 清空引用。未抖动时也保证复位。
- [x] `IsRunning() -> bool`。
- [x] `static SyncAnchor(icon: Sprite2D, anchor: Node2D) -> void`：写
      `anchor.position = icon.position + icon.scale * icon.get_rect().end`；
      `icon` 或 `anchor` 为空时直接返回。
- [x] `filesystem_manage(op="scan")` 让新 `class_name` 进全局类表。

## 阶段 2：视图接线

### 2.1 地形卡 `scripts/item_scripts/item_view.gd` + `scenes/ItemTerrian/Item.tscn`

- [x] `Item.tscn` 在 `Visuals/PlayerView` 下新增 `Marker2D` 名为 `ProgressAnchor`（不参与抖动）。
- [x] `item_view.gd`：`@onready var _progress_anchor: Marker2D = $Visuals/PlayerView/ProgressAnchor`。
- [x] `_ready()`：构造 `DestroyShake.new(_icon, 幅度, 步进)`（幅度/步进取 `MotionConfig`，缺失用默认常量）。
- [x] `GetProgressAnchor()` 返回 `_progress_anchor`；更新 `##` 注释为「不随破坏抖动移动的进度锚点」。
- [x] `RefreshView()` 设置 `_icon.texture` 之后调用 `DestroyShake.SyncAnchor(_icon, _progress_anchor)`。
- [x] 新增公开幂等入口：
      `## 切换「正在被破坏」的抖动表现。` / `func SetDestroying(destroying: bool) -> void`，
      委托 `_shake.Start()` / `_shake.Stop()`；`_shake == null` 时安全返回。
- [x] `_exit_tree()` 调用 `_shake.Stop()`。

### 2.2 建筑 `core/building/building_view.gd` + `scenes/building/building_view.tscn`

- [x] `building_view.tscn` 新增 `Marker2D` 名为 `ProgressAnchor`。
- [x] `building_view.gd`：新增 `@export var MotionConfig: Resource = preload("res://resources/interaction/item_motion_config.tres")`。
- [x] `Configure()` 设置 `icon.texture` 与 `icon.scale` 之后调用 `DestroyShake.SyncAnchor(icon, _progress_anchor)`。
- [x] 新增 `SetDestroying(destroying: bool) -> void`（同上，抖 `Icon`）。
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
- [x] `game_eval` 采样：真实按下并保持一张地形卡，跨帧比较 `Icon.position`、锚点屏幕位置、`tree.paused`。
- [x] `game_eval` 验证建筑拆除路径（走真实 `_begin_demolition`）。
- [x] `game_eval` 验证地图方向长按不产生抖动（R5）。
- [x] `project_manage(op="stop")`；**未关闭 Godot 编辑器**。
- [x] `git status` 确认编辑器没有改写无关文件（发现并还原了一次对 `login_menu.tscn` 的无关改写）。

## 阶段 6：质量检查与收尾

- [x] 载入 `trellis-check`，跑全量 `test_run` 并与「改动前失败清单」对比，确认没有新增失败。
- [x] `trellis-update-spec`：把「圆环锚点必须落在不参与抖动的节点上」这条契约写进
      `.trellis/spec/backend/gameplay-system-patterns.md`；把编辑器测试的两条新坑写进
      `.trellis/spec/backend/testing-guidelines.md`（`tree_paused` 冻结 `Tween` 的坑已存在，未重复添加）。
- [x] 更新 `docs/游戏机制与玩法内容.md` 关于圆环锚点与地形卡动画的表述（第 23、25、542 行三处）。
- [ ] 提交：`<work commit>` → `chore(task): archive 10-18-destroy-hold-shake` → `chore: record journal`。
- [ ] 归档：`task.py archive 10-18-destroy-hold-shake --skip-branch-validation`（本仓库 trunk-based，
      `branch == base_branch == "main"`，必须加该开关）。

## 验证证据

### 新增契约测试

`test_run(suite="destroy_hold_shake", verbose=true)` → **6/6 通过，62 项断言**：

| 用例 | 断言数 | 覆盖 |
|---|---|---|
| `test_source_contracts` | 17 | 源码与场景文本形状（下述 1~6、13） |
| `test_shake_jitters_and_restores_exactly` | 21 | 抖动发生、偏移不超幅度、精确复位 |
| `test_anchor_stays_still_while_icon_shakes` | 17 | 锚点逐帧静止 + 图标确实在抖 |
| `test_anchor_reproduces_icon_rest_bottom_right` | 2 | 锚点复刻静止右下角（屏幕 + 本地） |
| `test_shake_lifecycle_is_idempotent` | 3 | 重复启停幂等、未抖动时 Stop 不覆盖坐标 |
| `test_destroy_shake_ignores_out_of_tree_sprite` | 2 | 不在场景树时不建 Tween、不改坐标 |

源码形状（1~6）：

1. `item_view.gd` 含 `func SetDestroying(` 且 `GetProgressAnchor()` 返回锚点而非 `_icon`。
2. `building_view.gd` 含 `func SetDestroying(` 与 `MotionConfig` 导出。
3. `Item.tscn` 含 `[node name="ProgressAnchor" type="Marker2D" parent="Visuals/PlayerView"`，
   `building_view.tscn` 含 `parent="."`。
4. `world_interaction_coordinator.gd` 含 `card.call("SetDestroying", true)` 与
   `released_card.call("SetDestroying", false)`。
5. `building_controller.gd` 含 `view.call("SetDestroying", true)`、
   `cancelled_view.call("SetDestroying", false)`、`get_node_or_null("ProgressAnchor")`。
6. `item_motion_config.gd` 含 `DestroyShakeAmplitude` 与 `DestroyShakeStepSeconds`。
7. **额外**：共享长按端口 `world_hold_interaction_controller.gd` 的
   `begin_timed_hold(hold_owner, duration_seconds, on_completed, progress_target)` 签名逐字未变。

运行时行为（7~13）：

8. 抖动把图标推离静止位置，偏移始终 ≤ 配置幅度；`Stop()` 后 `Icon.position` **精确等于**静止坐标。
9. 抖动期间锚点 `get_screen_transform().origin` 逐帧不变（`is_equal_approx`，16 步）——**R3 核心断言**。
10. 抖动期间 `Icon.get_screen_transform().origin` 确实在变（排除「抖动没生效」的假通过）。
11. 锚点屏幕位置 == `icon.get_screen_transform() * icon.get_rect().end`（指示器旧公式），
    且锚点本地坐标 == `icon.position + icon.scale * icon.get_rect().end`。
12. `SetDestroying(true)` 连调两次、`SetDestroying(false)` 连调两次均幂等；未抖动时 Stop 不写坐标。
13. 不在场景树中的 `Sprite2D` 不创建 Tween，也不被 Stop 改写坐标。

> **相对计划的一处偏差**：计划第 7~13 条写的是「`Item.tscn` 实例化后」断言。实测在编辑器测试运行器里
> `Item.tscn` 的根脚本 `item_view.gd` 不是 `@tool`，实例化得到的是 placeholder instance，
> `SetDestroying` 不可调用；`building_view.tscn` 还被 `building_controller.gd` 的 `preload` 缓存，
> 场景改动在同一进程内不可见。因此套件改为用**等价的引擎节点夹具**（同父节点下的
> `Sprite2D` + `Marker2D`，坐标与缩放复刻生产值）直接驱动生产组件 `DestroyShake`，
> 真实场景的实例化行为全部移到运行期 `game_eval` 验证（见下）。场景结构则用文件文本断言，规避缓存。

### 运行期验证（`scenes/Main.tscn` + `game_eval`）

- 真实地形卡（`resources/map/terrain/wood_terrain.tres` 的浆果丛条目）：
  `_on_board_card_pressed(card)` → `IsRunning() == true`、`ring.is_hold_progress_visible == true`、
  `ring._hold_progress_target == ProgressAnchor`；`_on_board_card_released(card)` → `IsRunning() == false`、
  圆环隐藏、`Icon.position` 精确复位。
- **锚点解耦（决定性证据）**：在一次 eval 内连续 200 次调用 `_apply_random_offset`，
  用**精确 `!=`**（非近似）比较锚点屏幕坐标 —— `anchor_screen_bit_identical_over_200_steps == true`，
  同时 `icon_moved_steps == 200`。另一次单帧判定把 `Icon.position` 强行位移 `400px`，
  锚点屏幕坐标仍逐位不变（`anchor_decoupled_from_icon_position == true`）。
- **Tween 持续步进**：解暂停后 1.2 秒真实时间窗内图标取了 **28** 个不同位置
  （步进 `0.045s`，理论约 26 次），`max_shift == 2.992 ≤ amplitude 3.0`。
- **不影响实体**：抖动期间根节点 `global_position`、`rotation`、`Interaction` 全局位置全部不变。
- **建筑拆除**：真实 `building_view.tscn` + `Configure(building_data.gd 实例)` +
  真实 `_begin_demolition(record)` → `IsRunning() == true`、`ring._hold_progress_target == ProgressAnchor`；
  `_cancel_demolition()` → `IsRunning() == false`、图标精确复位、`_demolition_id == -1`、圆环清除。
- **R5（地图方向长按不抖）**：`BeginWorldHoldForMap(owner, 10, card)` 期间
  `card._shake.IsRunning() == false`，而 `ring._hold_progress_target == card` —— 证明共用同一圆环端口
  但完全不触发抖动。
- 场景冒烟：`project_run(mode="main")`（`login_menu.tscn`）与 `mode="custom"`（`scenes/Main.tscn`）
  均无 `SCRIPT ERROR` / `Parse Error` / `Failed to load script`；`DestroyShake` 已进全局类表。
- 两次踩坑导致的游戏 break（`String` 构造错误、`Camera2D` 属性名写错）均为 eval 脚本自身问题，
  不是生产代码问题，已按规范 `project_manage(op="stop")` 后重启复测。

### 既有套件回归（改动后）

全量 `test_run()` → **580 通过 / 12 失败 / 39 跳过 / 631 总 / 75 套件**。

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
