extends RefCounted

## 一局游戏的纯内存账本；不访问节点、存档或界面。
## 创建时传入本局编号和开局容量，收获采用生产 ItemStack 协议。
const STACK: GDScript = preload("res://resources/item/item_stack.gd")
const ITEM_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")

var run_id: String = ""
var capacity: int = 5
var duration_seconds: float = 0.0
var statistics: Dictionary = {}
var description: String = ""
var ended: bool = false
var _harvest: Array = []


## 参数 id 为唯一局编号，slot_capacity 为开局格数；无返回值。
func _init(id: String = "", slot_capacity: int = 5) -> void:
	run_id = id
	capacity = maxi(5, slot_capacity)


## 参数 seconds 为活跃秒数增量；结束后忽略，返回值无。
func advance_time(seconds: float) -> void:
	if not ended:
		duration_seconds += maxf(0.0, seconds)


## 参数 key 为统计名称，delta 为整数增量；返回是否记录成功。
func record_statistic(key: String, delta: int = 1) -> bool:
	if ended or key.is_empty():
		return false
	statistics[key] = int(statistics.get(key, 0)) + delta
	return true


## 参数 text 为完整描述；结束后拒绝修改，返回值无。
func set_description(text: String) -> void:
	if not ended:
		description = text


## 参数 text 为追加的一条描述；非空原文自动换行，返回值无。
func add_description(text: String) -> void:
	if ended or text.is_empty():
		return
	description += ("\n" if not description.is_empty() else "") + text


## 参数 item、amount、rolled 为物品、正数量、洗炼属性；返回能否完整容纳。
func can_add_harvest(item: Resource, amount: int, rolled: Dictionary = {}) -> bool:
	if ended or item == null or amount <= 0:
		return false
	var maximum: int = int(ITEM_COMPAT.call("get_max_stack_size", item, 99))
	if maximum <= 0:
		return false
	var space: int = (capacity - _harvest.size()) * maximum
	for stack: RefCounted in _harvest:
		if stack.get("Item") == item and stack.get("RolledAttributes") == rolled:
			space += maxi(0, maximum - int(stack.get("Amount")))
	return space >= amount


## 统一添加真实收获；参数为物品、数量、洗炼属性，返回成功与否。
## 先整体校验，空间不足时不产生部分奖励。
func add_harvest_item(item: Resource, amount: int, rolled: Dictionary = {}) -> bool:
	if not can_add_harvest(item, amount, rolled):
		return false
	var remaining: int = amount
	for stack: RefCounted in _harvest:
		if stack.get("Item") == item and stack.get("RolledAttributes") == rolled:
			remaining = int(stack.call("Add", remaining))
			if remaining == 0:
				return true
	var maximum: int = int(ITEM_COMPAT.call("get_max_stack_size", item, 99))
	while remaining > 0:
		var stack: RefCounted = STACK.new()
		var count: int = mini(maximum, remaining)
		stack.call("SetItem", item, count)
		stack.set("RolledAttributes", rolled.duplicate(true))
		_harvest.append(stack)
		remaining -= count
	return true


## 取消已归还来源的收获；参数为物品、数量、属性，返回是否足量移除。
func remove_harvest_item(item: Resource, amount: int, rolled: Dictionary = {}) -> bool:
	if ended or amount <= 0:
		return false
	var available: int = 0
	for stack: RefCounted in _harvest:
		if stack.get("Item") == item and stack.get("RolledAttributes") == rolled:
			available += int(stack.get("Amount"))
	if available < amount:
		return false
	var remaining: int = amount
	for index: int in range(_harvest.size() - 1, -1, -1):
		var stack: RefCounted = _harvest[index]
		if stack.get("Item") != item or stack.get("RolledAttributes") != rolled:
			continue
		var count: int = int(stack.get("Amount"))
		var taken: int = mini(count, remaining)
		stack.set("Amount", count - taken)
		remaining -= taken
		if count == taken:
			_harvest.remove_at(index)
		if remaining == 0:
			break
	return true


## 无参数；返回独立的真实堆叠副本，物品资源身份不变。
func get_harvest() -> Array:
	var copies: Array = []
	for stack: RefCounted in _harvest:
		copies.append(stack.call("Duplicate"))
	return copies


## 无参数；返回当前空收获格数量，堆叠内空间由 can_add_harvest 查询。
func get_remaining_slots() -> int:
	return capacity - _harvest.size()
