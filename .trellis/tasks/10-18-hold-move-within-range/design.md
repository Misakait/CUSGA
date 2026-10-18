# 设计：长按交互在范围内移动不打断

## 1. 边界与不变量

- **两条长按统一的是「移动不是取消条件」**，不是取消清单完全相同：
  - 地形卡：键盘移动不取消；离开 `InteractionRange` 才取消。
  - 建筑：玩家**自己没动鼠标**时的光标漂移（相机跟随）不取消；离开该建筑 `InteractionRadius` 才取消。
    玩家**主动移动鼠标**时，「移开鼠标」与「切换目标」依旧取消（R6，用户决策）。
- 取消门槛与开始门槛**同源**：
  - 地形卡走 `_try_get_interaction_range()`，距离口径「玩家节点中心 → 卡牌中心」≤ `InteractionRange`（默认 `160.0`）。
  - 建筑走 `_is_record_in_range()`，距离口径「玩家节点中心 → 建筑中心」≤ 该建筑自己的 `InteractionRadius`。
  - 两者都复用既有判定，各自不引入第二处距离来源，不加迟滞容差。
- 停止路径各自**唯一汇合**：地形 `_clear_active_terrain_hold()`、建筑 `_cancel_demolition()`。
  上一轮加的破坏抖动因此不会漏停。
- 取消是**终态**：走出范围后回到范围内不恢复已填进度。
- 地形长按期间的鼠标移动屏蔽（`_set_player_mouse_movement_blocked`）保持不变：点击移动已由
  `ClickWalk.CLICK_MOVEMENT_ENABLED = false` 全局停用，屏蔽当前是惰性的；解除它会顺带改变
  将来重新启用点击移动时的语义，超出本次范围。
- 保持 `_process_terrain_hold_input()` 的**方法名不变**：`tests/godot/test_loot_auto_pickup_contract.gd:85`
  逐字锁定了它。名字里的 "input" 仍成立（它读的是输入之后的交互状态），真实语义写进文档注释。

## 2. 地形卡：关键技术决策

### D1 范围复查放进 `_process_terrain_hold_input()`，替换「按方向键即取消」

现状（`world_interaction_coordinator.gd:245-260`）是「每帧只要按下任意 WASD 就取消」。
改成「每帧复查距离，超出才取消」：

```gdscript
func _process_terrain_hold_input() -> void:
	if _active_terrain_hold_card == null:
		return
	if not is_instance_valid(_active_terrain_hold_card):
		_cancel_active_hold()
		return

	var range_check: Dictionary = _try_get_interaction_range(_active_terrain_hold_card)
	if bool(range_check["ok"]):
		return

	# 先固定待提交的引用：_clear_active_terrain_hold 会清空记录。
	var out_of_range_card: Node2D = _active_terrain_hold_card
	# 只按拥有者取消，避免中断已由其它世界交互接管的圆环（与 _cancel_demolition 同一做法）。
	if _hold_interaction_controller != null and is_instance_valid(_hold_interaction_controller):
		_hold_interaction_controller.call("cancel_hold_for", out_of_range_card)
	_clear_active_terrain_hold()
	_report_out_of_range_interaction(out_of_range_card, float(range_check["distance"]))
```

要点：

- 保留既有的 `is_instance_valid` 分支：卡片可能在长按期间被房间重建释放，那条分支走
  `_cancel_active_hold()`（无飘字——卡都没了，没有可锚定的目标）。
- 用 `cancel_hold_for(owner)` 而不是无条件 `cancel_active_hold()`：与原有写法、以及
  `building_controller._cancel_demolition()` 的注释（「按拥有者取消，避免中断已经由其它世界交互
  接管的圆环」）一致。若长按已被别的交互接管，只清自己的记账。
- 复查频率就是 `_process` 的频率，`_process` 已经在调它（:239），不需要新增调用点。

### D2 走出范围的取消复用 `_report_out_of_range_interaction()` 漏斗

