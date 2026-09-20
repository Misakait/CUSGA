@tool
extends McpTestSuite

## DebugLoadout Resource 与 Seeder 的 GDScript 生产迁移契约套件。

## 迁移后的开局配置脚本。
const DEBUG_LOADOUT_DATA_SCRIPT: GDScript = preload("res://resources/debug/debug_loadout_data.gd")

## 迁移后的固定堆叠条目脚本。
const DEBUG_ITEM_STACK_ENTRY_SCRIPT: GDScript = preload("res://resources/debug/debug_item_stack_entry.gd")

## 迁移后的动态装备条目脚本。
const DEBUG_GENERATED_EQUIPMENT_ENTRY_SCRIPT: GDScript = preload("res://resources/debug/debug_generated_equipment_entry.gd")

## 迁移后的开局配置应用脚本。
const DEBUG_LOADOUT_SEEDER_SCRIPT: GDScript = preload("res://core/debug/debug_loadout_seeder.gd")

## 固定物品条目现在创建的生产 GDScript ItemStack 路径。
const PRODUCTION_ITEM_STACK_PATH: String = "res://resources/item/item_stack.gd"

## 动态装备条目现在创建的生产 GDScript EquipmentData 路径。
const PRODUCTION_EQUIPMENT_DATA_PATH: String = "res://resources/item/equipment/equipment_data.gd"

## 动态工具条目现在创建的生产 GDScript ToolData 路径。
const PRODUCTION_TOOL_DATA_PATH: String = "res://resources/item/tool/tool_data.gd"

## 编辑器聚焦测试直接实例化的 C# ItemData 脚本。
const LEGACY_ITEM_DATA_SCRIPT: Script = preload("res://resources/item/ItemData.cs")

## 编辑器聚焦测试直接实例化的 C# SkillCardData 脚本。
const LEGACY_SKILL_CARD_DATA_SCRIPT: Script = preload("res://resources/item/card/SkillCardData.cs")

## 已切换到 GDScript 的默认 Debug 配置资源路径。
const DEFAULT_LOADOUT_PATH: String = "res://resources/debug/default_inventory_loadout.tres"

## 生产主场景路径。
const MAIN_SCENE_PATH: String = "res://scenes/Main.tscn"

## 默认配置使用的生产 GDScript 普通物品资源路径。
const PRODUCTION_ITEM_PATH: String = "res://items/item1.tres"

## 测试使用的旧 C# 技能卡资源路径。
const LEGACY_SKILL_CARD_PATH: String = "res://resources/skill_cards/test_card_1.tres"


## 提供 Seeder 所需固定槽位协议的最小库存组件。
class FakeInventoryComponent extends Node:
	## 创建空槽时使用的生产兼容 C# 堆叠脚本。
	const STACK_SCRIPT: Script = preload("res://core/inventory/ItemStack.cs")

	## 当前库存容量。
	var Capacity: int = 0
	## 按槽位保存的生产兼容堆叠。
	var slots: Array[RefCounted] = []
	## TrySetStackAt 的累计调用次数。
	var set_call_count: int = 0
	## TryClearStackAt 的累计调用次数。
	var clear_call_count: int = 0

	## 创建指定数量的空堆叠槽位。
	## 参数 capacity：需要初始化的固定容量。
	## 返回值：无。
	func configure_capacity(capacity: int) -> void:
		Capacity = capacity
		slots.clear()
		for _index: int in range(Capacity):
			slots.append(STACK_SCRIPT.new() as RefCounted)

	## 读取指定槽位的堆叠。
	## 参数 index：目标槽位下标。
	## 返回值：该槽位当前保存的堆叠。
	func GetStackAt(index: int) -> RefCounted:
		return slots[index]

	## 复制堆叠到指定槽位并记录调用。
	## 参数 index：目标槽位下标。
	## 参数 stack：需要写入的生产兼容堆叠。
	## 返回值：下标有效时返回 true。
	func TrySetStackAt(index: int, stack: RefCounted) -> bool:
		if index < 0 or index >= Capacity or stack == null:
			return false
		set_call_count += 1
		slots[index] = stack.call("Duplicate") as RefCounted
		return true

	## 清空指定槽位并记录调用。
	## 参数 index：目标槽位下标。
	## 返回值：下标有效时返回 true。
	func TryClearStackAt(index: int) -> bool:
		if index < 0 or index >= Capacity:
			return false
		clear_call_count += 1
		slots[index] = STACK_SCRIPT.new() as RefCounted
		return true


