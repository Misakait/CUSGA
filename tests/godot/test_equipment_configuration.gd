@tool
extends McpTestSuite

## 装备配置重构契约：检查器提示、多套装、独立实例属性与存档往返。

const EQUIPMENT: GDScript = preload("res://resources/item/equipment/equipment_data.gd")
const BONUS: GDScript = preload("res://resources/item/equipment/equipment_attribute_bonus.gd")
const SET_DATA: GDScript = preload("res://resources/item/equipment/equipment_set_data.gd")
const TIER: GDScript = preload("res://resources/item/equipment/set_bonus_tier.gd")
const FIXED_BONUS: GDScript = preload("res://resources/item/equipment/equipment_set_attribute_bonus.gd")
const COMPONENT: GDScript = preload("res://entities/components/equipment_component.gd")
const INVENTORY: GDScript = preload("res://entities/components/inventory_component.gd")
const STACK: GDScript = preload("res://resources/item/item_stack.gd")
const CODEC: GDScript = preload("res://core/save/save_slot_codec.gd")
const COMPAT: GDScript = preload("res://resources/item/equipment/equipment_data_compat.gd")
const PLAYER: GDScript = preload("res://entities/player.gd")
const LOOT_TABLE: GDScript = preload("res://resources/loot/loot_table.gd")
const LOOT_DROP: GDScript = preload("res://resources/loot/loot_drop.gd")

## 记录属性加成的最小同级组件。
class Attributes extends Node:
	var bonuses: Dictionary = {}

	## 参数 attribute：属性编号；value：固定增量；source：来源。返回值：无。
	func AddPermanentBonus(attribute: Variant, value: float, _source: Variant) -> void:
		bonuses[attribute] = float(bonuses.get(attribute, 0.0)) + value

	## 参数 attribute：属性编号；value：需撤销的增量；source：来源。返回值：无。
	func RemovePermanentBonus(attribute: Variant, value: float, _source: Variant) -> void:
		bonuses[attribute] = float(bonuses.get(attribute, 0.0)) - value
		if is_zero_approx(float(bonuses[attribute])):
			bonuses.erase(attribute)

## 记录标签层数的最小同级组件。
class Tags extends Node:
	var counts: Dictionary = {}

	## 参数 tag：标签。返回值：无，增加一层。
	func AddTag(tag: StringName) -> void:
		counts[tag] = int(counts.get(tag, 0)) + 1

	## 参数 tag：标签。返回值：无，撤销一层。
	func RemoveTag(tag: StringName) -> void:
		counts[tag] = int(counts.get(tag, 0)) - 1
		if int(counts[tag]) <= 0:
			counts.erase(tag)

## 历史资源输入夹具；仅兼容桥接收旧数字与字典，正式资源不再导出旧形状。
class LegacyItem extends Resource:
	var CardId: StringName = &"legacy_item"
	var CardName: String = "历史装备"
	var MaxStackSize: int = 1
	var ItemTags: Array[StringName] = []
	var BuyPrice: int = 0
	var SellPrice: int = 0
	var ValidSlots: Array[int] = [4]
	var SetType: int = 2
	var AttributeBonuses: Dictionary = {0: Vector2i(8, 3)}
	var GrantedTags: Array[StringName] = []


## 无参数；返回值：编辑器测试套件名。
func suite_name() -> String:
	return "equipment_configuration"