用户选定「复用现有『距离不够！』飘字 + 范围提示圈」。该漏斗（:469-474）已经是
「点击与长按两个鼠标入口共用」的单一出口，输出含真实距离的调试日志、飘字与半径
`InteractionRange` 的提示圈。直接复用即可，不新增半径来源——`tests/godot/test_floating_text_contract.gd:372`
锁定了调用点必须传 `FAILURE_TEXT_COLOR, InteractionRange`。

顺序是**先取消、后提示**：先 `_clear_active_terrain_hold()` 把状态与表现复位，再调用提示漏斗。
提示漏斗自己会做空值降级（`_floating_text` 缺失时只留调试日志），不需要额外守卫。

### D3 完成瞬间再复查一次，对齐建筑的既有先例

`_complete_terrain_hold()`（:840-863）目前**不**复查距离，理由是旧实现下玩家被钉在原地
（:693-695 的注释：「开始长按后玩家移动会被屏蔽（键盘方向输入会取消长按），因此本次交互在完成时
仍处于同一位置，完成入口不需要重复距离判定」）。本次改动打破了这个前提。

虽然 D1 的每帧复查会在走出范围的那一帧取消长按，但 `WorldHoldInteractionController` 用的是
`Tween`，同一帧内 Tween 与节点 `_process` 的先后顺序并不保证。`building_controller` 已经为同一类
竞态加了完成复查，注释写得很明确：「检查完成瞬间的输入及目标状态，**避免 Tween 比下一帧门禁先结算**」。
因此按同一模式在 `_complete_terrain_hold` 里补一道门：

```gdscript
	# Tween 可能比 _process 的范围复查先结算，因此完成瞬间按同一判定再复查一次；
	# 超范围时按「走出范围」处理，不消耗行动值、不生成掉落。
	var range_check: Dictionary = _try_get_interaction_range(card)
	if not bool(range_check["ok"]):
		_report_out_of_range_interaction(card, float(range_check["distance"]))
		return
```

位置放在 `GetTerrainInstanceOrNull() != terrain` 之后、可重复采集复查之前：地形已经换掉时静默放弃
（目标已不是原来那个），只有「目标还在但人走远了」才给距离反馈。

不会出现双重提示：D1 取消时会 `cancel_hold_for` → `cancel_active_hold()` 杀掉 Tween，
被杀的 Tween 不触发 `finished`，完成回调根本不会跑。

**代价**：`_try_get_interaction_range(card)` 的调用点从 2 处变成 3 处，
`tests/godot/test_world_interaction_coordinator_contract.gd::test_interaction_range_gate` 的
`_count_occurrences(...) == 2` 断言要改成 3，理由从「点击与长按两个入口」更新为
「点击、长按开始、长按完成三个入口」。

### D4 开始门槛只由距离决定，删掉「方向键已按住就不开始」

`_on_board_card_pressed()` 的 :728-730：

```gdscript
	if Input.get_vector("move_left", "move_right", "move_up", "move_down") != Vector2.ZERO:
		_clear_active_terrain_hold()
		return
```

这段在旧设计下是「键盘接管优先」的兜底，新设计下方向键与长按无关，整段删除。
保留它反而会造出「按下时刚好在走 → 长按不开始」的随机体验，与 R4 冲突。
按下瞬间的范围门槛（:708-711）不动。

同时把 `_on_board_card_pressed` 的文档注释（:693-695）从「玩家移动会被屏蔽，因此完成时仍在同一位置」
改写为「长按期间走出范围会立即取消，因此能走到完成回调时玩家必定仍在范围内」。

## 3. 建筑：关键技术决策

### D5 用「鼠标屏幕坐标是否变化」区分玩家操作与相机漂移

**问题根源**：`_can_continue_demolition()`（:489-495）每帧用 `_building_under_pointer()` 重新命中目标，
而它（:432-443）依赖 `_mouse_world_position()` = `_buildings_root.get_global_mouse_position()`，
把**屏幕光标**换算到世界坐标。相机跟随玩家平移时，光标下的世界点随相机一起漂移，
于是玩家只在范围内挪一步，光标也会离开建筑占地 → 门禁 false → 取消。

