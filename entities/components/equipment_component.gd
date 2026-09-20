extends Node

## 装备组件的 GDScript 生产实现。
##
## 本组件保持槽位移动、属性与标签结算、套装阶级、采集工具和火把倍率规则。
## 所有 Resource 字段通过兼容桥读取，使旧 C# 资产与 GDScript 资产可以参与同一套行为。

const EQUIPMENT_TYPES: GDScript = preload("res://core/constants/equipment_types.gd")
const ITEM_DATA_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")
const EQUIPMENT_DATA_COMPAT: GDScript = preload("res://resources/item/equipment/equipment_data_compat.gd")

## 装备拖拽来源标识；保持 C# TagConsts.SystemEquipment 的值。
const DragSourceSystem: StringName = &"SystemEquipment"

## 魔法物品槽使用的显式分类标签，不能用名称片段代替。
const MAGIC_ITEM_TAG: StringName = &"MagicItem"

## 所有合法装备槽位的数量；对应 EquipmentSlot 的 0..15。
const EQUIPMENT_SLOT_COUNT: int = 16

## 装备内容或效果发生变化时发出；保持旧 C# 无参数信号名称。
signal EquipmentChanged

## 游戏中可用于套装结算的全部套装配置。
@export var AllSetDatabase: Array[Resource] = []

## 有效火把在夜晚遭遇计算中使用的概率乘数；运行时限制到 0..1。
@export_range(0.0, 1.0, 0.05) var TorchNightEncounterChanceMultiplier: float = 0.5

## 当前每个装备槽保存的独立 ItemStack 副本，键为 EquipmentSlot 整数值。
var _equipped_items: Dictionary = {}

## 同级属性组件；装备和套装效果通过稳定方法名写入。
var _attribute_component: Node = null

## 同级标签组件；装备和套装标签通过稳定方法名增减层数。
var _tag_component: Node = null

## 当前已经应用的套装阶级，用于下次重算前精确撤销旧效果。
var _active_set_tiers: Array[Resource] = []


## 节点进入场景树时解析同级属性与标签组件。
func _ready() -> void:
	_attribute_component = get_parent().get_node("AttributeComponent")
	_tag_component = get_parent().get_node("TagComponent")


## 将物品装备到指定槽位。
## @param stack 旧 C# 或并行 GDScript ItemStack。
## @param slot EquipmentSlot 的稳定整数值。
## @return bool 装备成功时返回 true。
func Equip(stack: Variant, slot: int) -> bool:
	if not CanEquipStack(stack, slot):
		push_error("这件物品不能放在 %d 槽位！" % slot)
		return false

	if _equipped_items.has(slot):
		Unequip(slot)

	var duplicated_stack: Variant = _duplicate_stack(stack)
	if duplicated_stack == null:
		return false
	_equipped_items[slot] = duplicated_stack
	_apply_item_effects(duplicated_stack)
	_check_set_bonuses()
	EquipmentChanged.emit()
	return true


## 卸下指定槽位的装备并撤销其效果。
## @param slot EquipmentSlot 的稳定整数值。
func Unequip(slot: int) -> void:
	if not _equipped_items.has(slot):
		return
	var stack: Variant = _equipped_items[slot]
	_remove_item_effects(stack)
	_equipped_items.erase(slot)
	_check_set_bonuses()
	EquipmentChanged.emit()


## 读取指定槽位的装备堆叠。
## @param slot EquipmentSlot 的稳定整数值。
## @return Variant 已装备的 ItemStack；槽位为空时返回 null。
## @remarks 这是 C# out 参数查询在 GDScript 中的等价返回值边界。
func TryGetEquippedStack(slot: int) -> Variant:
	return GetEquippedStack(slot)


## 获取指定槽位当前装备的物品堆叠。
## @param slot EquipmentSlot 的稳定整数值。
## @return Variant 已装备的 ItemStack；槽位为空时返回 null。
## @remarks 保留旧 C# 为 GDScript 视图提供的无 out 参数兼容入口。
func GetEquippedStack(slot: int) -> Variant:
	return _equipped_items.get(slot)


## 判断一个堆叠能否放入指定装备槽。
## @param stack 旧 C# 或并行 GDScript ItemStack。
## @param slot EquipmentSlot 的稳定整数值。
## @return bool 显式槽位或旧标签兜底匹配时返回 true。
static func CanEquipStack(stack: Variant, slot: int) -> bool:
	if _stack_is_empty(stack):
		return false
	var item: Resource = _stack_item(stack)
	if bool(EQUIPMENT_DATA_COMPAT.call("is_equipment_resource", item)):
		var valid_slots: Array[int] = EQUIPMENT_DATA_COMPAT.call("get_valid_slots", item)
		if valid_slots.has(slot):
			return true
		# 只要设计资源显式配置了槽位，就不能再让旧名称兜底绕过配置。
		if not valid_slots.is_empty():
			return false
	return _can_equip_tagged_item(stack, slot)