## 无参数，无返回值；验证枚举与专属资源类型确实提供给检查器。
func test_inspector_shapes_and_neutral_defaults() -> void:
	var item: EquipmentData = EQUIPMENT.new()
	assert_eq(item.MaxStackSize, 1, "装备默认不可堆叠。")
	item.MaxStackSize = 99
	assert_eq(item.ActualMaxStackSize, 1, "通用配置被改写时，实际装备上限仍固定为一。")
	assert_true(item.SetType.is_empty(), "没有套装配置时保持中性。")
	assert_true(item.AttributeBonuses.is_empty(), "不虚构属性加成。")
	var slot_property := _property(item, "ValidSlots")
	assert_contains(String(slot_property.get("hint_string", "")), "Helmet", "数组元素需要真正的枚举提示。")
	assert_contains(String(slot_property.get("hint_string", "")), "MagicItem", "槽位枚举必须包含末尾槽位。")
	assert_contains(String(_property(item, "AttributeBonuses").get("hint_string", "")), "EquipmentAttributeBonus", "属性只能新建专属资源。")
	assert_contains(String(_property(TIER.new(), "AttributeBonuses").get("hint_string", "")), "EquipmentSetAttributeBonus", "套装使用固定加成专属资源。")
	var registered: Dictionary = {}
	for info: Dictionary in ProjectSettings.get_global_class_list():
		registered[String(info.get("class", ""))] = info.get("path", "")
	for entry: Array in [
		[item, "EquipmentAttributeBonus", "res://resources/item/equipment/equipment_attribute_bonus.gd"],
		[TIER.new(), "EquipmentSetAttributeBonus", "res://resources/item/equipment/equipment_set_attribute_bonus.gd"],
	]:
		var expected_type: String = entry[1]
		assert_eq(registered.get(expected_type), entry[2], "检查器新建类型必须注册到专属脚本。")
		var hint: String = String(_property(entry[0], "AttributeBonuses").get("hint_string", ""))
		var picker := EditorResourcePicker.new()
		# 使用真实字段的数组元素类型，避免只验证一个与字段无关的手工选择器。
		picker.base_type = hint.get_slice(":", hint.get_slice_count(":") - 1)
		var allowed: PackedStringArray = picker.get_allowed_types()
		assert_true(allowed.has(expected_type), "新建菜单必须包含 %s。" % expected_type)
		assert_false(allowed.has("Resource"), "专属加成数组不能新建无关普通 Resource。")
		picker.free()
	var fixed: EquipmentSetAttributeBonus = FIXED_BONUS.new()
	assert_eq(fixed.Value, 0.0, "未配置固定加成为零。")
	var range: EquipmentAttributeBonus = BONUS.new()
	assert_eq(range.MinValue, 0, "未配置随机下界为零。")
	assert_eq(range.MaxValue, 0, "未配置随机上界为零。")


## 无参数，无返回值；固定条目与倒置随机范围相加且不重复随机。
func test_attribute_ranges_add_and_roll_only_once() -> void:
	var item: EquipmentData = _item(4, [])
	item.AttributeBonuses = [_bonus(0, 5, 5), null, _bonus(0, 9, 7), _bonus(5, 100, 100)] as Array[EquipmentAttributeBonus]
	var stack: RefCounted = _stack(item)
	stack.call("RollRandomStats")
	var rolled: Dictionary = stack.get("RolledAttributes").duplicate(true)
	assert_true(int(rolled[0]) >= 12 and int(rolled[0]) <= 14, "重复物攻条目独立生成再叠加，倒置范围需规整。")
	assert_eq(int(rolled[5]), 100, "固定生命上限条目准确生成。")
	item.AttributeBonuses[0].MinValue = 900
	item.AttributeBonuses[0].MaxValue = 900
	stack.call("RollRandomStats")
	assert_eq(stack.get("RolledAttributes"), rolled, "重复调用不改变已生成属性。")
	var duplicate: RefCounted = stack.call("Duplicate")
	duplicate.call("RollRandomStats")
	assert_eq(duplicate.get("RolledAttributes"), rolled, "复制后的实例仍保留属性。")
	var copied: RefCounted = STACK.new()
	copied.call("CopyFrom", duplicate)
	copied.call("RollRandomStats")
	assert_eq(copied.get("RolledAttributes"), rolled, "CopyFrom 不允许重随机。")