**判据**：相机平移不改变鼠标的**屏幕**坐标。玩家没碰鼠标时屏幕采样逐帧恒定；
玩家真的把鼠标移到空白处或另一栋建筑时，屏幕采样一定会变。因此只在
「这一帧鼠标的屏幕坐标变了」时才做光标目标复查。

新增一个字段与一个容差常量：

```gdscript
## 上一次采样的鼠标屏幕坐标；用于区分「玩家自己动了鼠标」与「相机跟随造成的世界坐标漂移」。
var _demolition_mouse_screen: Vector2 = Vector2.ZERO
```

```gdscript
## 鼠标屏幕位移超过该像素值才认定为玩家主动移动鼠标，避免浮点误差与系统级抖动触发目标复查。
##
## 单位是视口像素：_mouse_screen_position() 把世界坐标乘回画布变换后得到的就是屏幕坐标，
## 因此与相机缩放无关。
const DEMOLITION_MOUSE_MOVE_TOLERANCE: float = 0.5
```

```gdscript
## 采样鼠标的屏幕坐标。
##
## 必须回到屏幕空间比较：相机跟随玩家平移时屏幕光标不动、世界坐标会漂移，
## 只有屏幕坐标才能区分「玩家自己动了鼠标」与「相机动了」。
##
## 实现上先经 _mouse_world_position() 取世界坐标再乘本节点所在画布的变换，而不是直接读
## get_viewport().get_mouse_position()：前者沿用回归场景 ControllerInputProbe 已经覆写的
## 鼠标采样接口，测试不必为漂移判定再加一个替身接口。
##
## @return 鼠标在屏幕空间的位置。
func _mouse_screen_position() -> Vector2:
	return _buildings_root.get_canvas_transform() * _mouse_world_position()
```

`get_global_mouse_position()` 给的是画布（世界）坐标，`get_canvas_transform()` 是「画布 → 视口」，
两者相乘即得屏幕坐标；生产环境下这条往返是恒等的（浮点误差由 0.5px 容差吸收）。

目标复查助手：

```gdscript
## 复查本次拆除的目标是否仍被玩家选中。
##
## 相机跟随玩家平移时，屏幕光标不动、世界坐标却会漂移；如果每帧都按光标重新命中，
## 「在范围内移动」就会被误判成「移开鼠标」。因此只在玩家自己动过鼠标的那一帧才重新命中，
## 其余帧沿用开始长按时锁定的目标。
##
## @return 目标未被切换时为 true。
func _is_demolition_target_kept() -> bool:
	var mouse_screen: Vector2 = _mouse_screen_position()
	var mouse_moved: bool = mouse_screen.distance_to(_demolition_mouse_screen) > DEMOLITION_MOUSE_MOVE_TOLERANCE
	# 采样基准每帧前移：只比较相邻两帧，因此慢速拖动也会在光标离开建筑的那一帧被发现。
	_demolition_mouse_screen = mouse_screen
	if not mouse_moved:
		return true
	# 玩家自己动了鼠标：沿用既有的光标命中口径，「移开鼠标」与「切换目标」都取消。
	var pointed: Dictionary = _building_under_pointer()
	return not pointed.is_empty() and int(pointed["id"]) == _demolition_id
```

`_begin_demolition()` 在 `_demolition_id = int(record["id"])`（:474）之后、启动抖动与长按之前
写入首帧基准：

```gdscript
	# 记录本帧鼠标屏幕坐标，作为「玩家是否自己动过鼠标」的比较基准。
	_demolition_mouse_screen = _mouse_screen_position()
```

`_building_under_pointer()` 与 `_mouse_world_position()` 都**不改**，仍被按下路径（:424）与本次复查共用。

### D6 每帧门禁与完成门禁拆开：遮挡只在完成瞬间拦（用户决策）

用户选定「每帧只判距离，遮挡只在完成瞬间拦」。因此把现在一个函数承担的两件事拆开，
并用两段公共助手避免条件漂移：

