extends Node2D

## 结算面板根控制器，协调固定结果、各显示区域和导航意图。
## 参数由 set_result 与文案接口提供；不收集、计算或发放奖励。

## 玩家选择去向；参数 destination 为 menu 或 next_run。
signal navigation_requested(destination: String)

const MANAGER_PATH: NodePath = ^"/root/SettlementManager"

var _result: Dictionary = {}
var _has_result: bool = false
var _navigation_pending: bool = false
var _manager: Node = null

@onready var _harvest: Node = get_node("Harvest/ScrollContainer/SlotGrid")
@onready var _statistics: Node = get_node("Data")
@onready var _buttons: Node = get_node("ButtonSection")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_buttons.connect("retry_requested", _on_retry_requested)
	_manager = get_node_or_null(MANAGER_PATH)
	if _manager != null:
		var callback := Callable(self, "set_result")
		if _manager.has_signal("settlement_ready") and not _manager.is_connected("settlement_ready", callback):
			_manager.connect("settlement_ready", callback)
		if not _has_result and _manager.has_method("get_last_result"):
			var existing: Variant = _manager.call("get_last_result")
			if existing is Dictionary and not (existing as Dictionary).is_empty():
				_result = (existing as Dictionary).duplicate(true)
	_refresh_result()

## 绑定固定结果；允许经理在面板进入场景树之前调用。
## 参数 result：统一结算结果字典；返回值：无。
func set_result(result: Dictionary) -> void:
	_result = result.duplicate(true)
	_has_result = true
	_navigation_pending = false
	if is_node_ready():
		_refresh_result()

## 更新显示的游玩时间，不修改已入账奖励。
## 参数 seconds：活跃秒数；返回值：无。
func set_play_time(seconds: float) -> void:
	_result["duration_seconds"] = maxf(seconds, 0.0)
	_has_result = true
	if is_node_ready():
		_statistics.call("set_play_time", seconds)

## 更新结局显示。
## 参数 id：稳定结局标识；title：显示名称；返回值：无。
func set_ending(id: String, title: String) -> void:
	_result["ending_id"] = id
	_result["ending_title"] = title
	_has_result = true
	if is_node_ready():
		_statistics.call("set_ending", id, title)

## 替换整段描述。
## 参数 text：新描述；返回值：无。
func set_description(text: String) -> void:
	_result["description"] = text
	_has_result = true
	if is_node_ready():
		_statistics.call("set_description", text)

## 保留原文并按调用顺序换行追加，空追加不产生空行。
## 参数 text：额外描述；返回值：无。
func add_description(text: String) -> void:
	if text.is_empty():
		return
	var existing: String = str(_result.get("description", ""))
	set_description(existing + ("\n" if not existing.is_empty() else "") + text)

## 更新扩展统计，不触发奖励重算。
## 参数 data：玩法统计字典；返回值：无。
func set_statistics(data: Dictionary) -> void:
	_result["statistics"] = data.duplicate(true)
	_has_result = true
	if is_node_ready():
		_statistics.call("set_statistics", data)

## 查询当前面板容量；场景尚未就绪时也能读取结果默认值。
## 返回值：格子数量，默认 5。
func get_harvest_capacity() -> int:
	return maxi(int(_result.get("capacity", 5)), 0)

## 刷新容量展示，供未来局外升级的显示接入，不写入永久容量。
## 参数 capacity：格子数量；返回值：没有遮蔽已有收获时为 true。
func refresh_harvest_capacity(capacity: int) -> bool:
	var harvest: Variant = _result.get("harvest", [])
	if capacity < 0 or (harvest is Array and capacity < (harvest as Array).size()):
		return false
	_result["capacity"] = capacity
	_has_result = true
	if is_node_ready():
		return bool(_harvest.call("refresh_capacity", capacity))
	return true

## 请求离开结算页；处理中的重复请求和保存失败状态都会被拒绝。
## 参数 destination：menu 或 next_run；返回值：请求已提交时为 true。
func request_navigation(destination: String) -> bool:
	if destination not in ["menu", "next_run"] or _navigation_pending or not str(_result.get("error", "")).is_empty():
		return false
	_navigation_pending = true
	_refresh_buttons()
	if not navigation_requested.get_connections().is_empty():
		navigation_requested.emit(destination)
		return true
	if is_instance_valid(_manager) and _manager.has_method("navigate_to"):
		if bool(_manager.call("navigate_to", destination)):
			return true
	cancel_navigation()
	return false

## 导航被外部流程拒绝时恢复按钮，不能重发收获。
## 返回值：无。
func cancel_navigation() -> void:
	_navigation_pending = false
	_refresh_buttons()

func _refresh_result() -> void:
	var harvest: Variant = _result.get("harvest", [])
	_harvest.call("bind_result", harvest if harvest is Array else [], get_harvest_capacity())
	_statistics.call("set_play_time", float(_result.get("duration_seconds", 0.0)))
	_statistics.call("set_ending", str(_result.get("ending_id", "")), str(_result.get("ending_title", "")))
	_statistics.call("set_description", str(_result.get("description", "")))
	var statistics: Variant = _result.get("statistics", {})
	_statistics.call("set_statistics", statistics if statistics is Dictionary else {})
	_refresh_buttons()

func _refresh_buttons() -> void:
	if is_node_ready():
		_buttons.call("set_navigation_state", _navigation_pending, str(_result.get("error", "")))

func _on_retry_requested() -> void:
	if _navigation_pending or not is_instance_valid(_manager) or not _manager.has_method("retry_persistence"):
		return
	_navigation_pending = true
	_refresh_buttons()
	# 重试仅委托经理保存已有结果，不能再次计算或注入奖励。
	_manager.call("retry_persistence")
	if _manager.has_method("get_last_result"):
		var result: Variant = _manager.call("get_last_result")
		if result is Dictionary:
			set_result(result)
	cancel_navigation()

func _exit_tree() -> void:
	var callback := Callable(self, "set_result")
	if is_instance_valid(_manager) and _manager.has_signal("settlement_ready") and _manager.is_connected("settlement_ready", callback):
		_manager.disconnect("settlement_ready", callback)