## 无参数，无返回值；多个套装独立计数，同件重复标识不重复贡献。
func test_multiple_sets_deduplicate_and_remove_exactly() -> void:
	var context := _context()
	var component: Node = context.component
	var attributes: Attributes = context.attributes
	var tags: Tags = context.tags
	var alpha: EquipmentSetData = _make_set("alpha_set", 2, 0, 2.5, &"alpha_active")
	var beta: EquipmentSetData = _make_set("beta_set", 2, 4, -1.25, &"beta_active")
	var extra_tier: EquipmentSetBonusTier = TIER.new()
	extra_tier.RequiredPieces = 2
	extra_tier.AttributeBonuses = [_fixed(0, 1.25), _fixed(0, 1.25), null] as Array[EquipmentSetAttributeBonus]
	alpha.Tiers.append(extra_tier)
	component.set("AllSetDatabase", [alpha, beta] as Array[EquipmentSetData])
	var helmet: EquipmentData = _item(0, ["alpha_set", "alpha_set", "beta_set"])
	var chest: EquipmentData = _item(1, ["alpha_set", "beta_set"])
	assert_true(bool(component.call("Equip", _stack(helmet), 0)), "第一件装备成功。")
	assert_true(attributes.bonuses.is_empty(), "一件中的重复套装标识不能触发两件套。")
	assert_true(bool(component.call("Equip", _stack(chest), 1)), "第二件装备成功。")
	assert_eq(attributes.bonuses.get(0), 5.0, "多个满足阶级和重复属性条目相加。")
	assert_eq(attributes.bonuses.get(4), -1.25, "同一件装备的另一个套装独立生效并保留浮点负值。")
	assert_eq(tags.counts.get(&"alpha_active"), 1, "第一个套装标签仅加一层。")
	assert_eq(tags.counts.get(&"beta_active"), 1, "第二个套装标签同样生效。")
	component.call("Unequip", 1)
	assert_true(attributes.bonuses.is_empty(), "不满足件数时所有阶级精确撤销。")
	assert_true(tags.counts.is_empty(), "卸下后没有残留套装标签。")


## 无参数，无返回值；穿脱及新属性数组的存档往返保留实例值。
func test_equipment_and_save_roundtrip_preserve_values() -> void:
	var context := _context()
	var component: Node = context.component
	var item: EquipmentData = _item(4, [])
	item.CardId = &"attribute_save_probe"
	item.AttributeBonuses = [_bonus(0, 10, 20), _bonus(5, 100, 100)] as Array[EquipmentAttributeBonus]
	var stack: RefCounted = _stack(item)
	stack.call("RollRandomStats")
	var expected: Dictionary = stack.get("RolledAttributes").duplicate(true)
	assert_true(bool(component.call("Equip", stack, 4)), "装备随机实例。")
	var equipped: RefCounted = component.call("GetEquippedStack", 4)
	assert_eq(equipped.get("RolledAttributes"), expected, "穿戴复制实例值。")
	component.call("Unequip", 4)
	var encoded: Dictionary = CODEC.call("encode_entry", item, 1, expected)
	var lookup: Callable = func(_id: StringName) -> Resource: return item
	var decoded: Dictionary = CODEC.call("decode_entry", encoded, lookup)
	assert_eq(decoded.get("rolled"), expected, "新数组声明白名单后存档不丢失合法属性。")
	var hydrated: RefCounted = STACK.new()
	hydrated.call("SetItem", item, 1)
	hydrated.set("RolledAttributes", decoded.get("rolled"))
	hydrated.call("RollRandomStats")
	assert_eq(hydrated.get("RolledAttributes"), expected, "读档后的结果不能重随机。")
	encoded["rolled"]["14"] = 50
	decoded = CODEC.call("decode_entry", encoded, lookup)
	assert_eq(decoded.get("rolled"), expected, "新数组白名单拒绝未声明的属性。")
	assert_eq(int(decoded.get("rolled_dropped")), 1, "丢弃脏属性需计数。")