```gdscript
## 拆除长按的公共输入与世界门禁；每帧门禁与完成门禁共用，避免两组条件漂移。
##
## @return 左键仍按住、未在放置、无界面遮挡且世界可用时为 true。
func _is_demolition_input_available() -> bool:
	return _demolition_id >= 0 and _is_demolition_button_pressed() and _world_available() \
		and _placing_data == null and not _has_open_overlay() \
		and get_viewport().gui_get_hovered_control() == null


## 检查拆除长按是否仍可继续；每帧门禁只看距离，遮挡留到完成瞬间再判。
##
## 玩家在交互范围内移动（含相机跟随造成的建筑位移、走到墙后）都不该打断拆除，
## 因此这里不判遮挡；「不允许隔墙远程破坏」由 _can_complete_demolition 把关。
##
## @return 仍可继续时为 true。
func _can_continue_demolition() -> bool:
	if not _is_demolition_input_available() or not _is_demolition_target_kept():
		return false
	var record: Dictionary = _record_for_instance(_demolition_id)
	return not record.is_empty() and _is_record_in_range(record)


## 检查拆除完成瞬间的输入及目标状态，避免 Tween 比下一帧门禁先结算。
##
## 比每帧门禁多一条遮挡判定：长按期间允许移动，但进度填满时仍不能隔墙远程拆除。
##
## @return 允许结算拆除时为 true。
func _can_complete_demolition() -> bool:
	if not _is_demolition_input_available() or not _is_demolition_target_kept():
		return false
	var record: Dictionary = _record_for_instance(_demolition_id)
	return not record.is_empty() and _is_record_reachable(record)
```

- `_process()` :262 继续用 `_can_continue_demolition()`（每帧，只看距离）。
- `_complete_demolition()` :500 改用 `_can_complete_demolition()`（完成瞬间，含遮挡）。
- 现状 :489 的注释「重新命中当前鼠标目标，不能沿用开始长按时的旧引用」随行为改写为
  「鼠标未动时沿用锁定目标，玩家动过鼠标时才重新命中」。

按 id 取记录的助手，复刻 `_building_world_position()`（:764-770）既有的遍历写法：

```gdscript
## 按实例标识取回当前房间的建筑记录；记录已不存在时返回空字典。
##
## 鼠标未移动时用它沿用开始长按时锁定的目标，不再按光标重新命中。
##
## @param instance_id 建筑实例标识。
## @return 该实例的记录；仓库不可用或记录已删除时返回空字典。
func _record_for_instance(instance_id: int) -> Dictionary:
	if not is_instance_valid(_store):
		return {}
	for record: Dictionary in _store.call("GetBuildings", _room):
		if int(record["id"]) == instance_id:
			return record
	return {}
```

### D7 走出范围的取消给距离反馈

用户选定「复用 `_show_building_out_of_range`」。`_process` 的拆除分支改为：

```gdscript
	if _demolition_id >= 0:
		# 目标、输入与世界状态持续有效才允许进度完成；外部取消长按也清理提示。
		var hold: Node = _world_hold()
		if not _can_continue_demolition() or hold == null or not bool(hold.get("is_holding")):
			# 只有「按住时走出交互范围」需要解释原因；暂停、界面、战斗、松键、移开鼠标保持静默。
			var out_of_range_record: Dictionary = _out_of_range_demolition_record()
			_cancel_demolition()
			if not out_of_range_record.is_empty():
				_show_building_out_of_range(out_of_range_record)
		else:
			_set_focus(_demolition_id)
			_hint.text = "正在拆除 · 松开左键、移开鼠标或走出交互范围取消"
			return
```

新增的判定助手：

```gdscript
## 返回「拆除只因玩家走出交互范围而失效」时的建筑记录；其它原因返回空字典。
##
## 暂停、打开界面、进入战斗、松键、移开鼠标等原因不该弹「距离不够」，因此必须把范围单独判出来。
##
## @return 只因超出交互范围而失效时的记录；否则返回空字典。
func _out_of_range_demolition_record() -> Dictionary:
	# 必须先确认左键仍按住：松键取消不该被误报成距离不足。
	if _demolition_id < 0 or not _is_demolition_button_pressed():
		return {}
	var record: Dictionary = _record_for_instance(_demolition_id)
	if record.is_empty() or _is_record_in_range(record):
		return {}
	return record
```