## 判断能否从库存指定槽位装备到目标槽位。
## @param source_inventory 兼容 C# 或 GDScript InventoryComponent。
## @param from_index 库存来源索引。
## @param slot 目标 EquipmentSlot 整数值。
## @return bool 装备有效且被替换物能放回库存时返回 true。
func CanEquipFromInventory(source_inventory: Variant, from_index: int, slot: int) -> bool:
	if not _inventory_has_valid_index(source_inventory, from_index):
		return false
	var source_stack: Variant = source_inventory.call("GetStackAt", from_index)
	if not CanEquipStack(source_stack, slot):
		return false
	if not _equipped_items.has(slot):
		return true
	return _inventory_can_store(source_inventory, _stack_item(_equipped_items[slot]))


## 从库存指定槽位装备物品，原槽装备会以堆叠副本放回同一库存格。
## @param source_inventory 来源库存。
## @param from_index 来源索引。
## @param slot 目标 EquipmentSlot 整数值。
## @return bool 完整交换成功时返回 true。
func EquipFromInventory(source_inventory: Variant, from_index: int, slot: int) -> bool:
	if not CanEquipFromInventory(source_inventory, from_index, slot):
		return false
	var source_stack: Variant = source_inventory.call("GetStackAt", from_index)
	var new_equipment: Variant = _duplicate_stack(source_stack)
	var previous_equipment: Variant = null
	if _equipped_items.has(slot):
		previous_equipment = _duplicate_stack(_equipped_items[slot])
		Unequip(slot)

	if previous_equipment != null:
		source_inventory.call("TrySetStackAt", from_index, previous_equipment)
	else:
		source_inventory.call("TryClearStackAt", from_index)
	return Equip(new_equipment, slot)


## 从库存快速装备到最优槽位，优先空槽，再允许替换已有装备。
## @param source_inventory 来源库存。
## @param from_index 来源索引。
## @return bool 找到可用槽位并完成装备时返回 true。
func EquipFromInventoryToBestSlot(source_inventory: Variant, from_index: int) -> bool:
	if not _inventory_has_valid_index(source_inventory, from_index):
		return false
	var source_stack: Variant = source_inventory.call("GetStackAt", from_index)
	if _stack_is_empty(source_stack):
		return false
	var empty_slot: Variant = _find_best_inventory_equipment_slot(source_inventory, from_index, true)
	if empty_slot != null:
		return EquipFromInventory(source_inventory, from_index, int(empty_slot))
	var replacement_slot: Variant = _find_best_inventory_equipment_slot(source_inventory, from_index, false)
	return replacement_slot != null and EquipFromInventory(source_inventory, from_index, int(replacement_slot))


## 判断指定装备能否卸到库存目标格。
## @param slot 来源装备槽。
## @param target_inventory 目标库存。
## @param target_index 目标库存索引。
## @return bool 目标可接收装备且原目标物能反向装备时返回 true。
func CanUnequipToInventory(slot: int, target_inventory: Variant, target_index: int) -> bool:
	if not _equipped_items.has(slot) or not _inventory_has_valid_index(target_inventory, target_index):
		return false
	var equipped_stack: Variant = _equipped_items[slot]
	if not _inventory_can_store(target_inventory, _stack_item(equipped_stack)):
		return false
	var target_stack: Variant = target_inventory.call("GetStackAt", target_index)
	return _stack_is_empty(target_stack) or CanEquipStack(target_stack, slot)


## 把指定装备卸到库存目标格，必要时将原目标物装备回来源槽。
## @param slot 来源装备槽。
## @param target_inventory 目标库存。
## @param target_index 目标库存索引。
## @return bool 完整交换成功时返回 true。
func UnequipToInventory(slot: int, target_inventory: Variant, target_index: int) -> bool:
	if not CanUnequipToInventory(slot, target_inventory, target_index):
		return false
	var equipped_stack: Variant = _duplicate_stack(_equipped_items[slot])
	var target_stack: Variant = target_inventory.call("GetStackAt", target_index)
	var replacement_equipment: Variant = null if _stack_is_empty(target_stack) else _duplicate_stack(target_stack)
	Unequip(slot)
	target_inventory.call("TrySetStackAt", target_index, equipped_stack)
	if replacement_equipment != null:
		Equip(replacement_equipment, slot)
	return true