## 无参数，无返回值；新库存物品和掉落各生成属性，库存转移保留结果。
func test_inventory_creation_loot_and_transfer() -> void:
	var item: EquipmentData = _item(4, [])
	item.MaxStackSize = 99
	item.AttributeBonuses = [_bonus(0, 11, 11)] as Array[EquipmentAttributeBonus]
	var source: Node = track(INVENTORY.new()) as Node
	var target: Node = track(INVENTORY.new()) as Node
	source.set("Capacity", 2)
	target.set("Capacity", 2)
	assert_eq(int(source.call("AddItem", item, 2)), 0, "新库存装备可以生成两件独立实例。")
	assert_eq(source.call("GetStackAt", 0).get("RolledAttributes"), {0: 11}, "AddItem 首次生成属性。")
	assert_eq(source.call("GetStackAt", 1).get("RolledAttributes"), {0: 11}, "第二件也具有配置属性。")
	item.CardId = &"single_equipment_probe"
	var lookup: Callable = func(_id: StringName) -> Resource: return item
	for index: int in 2:
		var entry: Dictionary = CODEC.call("stack_to_entry", source.call("GetStackAt", index))
		var encoded: Dictionary = CODEC.call("encode_entry", item, int(entry["amount"]), entry["rolled"])
		var decoded: Dictionary = CODEC.call("decode_entry", encoded, lookup)
		assert_eq(int(decoded.get("amount")), 1, "存档往返的每个装备实例仍为单件。")
		assert_eq(decoded.get("rolled"), {0: 11}, "通用上限误配不会合并或丢失实例属性。")
	item.AttributeBonuses[0].MinValue = 99
	item.AttributeBonuses[0].MaxValue = 99
	target.call("MoveItemFrom", source, 0, 0)
	assert_eq(target.call("GetStackAt", 0).get("RolledAttributes"), {0: 11}, "搬运不按资源新配置重新生成。")
	var drop: LootDrop = LOOT_DROP.new()
	drop.Item = item
	drop.DropChance = 100
	drop.MinAmount = 2
	drop.MaxAmount = 2
	var table: LootTableData = LOOT_TABLE.new()
	table.Drops = [drop] as Array[LootDrop]
	var result: Array = table.call("RollLoot", 0)
	assert_eq(result.size(), 2, "不可堆叠装备掉落必须拆为独立实例。")
	for entry in result:
		assert_eq(int(entry.get("Amount")), 1, "每件装备数量为一。")
		assert_eq(entry.get("RolledAttributes"), {0: 99}, "掉落首次生成当前配置属性。")
	var pickup_inventory: Node = track(INVENTORY.new()) as Node
	pickup_inventory.set("Capacity", 2)
	var player: Node = track(PLAYER.new()) as Node
	player.set("_inventory", pickup_inventory)
	item.AttributeBonuses[0].MinValue = 123
	item.AttributeBonuses[0].MaxValue = 123
	assert_true(bool(player.call("TryAddItemToInventory", result[0])), "公开拾取入口接受掉落。")
	assert_eq(pickup_inventory.call("GetStackAt", 0).get("RolledAttributes"), {0: 99}, "拾取保留掉落实例属性，不按新配置重随机。")
	assert_eq(result[0].get("RolledAttributes"), {0: 99}, "加入库存不改变来源堆叠。")
	var observed: Dictionary = {}
	pickup_inventory.call("GetStackAt", 1).OnStackChanged.connect(func(stack: Variant) -> void:
		if not bool(stack.get("IsEmpty")):
			observed["rolled"] = stack.get("RolledAttributes").duplicate(true)
	)
	pickup_inventory.call("ReplaceItem", 1, item, 1)
	assert_eq(observed.get("rolled"), {0: 123}, "槽位观察者首次通知必须看到完整生成结果。")
	assert_false(bool(player.call("TryAddItemToInventory", result[1])), "背包满时拾取失败。")
	assert_eq(pickup_inventory.call("GetStackAt", 0).get("RolledAttributes"), {0: 99}, "拾取失败不改已有实例。")
	var ordinary: Resource = preload("res://resources/item/item_data.gd").new()
	ordinary.set("CardId", &"partial_pickup_probe")
	ordinary.set("CardName", "部分拾取契约物品")
	ordinary.set("MaxStackSize", 5)
	var partial_inventory: Node = track(INVENTORY.new()) as Node
	partial_inventory.set("Capacity", 1)
	assert_eq(int(partial_inventory.call("AddItem", ordinary, 4)), 0, "普通物品夹具先完整加入四件。")
	assert_eq(int(partial_inventory.call("GetStackAt", 0).get("Amount")), 4, "拾取前普通库存必须为四件。")
	var larger_drop: RefCounted = STACK.new()
	larger_drop.call("SetItem", ordinary, 2)
	player.set("_inventory", partial_inventory)
	assert_false(bool(player.call("TryAddItemToInventory", larger_drop)), "仅能放入部分数量时拾取整体失败。")
	assert_eq(int(partial_inventory.call("GetStackAt", 0).get("Amount")), 4, "失败不部分加入，以免世界保留完整掉落导致重复物品。")




