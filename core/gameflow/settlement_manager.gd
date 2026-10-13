extends Node

## 常驻的轮回协调入口：唯一持有本局账本，统一计算、入库、保存和导航。
## 公开方法通过稳定节点路径使用现有存档与仓库，不直接访问玩家私有状态。
const RUN_DATA: GDScript = preload("res://core/gameflow/run_session_data.gd")
const PANEL_PATH: String = "res://scenes/GameProcess/Settlement.tscn"
const MENU_PATH: String = "res://scenes/main_menu_scenes/login_menu.tscn"
const MAIN_PATH: String = "res://scenes/Main.tscn"

## 参数 result 是独立结果副本，面板不得用它再次发奖。
signal settlement_ready(result: Dictionary)
## 参数 capacity 是下局使用的局外格数。
signal harvest_capacity_changed(capacity: int)

## 与 SaveManager 共用配置资产；测试赠品开关允许在检查器中修改。
@export var config: SettlementConfig = preload("res://resources/save/settlement_config.tres")

var _run: RefCounted = null
var _last_result: Dictionary = {}
var _timing_started: bool = false
var _ending: bool = false
var _navigating: bool = false
var _panel: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bus: Node = get_node_or_null("/root/GlobalEventBus")
	if bus != null and not bus.is_connected("player_died", _on_player_died):
		bus.connect("player_died", _on_player_died)


func _exit_tree() -> void:
	# 离树时归还订阅，避免缓存重入或替换经理留下旧死亡回调。
	var bus: Node = get_node_or_null("/root/GlobalEventBus")
	if is_instance_valid(bus) and bus.has_signal("player_died") and bus.is_connected("player_died", _on_player_died):
		bus.disconnect("player_died", _on_player_died)


func _process(delta: float) -> void:
	if is_run_active() and _timing_started and not get_tree().paused:
		_run.call("advance_time", delta)


## 参数 context 为可选开局描述；在消耗带入前调用，无返回值。
func begin_run(context: Dictionary = {}) -> void:
	var save: Node = _save_manager()
	if save != null:
		# 门禁早于任何带入消耗信号，防止自动保存记录半次开局。
		save.call("begin_run_write_hold")
	var id: String = "%s-%s-%s" % [Time.get_unix_time_from_system(), Time.get_ticks_usec(), randi()]
	_run = RUN_DATA.new(id, _profile_capacity())
	_run.call("set_description", str(context.get("description", "")))
	_last_result.clear()
	_timing_started = false
	_ending = false
	_navigating = false
	_panel = null


## 开局装配完成后开始计时；无参数，无返回值。
func complete_run_initialization() -> void:
	if is_run_active():
		_timing_started = true


## 无参数；返回是否允许采集和统计。
func is_run_active() -> bool:
	return _run != null and not _ending and not bool(_run.get("ended"))


## 无参数；返回本局是否已经进入结束流程（包括已完成）。
func is_run_ending() -> bool:
	return _ending


## 参数 key、delta 为统计名和增量；只改内存，返回是否成功。
func record_statistic(key: String, delta: int = 1) -> bool:
	return is_run_active() and bool(_run.call("record_statistic", key, delta))


## 参数 resource_id、amount 为成功领取资源及数量；返回是否已计入统计。
## 此记录不授予轮回资格，也不复制背包物品。
func record_resource(resource_id: String, amount: int) -> bool:
	return amount > 0 and record_statistic("resource:" + resource_id, amount)


## 参数 text 是完整当局描述；无返回值。
func set_description(text: String) -> void:
	if is_run_active():
		_run.call("set_description", text)


## 参数 text 是要追加的一行描述；无返回值。
func add_description(text: String) -> void:
	if is_run_active():
		_run.call("add_description", text)


## 参数 item、amount、rolled 为已授权奖励；返回是否完整放入收获账本。
## 这是领域奖励入口；建筑应调用资格校验后的选择入口，而非直接发奖。
func add_harvest_item(item: Resource, amount: int, rolled: Dictionary = {}) -> bool:
	return is_run_active() and bool(_run.call("add_harvest_item", item, amount, rolled))


## 参数 item 为物品；返回正式白名单资格，测试赠送不会修改白名单。
func can_reincarnate(item: Resource) -> bool:
	if item == null or config == null:
		return false
	var allowed: Array = config.get("allowed_resources")
	return allowed.has(item)


## 无参数；返回本局固定容量，局外返回下局容量。
func get_harvest_capacity() -> int:
	return int(_run.get("capacity")) if is_run_active() else _profile_capacity()


## 参数 capacity 为下局格数（至少五格）；返回是否更新成功。
## 当前局容量保持开局值，避免升级改变已经固定的结果。
func set_harvest_capacity(capacity: int) -> bool:
	var profile: RefCounted = _profile()
	if profile == null or capacity < 5:
		return false
	if not bool(profile.call("set_harvest_capacity", capacity)):
		return false
	harvest_capacity_changed.emit(capacity)
	var save: Node = _save_manager()
	if save != null:
		save.call("request_save")
	return true