## 判断两个装备槽位能否互换。
## @param from_slot 来源槽。
## @param to_slot 目标槽。
## @return bool 来源装备和可选目标装备都适配交换后的槽位时返回 true。
func CanMoveEquipment(from_slot: int, to_slot: int) -> bool:
	if from_slot == to_slot or not _equipped_items.has(from_slot):
		return false
	var from_stack: Variant = _equipped_items[from_slot]
	if not CanEquipStack(from_stack, to_slot):
		return false
	return not _equipped_items.has(to_slot) or CanEquipStack(_equipped_items[to_slot], from_slot)


## 在两个装备槽之间移动或交换装备。
## @param from_slot 来源槽。
## @param to_slot 目标槽。
## @return bool 移动或交换成功时返回 true。
func MoveEquipment(from_slot: int, to_slot: int) -> bool:
	if not CanMoveEquipment(from_slot, to_slot):
		return false
	var from_stack: Variant = _duplicate_stack(_equipped_items[from_slot])
	var to_stack: Variant = null
	if _equipped_items.has(to_slot):
		to_stack = _duplicate_stack(_equipped_items[to_slot])
	Unequip(from_slot)
	if to_stack != null:
		Unequip(to_slot)
		Equip(to_stack, from_slot)
	Equip(from_stack, to_slot)
	return true


## 获取有效火把提供的夜晚遭遇概率乘数。
## @return float 火把槽无有效火把时为 1，否则为限制到 0..1 的配置值。
func GetNightEncounterChanceMultiplier() -> float:
	var torch_slot: int = int(EQUIPMENT_TYPES.EquipmentSlot.Torch)
	if not _equipped_items.has(torch_slot) or not _is_torch_stack(_equipped_items[torch_slot]):
		return 1.0
	return clampf(TorchNightEncounterChanceMultiplier, 0.0, 1.0)


## 汇总所有匹配采集标签的工具额外产量。
## @param gathering_tag 当前资源点的采集标签。
## @return int 所有匹配工具 YieldGrowth 的总和。
func GetGatheringYieldBonus(gathering_tag: StringName) -> int:
	var bonus: int = 0
	for stack in _equipped_items.values():
		var item: Resource = _stack_item(stack)
		if bool(EQUIPMENT_DATA_COMPAT.call("is_tool_resource", item)) \
				and EQUIPMENT_DATA_COMPAT.call("get_target_gathering_tag", item) == gathering_tag:
			bonus += int(EQUIPMENT_DATA_COMPAT.call("get_yield_growth", item))
	return bonus


## 读取指定槽位中匹配工具提供的采集时间减免。
## @param gathering_tag 当前资源点的采集标签。
## @param slot 资源点指定的有效工具槽位。
## @return int 非负时间减免；无匹配工具时返回 0。
func GetGatheringTimeReduction(gathering_tag: StringName, slot: int) -> int:
	if gathering_tag == null or gathering_tag.is_empty() or not _equipped_items.has(slot):
		return 0
	var item: Resource = _stack_item(_equipped_items[slot])
	if not bool(EQUIPMENT_DATA_COMPAT.call("is_tool_resource", item)):
		return 0
	if EQUIPMENT_DATA_COMPAT.call("get_target_gathering_tag", item) != gathering_tag:
		return 0
	return maxi(0, int(EQUIPMENT_DATA_COMPAT.call("get_gathering_time_reduction", item)))


## 寻找快速装备使用的第一个候选槽位。
func _find_best_inventory_equipment_slot(
	source_inventory: Variant,
	from_index: int,
	require_empty_slot: bool
) -> Variant:
	var source_stack: Variant = source_inventory.call("GetStackAt", from_index)
	for slot in _get_candidate_slots(source_stack):
		var is_empty: bool = not _equipped_items.has(slot)
		if is_empty != require_empty_slot:
			continue
		if CanEquipFromInventory(source_inventory, from_index, slot):
			return slot
	return null


## 按显式 ValidSlots 或旧标签兜底顺序生成候选槽位。
static func _get_candidate_slots(stack: Variant) -> Array[int]:
	var candidates: Array[int] = []
	var item: Resource = _stack_item(stack)
	if bool(EQUIPMENT_DATA_COMPAT.call("is_equipment_resource", item)):
		var explicit_slots: Array[int] = EQUIPMENT_DATA_COMPAT.call("get_valid_slots", item)
		if not explicit_slots.is_empty():
			for slot in explicit_slots:
				if not candidates.has(slot):
					candidates.append(slot)
			return candidates
	for slot in EQUIPMENT_SLOT_COUNT:
		if CanEquipStack(stack, slot):
			candidates.append(slot)
	return candidates


