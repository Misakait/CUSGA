extends RefCounted

## 局外玩家档案的纯数据模型；不访问节点、界面或磁盘。
## 金币及升级由旧适配入口读写同一对象，额外字段由存档层统一编解码。
const STACK_SCRIPT: GDScript = preload("res://resources/item/item_stack.gd")
const SLOT_CODEC: GDScript = preload("res://core/save/save_slot_codec.gd")

## 当前金币，默认 1200；合法范围由钱包适配入口校验。
var gold: int = 1200
## 独立轮回代币余额，不改变现有商店金币含义。
var tokens: int = 0
## 永久升级项；旧容量升级保留原存档键。
var upgrade_levels: Dictionary = {"warehouse_level": 0, "carry_level": 0}
var _harvest_capacity: int = 5
var _settled_run_ids: Dictionary = {}
var _pending_harvest: Array = []

## 查询局外收获容量。无参数；返回当前格子数量。
func get_harvest_capacity() -> int:
	return _harvest_capacity

## 设置未来升级后的容量。参数 capacity 为格子数；小于 5 时不修改并返回 false。
func set_harvest_capacity(capacity: int) -> bool:
	if capacity < 5:
		return false
	_harvest_capacity = capacity
	return true

## 查询一局是否已经入账。参数 run_id 为稳定局编号；返回是否已经标记。
func has_settled_run(run_id: String) -> bool:
	return _settled_run_ids.has(run_id)

## 标记一次入账。参数 run_id 为非空局编号；无返回值，重复标记不会重复添加。
func mark_run_settled(run_id: String) -> void:
	if not run_id.is_empty():
		_settled_run_ids[run_id] = true

## 累加轮回代币。参数 amount 必须为正数；无返回值，非正数忽略。
func add_tokens(amount: int) -> void:
	if amount > 0:
		# 先收窄增量再相加，避免极大规则输入在取上限之前溢出为负数。
		tokens = mini(2147483647, tokens + mini(amount, 2147483647))

## 保存未能入仓的收获。参数 stacks 为真实物品堆叠数组；无返回值，保存隔离副本。
func add_pending_harvest(stacks: Array) -> void:
	_pending_harvest.append_array(_copy_stacks(stacks))

## 读取待领取收获。无参数；返回堆叠深复制，资源身份保持不变。
func get_pending_harvest() -> Array:
	return _copy_stacks(_pending_harvest)

## 替换待领取收获。参数 stacks 为领取后剩余堆叠；无返回值。
func replace_pending_harvest(stacks: Array) -> void:
	_pending_harvest = _copy_stacks(stacks)

## 编码新增档案字段。无参数；返回可写入 JSON 的字典，旧金币和容量等级仍由旧键保存。
func capture_extra_data() -> Dictionary:
	var entries: Array = []
	for stack: Variant in _pending_harvest:
		entries.append(SLOT_CODEC.call("stack_to_entry", stack))
	# 两个旧等级只由旧存档键保存，避免同一值出现两个真相来源。
	var future_levels: Dictionary = upgrade_levels.duplicate(true)
	future_levels.erase("warehouse_level")
	future_levels.erase("carry_level")
	return {
		"tokens": tokens,
		"upgrade_levels": future_levels,
		"harvest_capacity": _harvest_capacity,
		"settled_run_ids": _settled_run_ids.keys(),
		"pending_harvest": SLOT_CODEC.call("encode_slots", entries),
	}

## 水合新增字段。参数 data 为档案载荷，lookup 为物品编号查表函数；返回是否完成水合。
## 旧钱包及容量等级由各自适配入口覆盖，本方法只替换新增字段。
func apply_extra_data(data: Dictionary, lookup: Callable) -> bool:
	tokens = _nonnegative(data.get("tokens", 0), 0)
	_harvest_capacity = maxi(5, _nonnegative(data.get("harvest_capacity", 5), 5))
	var warehouse_level: int = int(upgrade_levels.get("warehouse_level", 0))
	var carry_level: int = int(upgrade_levels.get("carry_level", 0))
	upgrade_levels = {"warehouse_level": warehouse_level, "carry_level": carry_level}
	var raw_levels: Variant = data.get("upgrade_levels", {})
	if raw_levels is Dictionary:
		for key: Variant in raw_levels:
			if key is String and key not in ["warehouse_level", "carry_level"]:
				upgrade_levels[key] = _nonnegative(raw_levels[key], 0)
	_settled_run_ids.clear()
	var ids: Variant = data.get("settled_run_ids", [])
	if ids is Array:
		for id: Variant in ids:
			if id is String and not String(id).is_empty():
				_settled_run_ids[id] = true
	_pending_harvest.clear()
	var decoded: Dictionary = SLOT_CODEC.call("decode_slots", data.get("pending_harvest", []), 0, lookup)
	for entry: Dictionary in decoded.get("entries", []):
		if String(entry.get("status", "")) != "ok":
			continue
		var stack: RefCounted = STACK_SCRIPT.new()
		stack.call("SetItem", entry.get("item"), int(entry.get("amount", 0)))
		stack.set("RolledAttributes", (entry.get("rolled", {}) as Dictionary).duplicate(true))
		_pending_harvest.append(stack)
	if int(decoded.get("skipped", 0)) > 0:
		push_warning("PlayerProfile: 部分待领取物品无法恢复：%s" % str(decoded.get("reasons", [])))
	return true


func _copy_stacks(stacks: Array) -> Array:
	var copied: Array = []
	for raw: Variant in stacks:
		if not is_instance_valid(raw) or not (raw is Object) or not raw.has_method("Duplicate"):
			continue
		if bool(raw.get("IsEmpty")):
			continue
		copied.append(raw.call("Duplicate"))
	return copied


func _nonnegative(raw: Variant, fallback: int) -> int:
	if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
		return fallback
	return clampi(int(raw), 0, 2147483647)