## 无参数；返回当前未占用格数，已结束时为零。
func get_remaining_harvest_slots() -> int:
	return int(_run.call("get_remaining_slots")) if is_run_active() else 0


## 参数 source 为来源库存、slot_index 为精确槽位、amount 为数量。
## 返回 ok/error；本期只校验入口并明确拒绝，不改变库存或收获。
## 建筑开发阶段再确定选择的移转语义，不能由预留接口提前扣货。
func try_select_reincarnation_item(source: Node, slot_index: int, amount: int) -> Dictionary:
	if not is_run_active():
		return _selection_error("当前无法选择收获")
	if not is_instance_valid(source) or source.is_queued_for_deletion() or amount <= 0 or slot_index < 0:
		return _selection_error("来源或数量无效")
	if not source.has_method("GetStackAt"):
		return _selection_error("来源未实现库存查询接口")
	var capacity: Variant = source.get("Capacity")
	if not (capacity is int) or slot_index >= int(capacity):
		return _selection_error("来源槽位无效")
	var stack: Variant = source.call("GetStackAt", slot_index)
	if not is_instance_valid(stack) or not (stack is Object):
		return _selection_error("来源物品无效")
	var item: Resource = stack.get("Item") as Resource
	if not can_reincarnate(item):
		return _selection_error("该资源尚未允许轮回")
	return _selection_error("轮回选择建筑尚未接入，物品未移转")


## 参数 selection_id 为选择编号、amount 为取消数量（-1 表示全部）。
## 返回 ok/error；本期无建筑选择记录，拒绝取消且不改变任何资产。
func try_remove_reincarnation_item(selection_id: String, amount: int = -1) -> Dictionary:
	if not is_run_active():
		return _selection_error("当前无法取消选择")
	if selection_id.is_empty() or (amount != -1 and amount <= 0):
		return _selection_error("选择编号或取消数量无效")
	return _selection_error("轮回选择建筑尚未接入，物品未移转")


## 无参数；本期建筑未接入，返回空的独立选择数组。
func get_reincarnation_selection() -> Array:
	return []


## 参数为 death/win/abandon 和可选结局编号、标题；返回独立结算结果。
## 重复请求只返回同一结果，普通战斗胜利不得调用此方法。
func finish_run(reason: String = "death", ending_id: String = "", ending_title: String = "") -> Dictionary:
	if _ending or not is_run_active():
		return get_last_result()
	if not ["death", "win", "abandon"].has(reason):
		return {}
	# 测试赠品经过同一添加入口，但不取得正式资源资格。
	if reason == "death" and bool(config.get("enable_death_test_reward")):
		if not add_harvest_item(config.get("death_test_item") as Resource, 1):
			add_description("测试奖励未生成：收获格已满或测试物品配置无效")
	_ending = true
	_timing_started = false
	_run.set("ended", true)
	get_tree().paused = true
	var statistics: Dictionary = (_run.get("statistics") as Dictionary).duplicate(true)
	# 唯一规则入口同时接收正式收获和测试赠品；计算不直接操作资产。
	var rewards: Dictionary = config.calculate_rewards(_run.call("get_harvest"), statistics.duplicate(true), reason)
	var harvest: Array = []
	for stack: RefCounted in rewards.get("harvest", []):
		# 规则实现可能保留其返回对象，固定结果再隔离一次，避免后续修改重复影响入账。
		harvest.append(stack.call("Duplicate"))
	var raw_tokens: Variant = rewards.get("tokens", 0)
	var token_delta: int = maxi(0, int(raw_tokens)) if raw_tokens is int or raw_tokens is float else 0
	var titles: Dictionary = {"death": "死亡", "win": "通关", "abandon": "主动结束"}
	_last_result = {
		"run_id": _run.get("run_id"), "reason": reason, "ending_id": ending_id,
		"ending_title": ending_title if not ending_title.is_empty() else titles[reason],
		"duration_seconds": _run.get("duration_seconds"), "description": _run.get("description"),
		"statistics": statistics,
		"capacity": _run.get("capacity"), "harvest": harvest, "token_delta": token_delta,
		"persisted": false, "pending_count": 0, "error": ""
	}
	var profile: RefCounted = _profile()
	if profile == null:
		_last_result["error"] = "局外档案尚未就绪，无法入账"
	else:
		var id: String = str(_last_result["run_id"])
		if not bool(profile.call("has_settled_run", id)):
			for stack: RefCounted in _last_result["harvest"]:
				var remaining: RefCounted = _deposit_stack(stack)
				if remaining != null:
					profile.call("add_pending_harvest", [remaining])
			profile.call("add_tokens", token_delta)
			profile.call("mark_run_settled", id)
		_last_result["pending_count"] = _pending_amount(profile)
		var save: Node = _save_manager()
		if save != null:
			# 清空标记阻止仍在树中的旧世界快照重新捕获已结束局。
			save.call("clear_run_scope")
			save.call("end_run_write_hold")
			if bool(save.call("is_persistence_enabled")):
				_last_result["persisted"] = bool(save.call("save_now"))
				if not bool(_last_result["persisted"]):
					_last_result["error"] = "保存失败，请重试后再离开"
	settlement_ready.emit(get_last_result())
	call_deferred("_show_panel")
	return get_last_result()