## 应用装备自身洗炼属性和 GrantedTags。
func _apply_item_effects(stack: Variant) -> void:
	var rolled_attributes: Dictionary = _stack_rolled_attributes(stack)
	for attribute_type in rolled_attributes:
		_attribute_component.call(
			"AddPermanentBonus",
			attribute_type,
			float(rolled_attributes[attribute_type]),
			self
		)
	var item: Resource = _stack_item(stack)
	for tag in EQUIPMENT_DATA_COMPAT.call("get_granted_tags", item):
		_tag_component.call("AddTag", tag)


## 撤销装备自身洗炼属性和 GrantedTags。
func _remove_item_effects(stack: Variant) -> void:
	var rolled_attributes: Dictionary = _stack_rolled_attributes(stack)
	for attribute_type in rolled_attributes:
		_attribute_component.call(
			"RemovePermanentBonus",
			attribute_type,
			float(rolled_attributes[attribute_type]),
			self
		)
	var item: Resource = _stack_item(stack)
	for tag in EQUIPMENT_DATA_COMPAT.call("get_granted_tags", item):
		_tag_component.call("RemoveTag", tag)


## 先撤销旧套装阶级，再根据当前装备重新统计并应用全部满足的阶级。
func _check_set_bonuses() -> void:
	_clear_active_set_bonuses()
	var set_counts: Dictionary = {}
	for stack in _equipped_items.values():
		var item: Resource = _stack_item(stack)
		if not bool(EQUIPMENT_DATA_COMPAT.call("is_equipment_resource", item)):
			continue
		var set_type: int = int(EQUIPMENT_DATA_COMPAT.call("get_set_type", item))
		if set_type == int(EQUIPMENT_TYPES.EquipmentSet.None):
			continue
		set_counts[set_type] = int(set_counts.get(set_type, 0)) + 1

	for set_type in set_counts:
		var set_data: Resource = _find_set_data(int(set_type))
		if set_data == null:
			continue
		var raw_tiers: Variant = set_data.get("Tiers")
		if not (raw_tiers is Array):
			continue
		for raw_tier in raw_tiers:
			if not (raw_tier is Resource):
				continue
			var tier: Resource = raw_tier as Resource
			if int(set_counts[set_type]) >= int(tier.get("RequiredPieces")):
				_apply_tier_effects(tier)
				_active_set_tiers.append(tier)


## 撤销所有已记录的套装阶级效果。
func _clear_active_set_bonuses() -> void:
	for tier in _active_set_tiers:
		_remove_tier_effects(tier)
	_active_set_tiers.clear()


## 按套装整数值寻找配置 Resource。
func _find_set_data(set_type: int) -> Resource:
	for data in AllSetDatabase:
		if data != null and int(data.get("SetType")) == set_type:
			return data
	return null


## 应用单个套装阶级的属性和标签效果。
func _apply_tier_effects(tier: Resource) -> void:
	var raw_bonuses: Variant = tier.get("AttributeBonuses")
	if raw_bonuses is Dictionary:
		for attribute_type in raw_bonuses:
			_attribute_component.call("AddPermanentBonus", attribute_type, float(raw_bonuses[attribute_type]), self)
	var raw_tags: Variant = tier.get("GrantedTags")
	if raw_tags is Array:
		for raw_tag in raw_tags:
			_tag_component.call("AddTag", StringName(raw_tag))


## 撤销单个套装阶级的属性和标签效果。
func _remove_tier_effects(tier: Resource) -> void:
	var raw_bonuses: Variant = tier.get("AttributeBonuses")
	if raw_bonuses is Dictionary:
		for attribute_type in raw_bonuses:
			_attribute_component.call("RemovePermanentBonus", attribute_type, float(raw_bonuses[attribute_type]), self)
	var raw_tags: Variant = tier.get("GrantedTags")
	if raw_tags is Array:
		for raw_tag in raw_tags:
			_tag_component.call("RemoveTag", StringName(raw_tag))


## 判断库存对象是否接受给定索引。
static func _inventory_has_valid_index(inventory: Variant, index: int) -> bool:
	return inventory != null \
		and inventory.has_method("IsValidSlotIndex") \
		and bool(inventory.call("IsValidSlotIndex", index))


## 判断库存对象是否接受指定 Item Resource。
static func _inventory_can_store(inventory: Variant, item: Resource) -> bool:
	return inventory != null \
		and inventory.has_method("CanStore") \
		and bool(inventory.call("CanStore", item))


## 读取堆叠的空状态。
static func _stack_is_empty(stack: Variant) -> bool:
	return stack == null or bool(stack.get("IsEmpty"))


