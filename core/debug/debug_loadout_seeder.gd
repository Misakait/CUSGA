extends Node

## 把 Debug 开局配置应用到玩家现有组件。
##
## Seeder 只依赖稳定节点路径、属性名和 PascalCase 方法协议，因此可同时驱动当前 C#
## 生产组件和后续 GDScript 组件；物品、装备和属性规则仍由各自组件负责。

## 旧 EquipmentSlot 枚举共有 16 个连续值，清空装备时必须全部遍历。
const EQUIPMENT_SLOT_COUNT: int = 16

## 是否允许该 Seeder 执行。
@export var Enabled: bool = true

## 是否仅在 Debug 构建中执行。
@export var DebugBuildOnly: bool = true

## 是否只允许成功应用一次。
@export var ApplyOnce: bool = true

## 应用配置前是否清空玩家背包。
@export var ClearInventoryBeforeApply: bool = true

## 应用配置前是否清空出战卡组。
@export var ClearBattleDeckBeforeApply: bool = true

## 应用配置前是否卸下全部装备。
@export var ClearEquipmentBeforeApply: bool = true

## 相对于 Seeder 的玩家节点路径。
@export var PlayerPath: NodePath = NodePath("../Player")

## 待应用的 Debug 开局配置资源。
@export var Loadout: Resource

## 当前节点是否已经成功应用过配置。
var _has_applied: bool = false


## 在满足构建和启用条件时延迟应用配置。
## 返回值：无。
func _ready() -> void:
	if not Enabled or (DebugBuildOnly and not OS.is_debug_build()):
		return
	call_deferred("ApplyLoadout")


## 按旧实现顺序清理并填充玩家属性、装备、背包与出战卡组。
## 返回值：无。
func ApplyLoadout() -> void:
	if ApplyOnce and _has_applied:
		return
	if Loadout == null:
		push_warning("DebugLoadoutSeeder has no loadout assigned.")
		return

	## 配置目标玩家节点。
	var player := get_node_or_null(PlayerPath)
	if player == null:
		push_warning("DebugLoadoutSeeder could not find Player.")
		return

	## 玩家固定路径下的库存组件，是应用配置的必需目标。
	var inventory := player.get_node_or_null("Components/InventoryComponent")
	## 玩家固定路径下的出战卡组组件，缺失时只跳过卡组配置。
	var battle_deck := player.get_node_or_null("Components/BattleDeckComponent")
	## 玩家固定路径下的装备组件，缺失时只跳过装备配置。
	var equipment := player.get_node_or_null("Components/EquipmentComponent")
	## 玩家固定路径下的属性组件，已有初始数据时不得被覆盖。
	var attributes := player.get_node_or_null("Components/AttributeComponent")
	if inventory == null:
		push_warning("DebugLoadoutSeeder could not find InventoryComponent.")
		return

	## 调试配置中可选的玩家初始属性资源。
	var starting_stats := Loadout.get("PlayerStartingStats") as Resource
	if starting_stats != null and attributes != null and attributes.get("InitialData") == null:
		print("[Seeder] PlayerStartingStats", starting_stats)
		attributes.call("InitializeWithData", starting_stats)

	if ClearEquipmentBeforeApply and equipment != null:
		_clear_equipment(equipment)
	if ClearInventoryBeforeApply:
		_clear_inventory(inventory)
	if ClearBattleDeckBeforeApply and battle_deck != null:
		_clear_inventory(battle_deck)

	_fill_inventory(inventory, _read_entries(&"InventoryItems"))
	_fill_inventory(inventory, _read_entries(&"InventoryEquipment"))
	if battle_deck != null:
		_fill_inventory(battle_deck, _read_entries(&"BattleDeckItems"))
	if equipment != null:
		_equip_generated_equipment(equipment, _read_entries(&"EquippedEquipment"))

	_has_applied = true


## 从配置读取兼容条目数组。
## 参数 property_name：DebugLoadoutData 上的稳定 PascalCase 字段名。
## 返回值：字段为数组时返回原数组，否则返回空数组。
func _read_entries(property_name: StringName) -> Array:
	## 配置字段可能来自 C# 或 GDScript Resource。
	var entries: Variant = Loadout.get(property_name)
	if entries is Array:
		return entries
	return []


## 把条目生成的堆叠依次放入第一个空槽。
## 参数 inventory：实现生产库存稳定协议的组件。
## 参数 entries：提供 CreateStack 方法的调试条目数组。
## 返回值：无。
func _fill_inventory(inventory: Node, entries: Array) -> void:
	for entry_value: Variant in entries:
		## 允许迁移期间数组中同时存在 C# 和 GDScript Resource。
		var entry := entry_value as Resource
		if entry == null or not entry.has_method("CreateStack"):
			continue
		## 条目创建的生产兼容堆叠。
		var stack := entry.call("CreateStack") as RefCounted
		_add_stack_to_first_available_slot(inventory, stack)


## 生成条目并装备到其声明的槽位。
## 参数 equipment：实现生产装备稳定协议的组件。
## 参数 entries：提供 CreateStack 与 Slot 的装备条目数组。
## 返回值：无。
func _equip_generated_equipment(equipment: Node, entries: Array) -> void:
	for entry_value: Variant in entries:
		## 允许迁移期间数组中同时存在 C# 和 GDScript Resource。
		var entry := entry_value as Resource
		if entry == null or not entry.has_method("CreateStack"):
			continue
		## 条目创建的生产兼容装备堆叠。
		var stack := entry.call("CreateStack") as RefCounted
		if stack == null:
			continue
		equipment.call("Equip", stack, int(entry.get("Slot")))


## 把非空堆叠写入库存的第一个空槽。
## 参数 inventory：实现 Capacity、GetStackAt 与 TrySetStackAt 的组件。
## 参数 stack：旧 C# 或未来 GDScript ItemStack。
## 返回值：无。
func _add_stack_to_first_available_slot(inventory: Node, stack: RefCounted) -> void:
	if stack == null or bool(stack.get("IsEmpty")):
		return

	## 库存当前可访问的槽位数量。
	var capacity: int = int(inventory.get("Capacity"))
	for index: int in range(capacity):
		## 当前槽位堆叠用于判断是否可直接写入。
		var current_stack := inventory.call("GetStackAt", index) as RefCounted
		if current_stack != null and not bool(current_stack.get("IsEmpty")):
			continue
		if bool(inventory.call("TrySetStackAt", index, stack)):
			return

	## 写满时的警告沿用旧实现，方便定位具体物品和目标库存。
	var item := stack.get("Item") as Resource
	## 空物品使用安全占位名，避免调试警告自身触发错误。
	var item_name: String = "<unknown>" if item == null else str(item.get("CardName"))
	push_warning("Debug loadout could not fit item '%s' into %s." % [item_name, inventory.name])


## 清空库存的全部现有槽位。
## 参数 inventory：实现 Capacity 与 TryClearStackAt 的组件。
## 返回值：无。
func _clear_inventory(inventory: Node) -> void:
	## 清理开始时记录容量，保持与旧实现同一次遍历的边界一致。
	var capacity: int = int(inventory.get("Capacity"))
	for index: int in range(capacity):
		inventory.call("TryClearStackAt", index)


## 依次卸下旧 EquipmentSlot 的全部槽位。
## 参数 equipment：实现 Unequip 的装备组件。
## 返回值：无。
func _clear_equipment(equipment: Node) -> void:
	for slot: int in range(EQUIPMENT_SLOT_COUNT):
		equipment.call("Unequip", slot)