## 无参数；返回独立结果，嵌套堆叠也复制，防止外部修改奖励数量。
func get_last_result() -> Dictionary:
	var result: Dictionary = _last_result.duplicate(true)
	var copies: Array = []
	for stack: RefCounted in _last_result.get("harvest", []):
		copies.append(stack.call("Duplicate"))
	if not result.is_empty():
		result["harvest"] = copies
	return result


## 无参数；仅重试同一次存档，不再添加收获，返回保存是否成功。
func retry_persistence() -> bool:
	var save: Node = _save_manager()
	var profile: RefCounted = _profile()
	if _last_result.is_empty() or save == null or profile == null:
		return false
	if not bool(profile.call("has_settled_run", str(_last_result["run_id"]))):
		return false
	if not bool(save.call("is_persistence_enabled")):
		return true
	var success: bool = bool(save.call("save_now"))
	_last_result["persisted"] = success
	_last_result["error"] = "" if success else "保存失败，请重试后再离开"
	_refresh_panel()
	return success


## 无参数；局外重试领取待领取真实收获，返回本次实际入库数量。
func claim_pending_harvest() -> int:
	if is_run_active():
		return 0
	var profile: RefCounted = _profile()
	if profile == null:
		return 0
	var leftovers: Array = []
	var claimed: int = 0
	for stack: RefCounted in profile.call("get_pending_harvest"):
		var remaining: RefCounted = _deposit_stack(stack)
		claimed += int(stack.get("Amount")) - (int(remaining.get("Amount")) if remaining != null else 0)
		if remaining != null:
			leftovers.append(remaining)
	profile.call("replace_pending_harvest", leftovers)
	var save: Node = _save_manager()
	if save != null and claimed > 0:
		save.call("request_save")
	return claimed


## 参数 destination 为 menu 或 next_run；返回是否受理，失败保持面板可操作。
func navigate_to(destination: String) -> bool:
	if _navigating or _last_result.is_empty() or not ["menu", "next_run"].has(destination):
		_refresh_panel()
		return false
	if not str(_last_result.get("error", "")).is_empty():
		_refresh_panel()
		return false
	_navigating = true
	get_tree().paused = false
	var error: Error = get_tree().change_scene_to_file(MENU_PATH if destination == "menu" else MAIN_PATH)
	if error != OK:
		_navigating = false
		get_tree().paused = true
		_last_result["error"] = "场景切换失败（%d）" % error
		_refresh_panel()
		return false
	return true


func _on_player_died() -> void:
	finish_run("death")


func _show_panel() -> void:
	if _navigating or _last_result.is_empty() or is_instance_valid(_panel):
		return
	var host: Node = get_tree().current_scene
	if host == null:
		return
	var scene: PackedScene = load(PANEL_PATH) as PackedScene
	if scene == null:
		push_error("结算场景未能加载：" + PANEL_PATH)
		return
	_panel = scene.instantiate()
	_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.call("set_result", get_last_result())
	_panel.connect("navigation_requested", navigate_to)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "SettlementLayer"
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)
	layer.add_child(_panel)


func _refresh_panel() -> void:
	if is_instance_valid(_panel):
		_panel.call("set_result", get_last_result())


func _deposit_stack(stack: RefCounted) -> RefCounted:
	var warehouse: Node = get_node_or_null("/root/GlobalWarehouse")
	var remaining: int = int(stack.get("Amount"))
	if warehouse != null and warehouse.has_method("AddItemStack"):
		remaining = int(warehouse.call("AddItemStack", stack))
	if remaining <= 0:
		return null
	var copy: RefCounted = stack.call("Duplicate")
	copy.set("Amount", remaining)
	return copy


func _pending_amount(profile: RefCounted) -> int:
	var count: int = 0
	for stack: RefCounted in profile.call("get_pending_harvest"):
		count += int(stack.get("Amount"))
	return count


func _profile_capacity() -> int:
	var profile: RefCounted = _profile()
	return int(profile.call("get_harvest_capacity")) if profile != null else 5


func _profile() -> RefCounted:
	var save: Node = _save_manager()
	return save.call("get_profile") as RefCounted if save != null else null


func _save_manager() -> Node:
	return get_node_or_null("/root/SaveManager")


func _selection_error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