`_show_building_out_of_range(record)`（:741-743）已经是「『距离不够！』飘字 + 半径取该建筑自己的
`InteractionRadius` 的提示圈」，注释明确「与 `_is_record_in_range` 的判定口径完全一致，
不引入第二处距离来源」，直接复用。

注意 `_process` :240 的「世界不可用 / 有界面打开」分支在更前面就 `_cancel_demolition()` 并 return，
不会走到 D7 的反馈逻辑，因此战斗与界面导致的取消天然静默。

## 4. 数据流

```
地形卡：按住左键点中卡牌（范围内）
  └─ _on_board_card_pressed()
       ├─ _try_get_interaction_range → 超出则 _report_out_of_range_interaction 并 return（不变）
       ├─ 抖动开始 / 屏蔽鼠标移动（不变）
       └─ begin_hold(...)                       ← 不再因「方向键已按住」而放弃

每帧 _process
  └─ _process_terrain_hold_input()
       ├─ 卡片已释放 → _cancel_active_hold()（不变）
       ├─ 仍在范围内 → 直接 return               ← 键盘移动不再打断
       └─ 走出范围 → cancel_hold_for + _clear_active_terrain_hold()
                     + _report_out_of_range_interaction()   ← 新增

进度填满 → _complete_terrain_hold()
       ├─ 目标/地形校验（不变）
       ├─ 范围复查：超出 → 飘字后 return          ← 新增（挡住 Tween 抢先结算）
       └─ _execute_terrain_interaction(...)

建筑：按住左键命中建筑（可达）
  └─ _begin_demolition(record)   ← 仍按光标选中 + _is_record_reachable（不变）
       ├─ 记录 _demolition_mouse_screen 基准     ← 新增
       └─ 抖动开始 / begin_timed_hold(...)

每帧 _process（_demolition_id >= 0）
  └─ _can_continue_demolition()
       ├─ 输入/世界门禁失败        → 取消（静默）
       ├─ 鼠标动了且已不在本目标上 → 取消（静默，移开鼠标 / 切换目标）
       ├─ 记录已删除              → 取消（静默）
       ├─ 仍在范围内              → 继续       ← 鼠标没动时的相机漂移不再打断
       └─ 走出范围                → _cancel_demolition() + _show_building_out_of_range()

进度填满 → _complete_demolition()
       └─ _can_complete_demolition()  ← 含遮挡；隔墙不结算
```

## 5. 受影响的契约与测试

| 位置 | 现状 | 本次 |
|---|---|---|
| `test_loot_auto_pickup_contract.gd:85` | 锁定 `func _process_terrain_hold_input() -> void:` | 方法名保留，**断言不变** |
| `test_world_interaction_coordinator_contract.gd:484-488` | `_count_occurrences(..., "var range_check: Dictionary = _try_get_interaction_range(card)") == 2` | 改为 **3**，理由更新为「点击、长按开始、长按完成」 |
| `test_world_interaction_coordinator_contract.gd:459-479` | 锁定 `InteractionRange` 声明、助手签名、距离表达式、返回形状 | **不变**（复用，不改助手） |
| `test_world_interaction_coordinator_contract.gd:346-349` | 锁定 `cancel_hold_for` / `cancel_active_hold` 调用片段 | 两处调用都未动 → **不变** |
| `test_floating_text_contract.gd:372` | 锁定飘字调用传 `FAILURE_TEXT_COLOR, InteractionRange` | 复用同一漏斗 → **不变** |
| `test_floating_text_contract.gd:263-264` | 锁定 `_is_record_in_range` 被 `_is_record_reachable` 复用 | 未改这两个函数 → **不变** |
| `test_destroy_hold_shake.gd:114-128` | 锁定 `SetDestroying(true/false)` 调用片段 | 抖动启停位置未动 → **不变** |
| `building_system_tests.gd:443` | `_check(not hold.get("is_holding"), "移开鼠标或换目标必须取消拆除")` | **不变**：该用例显式改了注入的鼠标位置，等价于玩家真的动了鼠标，新逻辑下仍取消 |
| `building_system_tests.gd:458` | `_check(board.spawned_drops.is_empty(), "长按中走远必须取消拆除")` | 保留（走远仍取消） |
| `building_system_tests.gd:90` | 覆盖说明 | 补一句「鼠标不动时的相机漂移不取消」 |
| 新增 `tests/godot/test_hold_move_within_range.gd` + 2 行壳 | — | 新增 |

