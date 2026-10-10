extends RefCounted

## 单次出售的来源槽位适配器，只向原交易服务暴露被拖入的堆叠。
const STACK: GDScript = preload("res://resources/item/item_stack.gd")
const GET_STACK: StringName = &"GetStackAt"
const SET_STACK: StringName = &"TrySetStackAt"

var _inventory: Node
var _source: Dictionary = {}

## 注入本次交易来源。参数 inventory 为原库存，source 为槽位快照；返回无。
func bind(inventory: Node, source: Dictionary) -> void:
	_inventory = inventory
	_source = source.duplicate(true)

## 获取来源快照。参数 inventory 为库存、index 为槽位；返回身份、数量及独立属性，非法位置返回空。
static func snapshot(inventory: Node, index: int) -> Dictionary:
	if not is_instance_valid(inventory) or not inventory.has_method(GET_STACK):
		return {}
	var capacity: Variant = inventory.get("Capacity")
	if not capacity is int or index < 0 or index >= int(capacity):
		return {}
	var raw: Variant = inventory.call(GET_STACK, index)
	if not raw is Object or not is_instance_valid(raw):
		return {}
	var stack: Object = raw as Object
	var rolled: Variant = stack.get("RolledAttributes")
	if not rolled is Dictionary:
		return {}
	return {"index": index, "stack_id": stack.get_instance_id(), "item": stack.get("Item"), "amount": int(stack.get("Amount")), "rolled": (rolled as Dictionary).duplicate(true)}

## 判断来源仍相同。参数 inventory 为库存、source 为快照；返回槽位身份、资源、数量和属性均未变更。
static func matches(inventory: Node, source: Dictionary) -> bool:
	if not source.get("index") is int or not source.get("stack_id") is int:
		return false
	if not source.get("item") is Resource or not source.get("amount") is int or not source.get("rolled") is Dictionary:
		return false
	if int(source["amount"]) <= 0:
		return false
	var current: Dictionary = snapshot(inventory, int(source["index"]))
	return not current.is_empty() and current.get("stack_id") == source["stack_id"] and current.get("item") == source["item"] and current.get("amount") == source["amount"] and current.get("rolled") == source["rolled"]

## 校验商店拖动身份。参数 inventory/source 为库存与载荷、owner/session 为当前界面及进入次数；返回是否可接受。
static func valid_payload(inventory: Node, source: Dictionary, owner: int, session: int) -> bool:
	return source.get("owner") is int and source.get("session") is int and source.get("owner") == owner and source.get("session") == session and source.get("side") == &"warehouse" and matches(inventory, source)

## 提供原服务的持有量协议。参数 item 为待售资源；返回有效来源槽位的数量，过期来源返回 0。
func ItemCnt(item: Resource) -> int:
	return int(_source["amount"]) if item == _source.get("item") and matches(_inventory, _source) else 0

## 提供原服务的移除协议。参数 item 为资源、quantity 为整笔数量；返回成功与否，失败无副作用。
func TryRemoveItem(item: Resource, quantity: int) -> bool:
	if quantity <= 0 or quantity > ItemCnt(item) or not _inventory.has_method(SET_STACK):
		return false
	var remainder: int = int(_source["amount"]) - quantity
	var replacement: RefCounted = STACK.new()
	replacement.call("SetItem", item, remainder)
	# SetItem 会清空属性，剩余物品必须随后恢复原属性，避免随机装备身份漂移。
	if remainder > 0:
		replacement.set("RolledAttributes", (_source["rolled"] as Dictionary).duplicate(true))
	return bool(_inventory.call(SET_STACK, int(_source["index"]), replacement))