## 提供 Seeder 所需装备协议的最小组件。
class FakeEquipmentComponent extends Node:
	## 以稳定槽位整数保存当前装备堆叠。
	var equipped: Dictionary = {}
	## Equip 的累计调用次数。
	var equip_call_count: int = 0
	## Unequip 的累计调用次数。
	var unequip_call_count: int = 0

	## 复制并保存指定装备堆叠。
	## 参数 stack：需要装备的生产兼容堆叠。
	## 参数 slot：EquipmentSlot 的稳定整数值。
	## 返回值：堆叠有效时返回 true。
	func Equip(stack: RefCounted, slot: int) -> bool:
		if stack == null:
			return false
		equip_call_count += 1
		equipped[slot] = stack.call("Duplicate") as RefCounted
		return true

	## 清除指定槽位并记录调用。
	## 参数 slot：EquipmentSlot 的稳定整数值。
	## 返回值：无。
	func Unequip(slot: int) -> void:
		unequip_call_count += 1
		equipped.erase(slot)


## 提供 Seeder 所需初始属性协议的最小组件。
class FakeAttributeComponent extends Node:
	## 当前已经应用的初始属性资源。
	var InitialData: Resource
	## InitializeWithData 的累计调用次数。
	var initialize_call_count: int = 0

	## 保存首次应用的属性资源。
	## 参数 data：DebugLoadoutData 提供的 StartingStats 资源。
	## 返回值：无。
	func InitializeWithData(data: Resource) -> void:
		initialize_call_count += 1
		InitialData = data


## 返回 GodotAI 使用的稳定套件名称。
## 返回值：DebugLoadout 迁移契约套件名。
func suite_name() -> String:
	return "debug_loadout_migration"