新套件用**真实脚本 + 最小夹具**做运行时与形状断言（不实例化生产场景）：

- 地形卡：`load("res://core/gameflow/world_interaction_coordinator.gd").new()` 后直接注入内部字段
  （`_player_char` / `_active_terrain_hold_card` / `_hold_interaction_controller` / `_floating_text`），
  再调用 `_process_terrain_hold_input()`。可行性已核实：
  `_player_char: Node2D`、`_active_terrain_hold_card: Node2D`、`_hold_interaction_controller: Node`
  都是宽类型或 Node2D，**可以注入桩**，不需要真实的棋盘 / 圆环 / HUD。
- 建筑：复用 `building_system_tests.gd` 里既有的
  `ControllerInputProbe extends "res://core/building/building_controller.gd"` 夹具思路
  （它已覆写 `_mouse_world_position` 与 `_is_demolition_button_pressed`）。新增两条覆盖：
  - 保持注入的鼠标位置不变、只改玩家位置（模拟相机漂移）→ `_can_continue_demolition()` 仍为 true。
  - 改变注入的鼠标位置到另一栋建筑 / 空白处 → `_can_continue_demolition()` 为 false。
- 形状断言：协调器 `_process_terrain_hold_input` 不再含 `Input.get_vector`；
  建筑 `_can_continue_demolition` 含 `_is_record_in_range` 且**不含** `_is_record_reachable`；
  `_can_complete_demolition` 含 `_is_record_reachable`；`_is_demolition_target_kept` 含
  `_building_under_pointer`；提示文案含「走出交互范围」。
- 桩用 GDScript 内部类（`class StubHold extends Node` 等）实现 `cancel_hold_for(owner)` / `is_holding`
  与 `show_at_target(...)`，记录调用次数。
- 「键盘不再打断」用 `Input.action_press("move_right")` 真实模拟：**按下 → 调一次 → 立刻
  `Input.action_release` → 再断言**。顺序很重要：`McpTestSuite.assert_*` 在首次失败后会提前 return，
  把释放写在断言之后会漏掉清理、把编辑器输入状态留在「方向键按住」。

## 6. 风险与对策

| 风险 | 对策 |
|---|---|
| 走出范围后每帧重复取消 / 重复飘字 | 取消会清空 `_active_terrain_hold_card` / 置 `_demolition_id = -1`，下一帧首行即 return，只触发一次 |
| 取消时把别的交互刚接管的圆环一起掐掉 | 两条长按都用按拥有者的 `cancel_hold_for`，不用无条件 `cancel_active_hold()` |
| Tween 比每帧复查先结算，导致超范围仍然完成 | 两条长按都在完成入口按同一判定再复查一次（D3 / D6） |
| 建筑每帧不判遮挡后可以隔墙远程拆除 | 完成门禁 `_can_complete_demolition` 仍含 `_is_record_reachable`（D6） |
| 屏幕采样往返的浮点误差被当成「玩家动了鼠标」 | 0.5 视口像素容差（D5）；容差内不做目标复查，最坏情况是漏掉一次复查、下一帧补上 |
| 玩家轻碰鼠标后停住，随后相机漂移把建筑移出光标，被误判成移开鼠标 | 采样基准**每帧前移**，只在「相邻两帧之间鼠标真的动了」的那一帧复查；停住之后不再复查（D5） |
| 慢速拖动鼠标漏检 | 相邻两帧比较，慢速拖动每帧仍有位移；容差只吸收浮点误差与系统抖动（D5） |
| 回归场景只覆写 `_mouse_world_position()` | `_mouse_screen_position()` 经它换算，**不需要新增替身接口**；现有 `building_system_tests.gd:443` 断言因此继续成立 |
| 松键与走出范围同时发生被误报成距离不足 | `_out_of_range_demolition_record()` 先确认左键仍按住（D7） |
| 卡片 / 建筑在长按期间被释放或删除 | 地形保留 `is_instance_valid` 分支；建筑 `_record_for_instance` 返回空字典即取消 |
| 测试场景没有 `_player_char`，复查会误判 | `_try_get_interaction_range` 在玩家缺失时返回 `ok: true`（既有约定），不会误取消 |
| `building_system_tests.gd` 的 `gui_get_hovered_control()` 在测试场景非空 | `Label` 默认 `MOUSE_FILTER_IGNORE`，提示不会挡鼠标；仍以实跑该场景确认 |
| 测试里 `Input.action_press` 未释放污染编辑器 | 释放写在断言之前（见 §5） |

