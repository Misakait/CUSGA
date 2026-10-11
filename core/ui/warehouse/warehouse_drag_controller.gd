extends RefCounted

## 仓库数量拖拽的会话状态机：剩余数量、右键连续放置计时、目标解析与拖动预览。
##
## 会话只存在于内存，并且**不在拖动开始时从权威取走物品**：来源物品在每次实际放置前
## 一直留在原权威位置，所以取消（无效目标、失焦、退出场景）必然无损。
## 本类没有 _process，由根控制器每帧调用 tick(delta)，便于单元测试精确控制时间推进。
const ITEM_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")

## 单帧连续放置的安全阀：掉帧或时间推进过大时不允许一次放置无限多个。
const MAX_PLACEMENTS_PER_TICK: int = 60

## 拖动模式：未选中按整组、已选中按拆半。用 StringName 常量而非枚举，保持载荷可序列化。
const MODE_FULL: StringName = &"full"
const MODE_HALF: StringName = &"half"

var _host: Node
var _transfer: RefCounted
var _resolver: Callable = Callable()
var _initial_rate: float = 4.0
var _acceleration: float = 8.0
var _max_rate: float = 30.0

var _active: bool = false
var _side: StringName = &""
var _index: int = -1
var _mode: StringName = MODE_FULL
var _data: Dictionary = {}
var _remaining: int = 0
var _hold_time: float = 0.0
var _accumulator: float = 0.0
var _auto: bool = false
var _token: int = 0
var _next_token: int = 0
var _preview: Control
var _preview_label: Label

## 绑定宿主、传输层与目标解析。参数 host 为根控制器（须提供 commit_placement /
## commit_group_drop / refresh_slot / set_drag_session_active）、transfer 为
## warehouse_transfer 实例、resolver 为无参 Callable（返回 [side, index] 或 []）；返回无。
func bind(host: Node, transfer: RefCounted, resolver: Callable) -> void:
	_host = host
	_transfer = transfer
	_resolver = resolver

## 设置连续放置速率。三个参数单位均为“个/秒”，acceleration 为“个/秒²”；返回无。
func set_rates(initial: float, acceleration: float, maximum: float) -> void:
	_initial_rate = initial
	_acceleration = acceleration
	_max_rate = maximum

## 是否处于拖动会话；返回布尔。
func is_active() -> bool:
	return _active

## 当前剩余可放置数量；返回整数，无会话时返回 0。
func remaining() -> int:
	return _remaining

## 开始会话。参数 side/index 为来源、selected 为按下前的持续选中态；
## 返回拖动载荷字典；不能拖动（空槽或无物品）时返回 {}。
func begin(side: StringName, index: int, selected: bool) -> Dictionary:
	cancel()
	if _transfer == null or not is_instance_valid(_host):
		return {}
	var data: Dictionary = _transfer.call("snapshot", side, index)
	var item: Resource = data.get("item") as Resource
	var amount: int = int(data.get("amount", 0))
	if item == null or amount <= 0:
		return {}
	# 选中的格子只拖一半并向上取整；数量 1 时 ceil(1 / 2) = 1，因此照常拖走这 1 个。
	# amount 在上方已保证 ≥ 1，向上取整的结果不会小于 1，所以不需要「结果不足 1」的兜底分支。
	var requested: int = amount if not selected else ceili(float(amount) / 2.0)
	_next_token += 1
	_token = _next_token
	_active = true
	_side = side
	_index = index
	_mode = MODE_HALF if selected else MODE_FULL
	_remaining = requested
	_auto = false
	_hold_time = 0.0
	_accumulator = 0.0
	_preview = null
	_preview_label = null
	# 令牌与宿主身份写进载荷：别的界面或上一轮拖动的过期字典必须在提交时被拒绝。
	data.merge({
		"side": side,
		"index": index,
		"owner": _host.get_instance_id(),
		"token": _token,
	})
	_data = data
	_host.call("set_drag_session_active", true)
	return data

## 构建拖动预览（含剩余数量）。参数 item 为来源物品；返回 Control，宿主用 set_drag_preview 使用。
func create_preview(item: Resource) -> Control:
	var preview := Control.new()
	preview.custom_minimum_size = Vector2(56, 56)
	preview.size = Vector2(56, 56)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = ITEM_COMPAT.call("get_display_icon", item, null) as Texture2D
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(icon)
	var label := Label.new()
	# 数字固定贴在右下角，避免和格子图标主体重叠。
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(label)
	_preview = preview
	_preview_label = label
	_refresh_preview()
	return preview

## 预检目标。参数 data 为载荷、side/index 为目标；返回布尔。
## full 模式沿用整组交换规则；half 模式只接受空格或同类未满格。
func can_drop(data: Dictionary, side: StringName, index: int) -> bool:
	if not _is_payload_current(data) or _remaining <= 0:
		return false
	if _mode == MODE_FULL:
		return bool(_transfer.call("can_move", data, side, index))
	return bool(_transfer.call("can_receive_amount", data, side, index, _remaining))

## 提交剩余数量并结束会话。参数 data/side/index 同上；返回是否发生移动。
func drop(data: Dictionary, side: StringName, index: int) -> bool:
	if not can_drop(data, side, index):
		return false
	var source_side: StringName = _side
	var source_index: int = _index
	var moved: bool = false
	if _mode == MODE_FULL:
		moved = bool(_host.call("commit_group_drop", data, side, index))
	else:
		moved = int(_host.call("commit_placement", data, side, index, _remaining)) > 0
	if not moved:
		return false
	_host.call("refresh_slot", source_side, source_index)
	_host.call("refresh_slot", side, index)
	cancel()
	return true