## 无参数，无返回值；旧数字套装和字典只能从兼容桥读取。
func test_legacy_inputs_and_explicit_slots() -> void:
	var legacy := LegacyItem.new()
	assert_eq(COMPAT.call("get_set_types", legacy), PackedStringArray(["stone_set"]), "旧数字套装映射稳定标识。")
	assert_eq(COMPAT.call("get_attribute_bonuses", legacy), {0: Vector2i(3, 8)}, "旧属性范围同样规整。")
	var item: EquipmentData = EQUIPMENT.new()
	item.CardId = &"IronHelmet"
	var stack: RefCounted = _stack(item)
	assert_false(bool(COMPONENT.CanEquipStack(stack, 0)), "新装备未配置槽位时名称不能猜成头盔。")
	item.ValidSlots.append(0)
	assert_true(bool(COMPONENT.CanEquipStack(stack, 0)), "配置明确槽位后装备可用。")


func _property(object: Object, name: String) -> Dictionary:
	for property: Dictionary in object.get_property_list():
		if String(property.get("name", "")) == name:
			return property
	return {}


func _bonus(attribute: int, minimum: int, maximum: int) -> EquipmentAttributeBonus:
	var bonus: EquipmentAttributeBonus = BONUS.new()
	bonus.Attribute = attribute
	bonus.MinValue = minimum
	bonus.MaxValue = maximum
	return bonus


func _fixed(attribute: int, value: float) -> EquipmentSetAttributeBonus:
	var bonus: EquipmentSetAttributeBonus = FIXED_BONUS.new()
	bonus.Attribute = attribute
	bonus.Value = value
	return bonus


func _item(slot: int, sets: Array) -> EquipmentData:
	var item: EquipmentData = EQUIPMENT.new()
	item.ValidSlots.append(slot)
	item.SetType = PackedStringArray(sets)
	return item


func _stack(item: Resource) -> RefCounted:
	var stack: RefCounted = STACK.new()
	stack.call("SetItem", item, 1)
	return stack


func _make_set(key: String, count: int, attribute: int, value: float, tag: StringName) -> EquipmentSetData:
	var set_data: EquipmentSetData = SET_DATA.new()
	set_data.SetType = key
	var tier: EquipmentSetBonusTier = TIER.new()
	tier.RequiredPieces = count
	tier.AttributeBonuses = [_fixed(attribute, value)] as Array[EquipmentSetAttributeBonus]
	tier.GrantedTags.append(tag)
	set_data.Tiers.append(tier)
	return set_data


func _context() -> Dictionary:
	var root: Node = track(Node.new()) as Node
	var attributes := Attributes.new()
	attributes.name = "AttributeComponent"
	root.add_child(attributes)
	var tags := Tags.new()
	tags.name = "TagComponent"
	root.add_child(tags)
	var component: Node = COMPONENT.new()
	component.name = "EquipmentComponent"
	root.add_child(component)
	component.call("_ready")
	return {"component": component, "attributes": attributes, "tags": tags}