## 7. 回滚形状

- 生产改动集中在两个文件：
  - `core/gameflow/world_interaction_coordinator.gd` 的三个函数与两处文档注释。
  - `core/building/building_controller.gd` 的门禁拆分、三个新助手、一个字段、一个常量、
    `_begin_demolition` 一行、`_process` 分支与提示文案。
- `git revert` 单个提交即可恢复；新增测试套件与其壳文件可直接删除。
- 不涉及场景、资源、autoload 与公开签名，无数据或存档兼容问题。

## 8. 验证策略

- **契约测试**：新增 `tests/godot/test_hold_move_within_range.gd` + 2 行壳
  `tests/test_hold_move_within_range.gd`；同步调整 `test_interaction_range_gate` 的计数断言。
- **建筑回归场景**：`project_run(mode="custom", scene="res://tests/godot/building_system_tests.tscn")`，
  确认 :443「移开鼠标必须取消」与 :458「走远必须取消」都仍然通过。
  注意该场景**预先存在**一个与本次无关的崩溃：`:178` 读 `inputs[1].get("RequiredItem")`，
  而 `resources/recipe/res/campfire_recipe.tres` 的 `Inputs` 只有 1 项（3 树枝，无火），
  因此 `_test_recipe_and_crafting` 报类型错误。`_check` 只累加失败不中断、且 `_ready()` 里该函数是
  同步调用，所以拆除用例仍会执行。**只报告，不在本任务修复。**
- **全量回归**：`test_run()`，与改动前失败清单对比，确认零新增失败。
- **端到端（`scenes/Main.tscn` + `game_eval`）**——这是本协调器既有套件指定的实证方式
  （「真实拦截效果由 Main 场景冒烟阶段的 game_eval 实证」）：
  1. 地形卡：真实卡牌 + 真实 `_on_board_card_pressed`；`Input.action_press("move_right")` 后推进若干帧，
     断言长按仍在、`_active_terrain_hold_card` 未变、圆环仍可见（范围内移动不打断）。
  2. 地形卡：把玩家 `global_position` 移出 `InteractionRange` 后推进一帧，断言长按被取消、
     圆环隐藏、`SetDestroying` 已复位、飘字入口被调用。
  3. 地形卡完成入口：移出范围后直接调 `_complete_terrain_hold`，断言不进入 `_execute_terrain_interaction`。
  4. 建筑：放置一栋篝火，真实 `_begin_demolition` 后**不碰鼠标**、只把玩家在范围内移动若干帧，
     断言 `_can_continue_demolition()` 仍为 true、`_demolition_id` 未变、圆环仍可见。
  5. 建筑：把玩家移出该建筑 `InteractionRadius`，推进一帧后断言 `_demolition_id == -1`、
     建筑仍在、无掉落、飘字入口被调用。
  6. 建筑：重新开始拆除后把鼠标世界坐标改到另一栋建筑 / 空白处，断言 `_demolition_id == -1`（切换目标仍取消）。
  7. 建筑遮挡：把玩家移到范围内但有墙遮挡的位置，断言每帧门禁仍为 true，
     而直接调 `_complete_demolition()` 不结算、建筑保留。
- **注意**：`game_eval` 只支持制表符缩进、不能声明函数；相机跟随会让屏幕坐标整体漂移，
  因此涉及位置的断言一律用**世界坐标**或内部字段，不用屏幕坐标。