## 验证默认资源的脚本、数组和值在生产切换后完整保留。
## 返回值：无。
func test_default_resource_and_main_references_use_gdscript() -> void:
	## 强制从磁盘读取迁移后的默认配置，避免旧 ResourceLoader 缓存干扰。
	var loadout := ResourceLoader.load(DEFAULT_LOADOUT_PATH, "Resource", ResourceLoader.CACHE_MODE_REPLACE) as Resource
	assert_true(loadout != null, "默认 DebugLoadout 资源必须能够加载。")
	if loadout == null:
		return
	## 默认配置当前实际挂载的脚本。
	var loadout_script := loadout.get_script() as Script
	assert_eq(loadout_script.resource_path, "res://resources/debug/debug_loadout_data.gd", "默认配置必须使用 GDScript DebugLoadoutData。")

	## 默认玩家背包固定物品数组。
	var inventory_items: Array = loadout.get("InventoryItems")
	## 默认出战卡组固定物品数组。
	var battle_deck_items: Array = loadout.get("BattleDeckItems")
	## 默认玩家背包动态装备数组。
	var inventory_equipment: Array = loadout.get("InventoryEquipment")
	## 默认已装备动态装备数组。
	var equipped_equipment: Array = loadout.get("EquippedEquipment")
	assert_eq(inventory_items.size(), 10, "默认背包固定物品条目数不得丢失。")
	assert_eq(battle_deck_items.size(), 4, "默认出战卡组条目数不得丢失。")
	assert_eq(inventory_equipment.size(), 6, "默认背包动态装备条目数不得丢失。")
	assert_eq(equipped_equipment.size(), 2, "默认已装备条目数不得丢失。")
	assert_eq((inventory_items[0] as Resource).get_script().resource_path, "res://resources/debug/debug_item_stack_entry.gd", "固定物品条目必须切换到 GDScript。")
	assert_eq(((inventory_items[0] as Resource).get("Item") as Resource).resource_path, PRODUCTION_ITEM_PATH, "首个固定物品必须继续引用同一生产 ItemData 资产。")
	assert_eq(int((inventory_items[0] as Resource).get("Amount")), 24, "首个固定物品数量必须保留 24。")
	assert_eq(((battle_deck_items[0] as Resource).get("Item") as Resource).resource_path, LEGACY_SKILL_CARD_PATH, "首张出战卡必须继续引用原 SkillCardData 资产。")
	assert_eq((inventory_equipment[3] as Resource).get_script().resource_path, "res://resources/debug/debug_generated_equipment_entry.gd", "动态装备条目必须切换到 GDScript。")
	assert_eq((inventory_equipment[3] as Resource).get("TargetGatheringTag"), &"wood", "Debug 斧头采集标签必须保留。")
	assert_eq(int((inventory_equipment[3] as Resource).get("GatheringTimeReduction")), 10, "Debug 斧头时间减免必须保留 10。")

	## 强制从磁盘读取生产主场景。
	var main_scene := ResourceLoader.load(MAIN_SCENE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	assert_true(main_scene != null, "Main 场景必须能够加载。")
	if main_scene == null:
		return
	## 未进入场景树的生产主场景实例。
	var main := main_scene.instantiate() as Node
	## 生产 DebugLoadoutSeeder 节点。
	var seeder := main.get_node("DebugLoadoutSeeder") as Node
	## 生产 Seeder 当前实际挂载的脚本。
	var seeder_script := seeder.get_script() as Script
	assert_eq(seeder_script.resource_path, "res://core/debug/debug_loadout_seeder.gd", "Main 必须使用 GDScript DebugLoadoutSeeder。")
	assert_true(seeder.get("Loadout") == loadout or (seeder.get("Loadout") as Resource).resource_path == DEFAULT_LOADOUT_PATH, "Main 必须继续引用默认 DebugLoadout 资源。")
	main.free()


## 验证固定物品条目生成生产 GDScript 库存使用的 ItemStack。
## 返回值：无。
func test_item_stack_entry_preserves_item_amount_and_compatibility_type() -> void:
	## 直接实例化的 C# ItemData 用于避免编辑器工具态把 .tres 降为基础 Resource。
	var item := LEGACY_ITEM_DATA_SCRIPT.new() as Resource
	item.set("CardId", &"debug_stack_contract")
	item.set("CardName", "固定堆叠契约物品")
	## 待验证的固定堆叠条目。
	var entry := DEBUG_ITEM_STACK_ENTRY_SCRIPT.new() as Resource
	entry.set("Item", item)
	entry.set("Amount", 24)
	entry.set("RollRandomStats", false)
	## 条目生成的生产 GDScript 堆叠。
	var stack := entry.call("CreateStack") as RefCounted
	assert_true(stack != null, "有效固定物品条目必须生成堆叠。")
	assert_eq(stack.get_script().resource_path, PRODUCTION_ITEM_STACK_PATH, "固定物品条目必须生成生产 GDScript ItemStack。")
	assert_true(stack.get("Item") == item, "生成堆叠必须保留原 ItemData Resource 引用。")
	assert_eq(int(stack.get("Amount")), 24, "生成堆叠必须保留配置数量。")
	assert_true(bool(stack.get("IsEmpty")) == false, "有效堆叠不得被判定为空。")

	entry.set("Amount", 0)
	assert_eq(entry.call("CreateStack"), null, "非正数量必须沿用旧实现返回 null。")


## 验证动态普通装备和工具装备保留类型、槽位、属性与采集字段。
## 返回值：无。
func test_generated_equipment_preserves_regular_and_tool_contract() -> void:
	## 生成固定物攻普通武器的调试条目。
	var regular_entry := DEBUG_GENERATED_EQUIPMENT_ENTRY_SCRIPT.new() as Resource
	regular_entry.set("Slot", 4)
	regular_entry.set("CardName", "Debug 木剑")
	regular_entry.set("BonusAttribute", 0)
	regular_entry.set("BonusRange", Vector2i(70, 70))
	## 普通装备条目生成的生产堆叠。
	var regular_stack := regular_entry.call("CreateStack") as RefCounted
	assert_eq(regular_stack.get_script().resource_path, PRODUCTION_ITEM_STACK_PATH, "动态普通装备必须生成生产 GDScript ItemStack。")
	## 普通装备堆叠中的 GDScript EquipmentData。
	var regular_item := regular_stack.get("Item") as Resource
	assert_eq(regular_item.get_script().resource_path, PRODUCTION_EQUIPMENT_DATA_PATH, "无采集字段时必须生成生产 GDScript EquipmentData。")
	assert_eq(regular_item.get("CardId"), &"debug_Weapon_Debug 木剑", "动态装备 CardId 必须保留旧枚举名称格式。")
	assert_eq(int((regular_item.get("ValidSlots") as Array)[0]), 4, "普通装备必须写入 Weapon 槽。")
	assert_eq((regular_item.get("AttributeBonuses") as Dictionary)[0], Vector2i(70, 70), "普通装备必须保留属性范围。")
	assert_eq(int((regular_stack.get("RolledAttributes") as Dictionary)[0]), 70, "固定范围必须生成相同随机属性值。")

	## 生成带采集字段的斧头调试条目。
	var tool_entry := DEBUG_GENERATED_EQUIPMENT_ENTRY_SCRIPT.new() as Resource
	tool_entry.set("Slot", 5)
	tool_entry.set("CardName", "Debug 斧头")
	tool_entry.set("TargetGatheringTag", &"wood")
	tool_entry.set("YieldGrowth", 1)
	tool_entry.set("GatheringTimeReduction", 10)
	## 工具条目生成的生产堆叠。
	var tool_stack := tool_entry.call("CreateStack") as RefCounted
	assert_eq(tool_stack.get_script().resource_path, PRODUCTION_ITEM_STACK_PATH, "动态工具必须生成生产 GDScript ItemStack。")
	## 工具堆叠中的 GDScript ToolData。
	var tool_item := tool_stack.get("Item") as Resource
	assert_eq(tool_item.get_script().resource_path, PRODUCTION_TOOL_DATA_PATH, "任一采集字段生效时必须生成生产 GDScript ToolData。")
	assert_eq(tool_item.get("TargetGatheringTag"), &"wood", "工具必须保留采集标签。")
	assert_eq(int(tool_item.get("YieldGrowth")), 1, "工具必须保留额外采集产量。")
	assert_eq(int(tool_item.get("GatheringTimeReduction")), 10, "工具必须保留采集时间减免。")
	assert_eq(int((tool_item.get("ValidSlots") as Array)[0]), 5, "工具必须写入 Axe 槽。")


## 验证 Seeder 的清空、填充、初始属性、装备与 ApplyOnce 时序。
## 返回值：无。
func test_seeder_preserves_apply_order_and_apply_once_contract() -> void:
	## 夹具根节点提供 Player 与 Seeder 的相对路径关系。
	var fixture := Node.new()
	## Seeder 查找的玩家节点。
	var player := Node.new()
	player.name = "Player"
	fixture.add_child(player)
	## 玩家固定组件容器。
	var components := Node.new()
	components.name = "Components"
	player.add_child(components)

	## 三槽玩家背包夹具。
	var inventory := FakeInventoryComponent.new()
	inventory.name = "InventoryComponent"
	inventory.configure_capacity(3)
	components.add_child(inventory)
	## 两槽出战卡组夹具。
	var battle_deck := FakeInventoryComponent.new()
	battle_deck.name = "BattleDeckComponent"
	battle_deck.configure_capacity(2)
	components.add_child(battle_deck)
	## 装备组件夹具。
	var equipment := FakeEquipmentComponent.new()
	equipment.name = "EquipmentComponent"
	components.add_child(equipment)
	## 属性组件夹具。
	var attributes := FakeAttributeComponent.new()
	attributes.name = "AttributeComponent"
	components.add_child(attributes)

	## 夹具直接实例化的旧 C# 普通物品，确保 C# ItemStack 参数保持真实管理类型。
	var item := LEGACY_ITEM_DATA_SCRIPT.new() as Resource
	item.set("CardId", &"debug_seeder_item")
	item.set("CardName", "Seeder 契约物品")
	## 夹具直接实例化的旧 C# 技能卡，确保卡组输入保持真实管理类型。
	var skill_card := LEGACY_SKILL_CARD_DATA_SCRIPT.new() as Resource
	skill_card.set("CardId", &"debug_seeder_skill")
	skill_card.set("CardName", "Seeder 契约技能卡")
	## 玩家背包固定条目。
	var inventory_entry := DEBUG_ITEM_STACK_ENTRY_SCRIPT.new() as Resource
	inventory_entry.set("Item", item)
	inventory_entry.set("Amount", 2)
	inventory_entry.set("RollRandomStats", false)
	## 出战卡组固定条目。
	var deck_entry := DEBUG_ITEM_STACK_ENTRY_SCRIPT.new() as Resource
	deck_entry.set("Item", skill_card)
	deck_entry.set("RollRandomStats", false)
	## 玩家背包动态装备条目。
	var inventory_equipment_entry := DEBUG_GENERATED_EQUIPMENT_ENTRY_SCRIPT.new() as Resource
	inventory_equipment_entry.set("Slot", 4)
	inventory_equipment_entry.set("CardName", "背包装备")
	## 直接装备的动态装备条目。
	var equipped_entry := DEBUG_GENERATED_EQUIPMENT_ENTRY_SCRIPT.new() as Resource
	equipped_entry.set("Slot", 12)
	equipped_entry.set("CardName", "已装备戒指")
	## 首次初始化属性时使用的 StartingStats。
	var starting_stats := preload("res://resources/stats/starting_stats.gd").new() as Resource

	## 待应用的 GDScript DebugLoadoutData。
	var loadout := DEBUG_LOADOUT_DATA_SCRIPT.new() as Resource
	loadout.set("PlayerStartingStats", starting_stats)
	loadout.set("InventoryItems", [inventory_entry] as Array[Resource])
	loadout.set("BattleDeckItems", [deck_entry] as Array[Resource])
	loadout.set("InventoryEquipment", [inventory_equipment_entry] as Array[Resource])
	loadout.set("EquippedEquipment", [equipped_entry] as Array[Resource])

	## 待验证的 GDScript Seeder。
	var seeder := DEBUG_LOADOUT_SEEDER_SCRIPT.new() as Node
	seeder.name = "DebugLoadoutSeeder"
	seeder.set("Loadout", loadout)
	fixture.add_child(seeder)
	seeder.call("ApplyLoadout")

	assert_eq(attributes.initialize_call_count, 1, "属性尚未初始化时必须应用 PlayerStartingStats 一次。")
	assert_true(attributes.InitialData == starting_stats, "属性初始化必须保留 StartingStats Resource 身份。")
	assert_eq(inventory.clear_call_count, 3, "应用前必须清空玩家背包全部三个槽位。")
	assert_eq(battle_deck.clear_call_count, 2, "应用前必须清空出战卡组全部两个槽位。")
	assert_eq(equipment.unequip_call_count, 16, "应用前必须遍历并卸下全部 16 个装备槽。")
	assert_eq(inventory.set_call_count, 2, "玩家背包必须依次接收固定物品与动态装备。")
	assert_true(inventory.GetStackAt(0).get("Item") == item, "固定物品必须写入玩家背包首个空槽。")
	assert_eq(int(inventory.GetStackAt(0).get("Amount")), 2, "玩家背包固定物品数量必须保留。")
	assert_eq(battle_deck.set_call_count, 1, "出战卡组必须接收配置的技能卡。")
	assert_true(battle_deck.GetStackAt(0).get("Item") == skill_card, "出战卡组必须保留技能卡 Resource 身份。")
	assert_eq(equipment.equip_call_count, 1, "已装备条目必须调用 Equip 一次。")
	assert_true(equipment.equipped.has(12), "已装备戒指必须进入 Ring1=12 槽。")

	## 首次成功应用后的全部副作用次数快照。
	var call_snapshot: Array[int] = [
		attributes.initialize_call_count,
		inventory.clear_call_count,
		battle_deck.clear_call_count,
		equipment.unequip_call_count,
		inventory.set_call_count,
		battle_deck.set_call_count,
		equipment.equip_call_count,
	]
	seeder.call("ApplyLoadout")
	assert_eq(
		[
			attributes.initialize_call_count,
			inventory.clear_call_count,
			battle_deck.clear_call_count,
			equipment.unequip_call_count,
			inventory.set_call_count,
			battle_deck.set_call_count,
			equipment.equip_call_count,
		],
		call_snapshot,
		"ApplyOnce=true 时第二次调用不得重复产生任何副作用。"
	)
	fixture.free()