## 处理右键按下：先在鼠标下的格子放 1 个，再开始连续放置计时。返回是否消费事件。
func press_secondary() -> bool:
	if not _active or _remaining <= 0:
		return false
	# Godot 不重复派发「按下」，这里再挡一次重复事件：重复按下不得重置加速计时或多放一个。
	if _auto:
		return true
	if not _resolver.is_valid():
		return false
	var target: Array = _resolver.call()
	if target.size() < 2:
		return false
	var side: StringName = StringName(target[0])
	var index: int = int(target[1])
	# 来源格自身不是有效目标，避免右键把自己原地搬一遍。
	if side == _side and index == _index:
		return false
	if not _place_one(side, index):
		return false
	_hold_time = 0.0
	_accumulator = 0.0
	_auto = true
	return true

## 处理右键松开：停止连续放置（不结束会话）。返回无。
func release_secondary() -> void:
	_auto = false
	_hold_time = 0.0
	_accumulator = 0.0

## 每帧推进连续放置。参数 delta 为秒；返回无。
func tick(delta: float) -> void:
	if not _active or not _auto or delta <= 0.0 or not _resolver.is_valid():
		return
	_hold_time += delta
	_accumulator += delta
	var guard: int = 0
	while guard < MAX_PLACEMENTS_PER_TICK:
		var interval: float = _interval_at(_hold_time)
		if interval == INF or _accumulator < interval:
			break
		guard += 1
		var target: Array = _resolver.call()
		if target.size() < 2:
			break
		var side: StringName = StringName(target[0])
		var index: int = int(target[1])
		if not _place_one(side, index):
			# 目标暂时不接受只结束本轮循环，不结束连续放置：玩家可以滑到别的格子继续。
			# 同时把帧间余量压到最多一个间隔，避免「无效目标期间攒下的时间」在滑到有效
			# 目标时一次性爆发成几十个。
			_accumulator = minf(_accumulator, interval)
			break
		_accumulator -= interval
		if not _active or not _auto:
			break

## 左键释放后的收尾（由根控制器延迟调用），未投放时丢弃剩余并结束会话。返回无。
func finish_after_release() -> void:
	if _active:
		cancel()

## 立即结束并丢弃会话（幂等）。返回无。
func cancel() -> void:
	var was_active: bool = _active
	_active = false
	_side = &""
	_index = -1
	_mode = MODE_FULL
	_data = {}
	_remaining = 0
	_hold_time = 0.0
	_accumulator = 0.0
	_auto = false
	_token = 0
	_preview = null
	_preview_label = null
	if was_active and is_instance_valid(_host):
		_host.call("set_drag_session_active", false)

## 放置一次到目标。参数 side/index 为目标；返回是否真的放下一个。
func _place_one(side: StringName, index: int) -> bool:
	if not _active or _remaining <= 0:
		return false
	if side == _side and index == _index:
		return false
	# 提交前比对来源快照：外部改过库存时立刻结束会话，不再用过期数据继续放置。
	var fresh: Dictionary = _transfer.call("snapshot", _side, _index)
	if fresh.get("item") != _data.get("item") \
			or int(fresh.get("amount", 0)) != int(_data.get("amount", 0)) \
			or fresh.get("rolled") != _data.get("rolled"):
		cancel()
		return false
	var moved: int = int(_host.call("commit_placement", _data, side, index, 1))
	if moved < 1:
		return false
	_remaining = maxi(_remaining - moved, 0)
	_resync_source()
	_refresh_preview()
	_host.call("refresh_slot", _side, _index)
	_host.call("refresh_slot", side, index)
	if _remaining <= 0:
		# 余量放完就停止连续放置，但会话保留到左键释放，预览继续显示 0。
		_auto = false
	return true

## 重取来源快照的数量与洗炼属性，保持「data.amount 等于来源权威数量」的不变式。
func _resync_source() -> void:
	var fresh: Dictionary = _transfer.call("snapshot", _side, _index)
	_data["amount"] = int(fresh.get("amount", 0))
	_data["rolled"] = fresh.get("rolled")

## 载荷是否属于当前会话：令牌与宿主身份都对得上才算有效。
func _is_payload_current(data: Dictionary) -> bool:
	if not _active or _transfer == null or not is_instance_valid(_host):
		return false
	if not data.has("token") or not data.has("owner"):
		return false
	return int(data.get("token", -1)) == _token and int(data.get("owner", 0)) == _host.get_instance_id()

## 刷新预览上的剩余数量。返回无。
func _refresh_preview() -> void:
	if _preview_label == null or not is_instance_valid(_preview_label):
		return
	_preview_label.text = "x%d" % _remaining

## 计算右键按下 t 秒后的连续放置速率（个/秒）；结果不足 0 时按 0 处理（不放置）。
func _rate_at(t: float) -> float:
	return maxf(0.0, minf(_max_rate, _initial_rate + _acceleration * t))

## 计算当前速率下两次放置的间隔秒数；速率为 0 时返回无穷大，表示不再自动放置。
func _interval_at(t: float) -> float:
	var rate: float = _rate_at(t)
	return 1.0 / rate if rate > 0.0 else INF