## 读取堆叠中的原始 Item Resource 引用。
static func _stack_item(stack: Variant) -> Resource:
	return null if stack == null else stack.get("Item") as Resource


## 读取堆叠洗炼属性；缺失或类型错误时返回空字典。
static func _stack_rolled_attributes(stack: Variant) -> Dictionary:
	if stack == null:
		return {}
	var raw_attributes: Variant = stack.get("RolledAttributes")
	return raw_attributes as Dictionary if raw_attributes is Dictionary else {}


## 复制堆叠状态，同时保留同一 Item Resource 身份。
static func _duplicate_stack(stack: Variant) -> Variant:
	return null if stack == null or not stack.has_method("Duplicate") else stack.call("Duplicate")


## 按旧 CardId/ItemTags 名称片段规则判断槽位兼容性。
static func _can_equip_tagged_item(stack: Variant, slot: int) -> bool:
	match slot:
		EQUIPMENT_TYPES.EquipmentSlot.Helmet:
			return _has_any_identifier(stack, ["Helmet"])
		EQUIPMENT_TYPES.EquipmentSlot.Chest:
			return _has_any_identifier(stack, ["Breastplate", "Chest"])
		EQUIPMENT_TYPES.EquipmentSlot.Legs:
			return _has_any_identifier(stack, ["Legguard", "Legs"])
		EQUIPMENT_TYPES.EquipmentSlot.Boots:
			return _has_any_identifier(stack, ["Shoes", "Boots"])
		EQUIPMENT_TYPES.EquipmentSlot.Weapon:
			return _has_any_identifier(stack, ["Sword", "Weapon", "Truncheon", "Hammer", "Shovel"])
		EQUIPMENT_TYPES.EquipmentSlot.Axe:
			return _has_any_identifier(stack, ["Axe"])
		EQUIPMENT_TYPES.EquipmentSlot.Pickaxe:
			return _has_any_identifier(stack, ["Pickaxe"])
		EQUIPMENT_TYPES.EquipmentSlot.FishingRod:
			return _has_any_identifier(stack, ["FishingRod"])
		EQUIPMENT_TYPES.EquipmentSlot.LeftHandguard:
			return _has_any_identifier(stack, ["Handguard_left", "LeftHandguard"])
		EQUIPMENT_TYPES.EquipmentSlot.RightHandguard:
			return _has_any_identifier(stack, ["Handguard_right", "RightHandguard"])
		EQUIPMENT_TYPES.EquipmentSlot.Torch:
			return _is_torch_stack(stack)
		EQUIPMENT_TYPES.EquipmentSlot.Pendant:
			return _has_any_identifier(stack, ["Necklace", "Pendant"])
		EQUIPMENT_TYPES.EquipmentSlot.Ring1, EQUIPMENT_TYPES.EquipmentSlot.Ring2:
			return _has_any_identifier(stack, ["Ring"])
		EQUIPMENT_TYPES.EquipmentSlot.Belt:
			return _has_any_identifier(stack, ["Belt"])
		EQUIPMENT_TYPES.EquipmentSlot.MagicItem:
			return _has_exact_tag(stack, MAGIC_ITEM_TAG)
		_:
			return false


## 判断堆叠是否按旧标识规则代表火把。
static func _is_torch_stack(stack: Variant) -> bool:
	return _has_any_identifier(stack, ["flametorch", "torch"])


## 判断 ItemTags 是否包含指定精确标签。
static func _has_exact_tag(stack: Variant, expected_tag: StringName) -> bool:
	if _stack_is_empty(stack) or expected_tag == null or expected_tag.is_empty():
		return false
	return ITEM_DATA_COMPAT.call("get_item_tags", _stack_item(stack)).has(expected_tag)


## 依次检查 CardId 和 ItemTags 是否包含任一忽略大小写的旧标识片段。
static func _has_any_identifier(stack: Variant, fragments: Array) -> bool:
	if _stack_is_empty(stack):
		return false
	var item: Resource = _stack_item(stack)
	if _contains_any_fragment(ITEM_DATA_COMPAT.call("get_card_id", item), fragments):
		return true
	for tag in ITEM_DATA_COMPAT.call("get_item_tags", item):
		if _contains_any_fragment(tag, fragments):
			return true
	return false


## 对一个 StringName 执行忽略大小写的片段匹配。
static func _contains_any_fragment(identifier: StringName, fragments: Array) -> bool:
	if identifier == null or identifier.is_empty():
		return false
	var text: String = String(identifier).to_lower()
	for fragment in fragments:
		if text.contains(String(fragment).to_lower()):
			return true
	return false
