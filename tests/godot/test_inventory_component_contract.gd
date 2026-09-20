@tool
extends McpTestSuite

## 并行库存组件与生产共享 UI 链的跨语言运行时契约套件。
##
## 组件契约继续覆盖并行 GDScript 实现，UI 契约同时锁定生产场景；旧 C# 物品和组件仍作为兼容输入。

const INVENTORY_SCRIPT: GDScript = preload("res://entities/components/inventory_component.gd")
const WAREHOUSE_SCRIPT: GDScript = preload("res://entities/components/warehouse_inventory_component.gd")
const BATTLE_DECK_SCRIPT: GDScript = preload("res://entities/components/battle_deck_component.gd")
const EQUIPMENT_COMPONENT_SCRIPT: GDScript = preload("res://entities/components/equipment_component.gd")
const ITEM_DATA_SCRIPT: GDScript = preload("res://resources/item/item_data.gd")
const ITEM_DATA_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")
const ITEM_STACK_SCRIPT: GDScript = preload("res://resources/item/item_stack.gd")
const EQUIPMENT_DATA_SCRIPT: GDScript = preload("res://resources/item/equipment/equipment_data.gd")
const TOOL_DATA_SCRIPT: GDScript = preload("res://resources/item/tool/tool_data.gd")
const SET_BONUS_TIER_SCRIPT: GDScript = preload("res://resources/item/equipment/set_bonus_tier.gd")
const EQUIPMENT_SET_DATA_SCRIPT: GDScript = preload("res://resources/item/equipment/equipment_set_data.gd")
const EQUIPMENT_TYPES: GDScript = preload("res://core/constants/equipment_types.gd")
const DRAGGABLE_DATA_SCRIPT: GDScript = preload("res://core/ui/draggable/draggable_data.gd")
const ITEM_TOOLTIP_PRESENTER_SCRIPT: GDScript = preload("res://core/ui/item_tooltip_presenter.gd")
const EQUIPMENT_SLOT_UI_SCRIPT: GDScript = preload("res://core/ui/equipment_slot_ui.gd")
const SLOT_UI_SCRIPT: GDScript = preload("res://core/ui/slot_ui.gd")
const WAREHOUSE_UI_SCRIPT: GDScript = preload("res://core/ui/warehouse/warehouse_ui.gd")
const WAREHOUSE_UI_SCENE: PackedScene = preload("res://scenes/Warehouse/warehouse_ui.tscn")
const INVENTORY_UI_SCRIPT: GDScript = preload("res://core/ui/inventory_ui.gd")
const INVENTORY_UI_SCENE: PackedScene = preload("res://scenes/inventory/inventory_ui.tscn")
const CRAFTING_UI_SCENE: PackedScene = preload("res://scenes/crafting/crafting_ui.tscn")
const CRAFTING_UI_SCRIPT: GDScript = preload("res://core/ui/crafting/crafting_ui.gd")
const CRAFTING_COMPONENT_SCRIPT: GDScript = preload("res://entities/components/crafting_component.gd")
const CRAFTING_INGREDIENT_SCRIPT: GDScript = preload("res://resources/recipe/crafting_ingredient.gd")
const CRAFTING_RECIPE_SCRIPT: GDScript = preload("res://resources/recipe/crafting_recipe.gd")
const RECIPE_BOOK_SCRIPT: GDScript = preload("res://resources/recipe/recipe_book_data.gd")
## 生产普通库存槽位场景路径。
const SLOT_UI_SCENE_PATH: String = "res://scenes/inventory/SlotUI.tscn"
## 生产装备槽位场景路径。
const EQUIPMENT_SLOT_UI_SCENE_PATH: String = "res://scenes/inventory/EquipmentSlotUI.tscn"
## 生产背包父面板场景路径。
const INVENTORY_UI_SCENE_PATH: String = "res://scenes/inventory/inventory_ui.tscn"
## 生产仓库父面板场景路径。
const WAREHOUSE_UI_SCENE_PATH: String = "res://scenes/Warehouse/warehouse_ui.tscn"
## 生产合成父面板场景路径。
const CRAFTING_UI_SCENE_PATH: String = "res://scenes/crafting/crafting_ui.tscn"
## 玩家根脚本路径，用于锁定库存实现的跨语言节点边界。
const PLAYER_SOURCE_PATH: String = "res://entities/Player.cs"
const HUD_CONTROLLER_SCRIPT: GDScript = preload("res://core/ui/hud/hud_controller.gd")
const BACKPACK_BUTTON_SCRIPT: GDScript = preload("res://core/ui/hud/backpack_button.gd")
const LEGACY_ITEM_DATA_SCRIPT: Script = preload("res://resources/item/ItemData.cs")
const LEGACY_ITEM_STACK_SCRIPT: Script = preload("res://core/inventory/ItemStack.cs")
const LEGACY_DRAGGABLE_DATA_SCRIPT: Script = preload("res://core/ui/draggable/DraggableData.cs")
const SKILL_CARD_PROBE_SCRIPT: GDScript = preload("res://tests/godot/inventory_skill_card_probe.gd")
const LEGACY_ITEM_PATH: String = "res://items/items/applecore.tres"
const PRODUCTION_AX_PATH: String = "res://items/tool/Ax.tres"
const TALENT_CARD_SCENE_PATH: String = "res://scenes/talents/talent_card.tscn"
const TALENT_SCREEN_SCENE_PATH: String = "res://scenes/talents/talent_screen.tscn"
const TALENT_CARD_SCRIPT_PATH: String = "res://resources/talents/talent_card.gd"
const TALENT_MANAGER_SCRIPT_PATH: String = "res://resources/talents/talent_manager.gd"
const TALENT_EFFECT_SCRIPT: GDScript = preload("res://resources/talents/talent_effect.gd")
const TALENT_DATA_SCRIPT: GDScript = preload("res://resources/talents/talent_data.gd")
const ATTRIBUTE_TALENT_EFFECT_SCRIPT: GDScript = preload("res://resources/talents/attribute_talent_effect.gd")
const TAG_TALENT_EFFECT_SCRIPT: GDScript = preload("res://resources/talents/tag_talent_effect.gd")




## 记录装备与套装写入的属性增量，提供 EquipmentComponent 所需的稳定方法名。
class FakeAttributeComponent extends Node:
	## 每种属性当前累计的永久增量。
	var bonuses: Dictionary = {}

	## 增加指定属性的永久增量。
	func AddPermanentBonus(attribute_type: Variant, value: float, _source: Variant = null) -> bool:
		bonuses[attribute_type] = float(bonuses.get(attribute_type, 0.0)) + value
		return true

	## 移除指定属性的永久增量。
	func RemovePermanentBonus(attribute_type: Variant, value: float, _source: Variant = null) -> bool:
		bonuses[attribute_type] = float(bonuses.get(attribute_type, 0.0)) - value
		if is_zero_approx(float(bonuses[attribute_type])):
			bonuses.erase(attribute_type)
		return true


## 记录装备与套装赋予的标签层数，复刻 TagComponent 的叠层边界。
class FakeTagComponent extends Node:
	## 每个 StringName 标签当前拥有的层数。
	var tag_counts: Dictionary = {}

	## 增加一层非空标签。
	func AddTag(tag: StringName) -> void:
		if tag == null or tag.is_empty():
			return
		tag_counts[tag] = int(tag_counts.get(tag, 0)) + 1

	## 移除一层标签，归零后删除键。
	func RemoveTag(tag: StringName) -> void:
		if not tag_counts.has(tag):
			return
		var next_count: int = int(tag_counts[tag]) - 1
		if next_count <= 0:
			tag_counts.erase(tag)
		else:
			tag_counts[tag] = next_count

	## 判断标签当前是否有效。
	func HasTag(tag: StringName) -> bool:
		return tag_counts.has(tag)

	## 读取标签层数。
	func GetTagStack(tag: StringName) -> int:
		return int(tag_counts.get(tag, 0))


## 记录 Presenter 发给 TooltipPanel 的标题、描述和隐藏请求。
class FakeItemTooltipPanel extends Node:
	## 最近一次立即显示请求的标题。
	var shown_title: String = ""
	## 最近一次立即显示请求的描述。
	var shown_description: String = ""
	## 立即显示请求次数。
	var show_count: int = 0
	## 隐藏请求次数。
	var hide_count: int = 0

	## 记录一次立即显示请求。
	## 参数 title_text：Presenter 解析出的物品名称。
	## 参数 description_text：Presenter 解析出的物品描述。
	## 返回值：无。
	func show_tooltip_now(title_text: String, description_text: String) -> void:
		shown_title = title_text
		shown_description = description_text
		show_count += 1

	## 记录一次隐藏请求。
	## 返回值：无。
	func hide_tooltip() -> void:
		hide_count += 1


## 提供 WarehouseUI 使用的最小 GameplayPort 信号边界。
class FakeWarehouseGameplayPort extends Node:
	## 请求仓库面板绑定玩家库存与全局仓库。
	signal WarehouseRequested(player_inventory, warehouse_inventory)
	## GDScript 仓库兼容请求，参数降为 Node。
	signal WarehouseNodeRequested(player_inventory, warehouse_inventory)


## 提供 WarehouseUI 动态生成所需的最小槽位协议，隔离已由独立用例覆盖的 SlotUI 视觉行为。
class FakeWarehouseSlotUI extends PanelContainer:
	## 当前绑定的槽位索引。
	var SlotIndex: int = -1
	## 当前绑定的库存组件。
	var Inventory: Node = null
	## 当前绑定的 ItemStack。
	var CurrentStack: Variant = null
	## WarehouseUI 共享的提示框 Presenter。
	var TooltipPresenter: RefCounted = null
	## InventoryUI 提供的快捷输入回调。
	var ShortcutHandler: Callable = Callable()

	## 保存 WarehouseUI 提供的共享提示框 Presenter。
	## 参数 presenter：跨槽位复用的提示框 Presenter。
	## 返回值：无。
	func SetTooltipPresenter(presenter: RefCounted) -> void:
		TooltipPresenter = presenter

	## 保存 InventoryUI 提供的快捷输入回调。
	## 参数 shortcut_handler：接收槽位与快捷类型整数值的回调。
	## 返回值：无。
	func SetShortcutHandler(shortcut_handler: Callable) -> void:
		ShortcutHandler = shortcut_handler

	## 保存父面板提供的槽位索引、堆叠和库存引用。
	## 参数 index：库存槽位索引。
	## 参数 stack：当前 ItemStack。
	## 参数 inventory：槽位所属库存组件。
	## 返回值：无。
	func Bind(index: int, stack: Variant, inventory: Node) -> void:
		SlotIndex = index
		CurrentStack = stack
		Inventory = inventory


## 提供 InventoryUI 装备槽生成与重绑所需的最小协议。
class FakeInventoryEquipmentSlotUI extends PanelContainer:
	## 当前绑定的装备组件。
	var Equipment: Node = null
	## 当前绑定的装备槽整数值。
	var EquipmentSlot: int = -1
	## 父面板共享的提示框 Presenter。
	var TooltipPresenter: RefCounted = null
	## Bind 被调用的次数，用于验证 EquipmentChanged 重绑。
	var BindCount: int = 0

	## 保存 InventoryUI 提供的共享提示框 Presenter。
	## 参数 presenter：跨槽位复用的提示框 Presenter。
	## 返回值：无。
	func SetTooltipPresenter(presenter: RefCounted) -> void:
		TooltipPresenter = presenter

	## 保存装备组件与槽位整数值。
	## 参数 equipment：当前装备组件。
	## 参数 slot：EquipmentSlot 稳定整数值。
	## 返回值：无。
	func Bind(equipment: Node, slot: int) -> void:
		Equipment = equipment
		EquipmentSlot = slot
		BindCount += 1


## 记录 InventoryUI 传入的属性组件，用最小夹具隔离属性摘要视图内部展示逻辑。
class FakeInventoryAttributeSummaryUI extends PanelContainer:
	## 最近一次绑定的属性组件。
	var BoundAttributes: Node = null

	## 保存父面板解析出的玩家属性组件。
	## 参数 attributes：玩家属性组件。
	## 返回值：无。
	func Bind(attributes: Node) -> void:
		BoundAttributes = attributes


## 提供 InventoryUI 读取的玩家属性与装备引用。
class FakeInventoryPlayer extends Node:
	## 玩家属性组件。
	var Attributes: Node = null
	## 玩家装备组件。
	var Equipment: Node = null


## 提供 InventoryUI 使用的 GameplayPort 请求、玩家与卡组边界。
class FakeInventoryGameplayPort extends Node:
	## 请求切换背包面板。
	signal InventoryToggleRequested(inventory)
	## GDScript InventoryComponent 的动态背包切换请求。
	signal InventoryNodeToggleRequested(inventory)

	## 当前玩家节点。
	var Player: Node = null
	## 当前玩家出战卡组。
	var PlayerBattleDeck: Node = null
	## 打开合成界面的请求次数。
	var CraftingOpenRequestCount: int = 0

	## 记录一次幂等的合成界面打开请求。
	## 返回值：无。
	func RequestOpenCrafting() -> void:
		CraftingOpenRequestCount += 1


## 提供 CraftingUI 使用的最小 GameplayPort 信号边界。
class FakeCraftingGameplayPort extends Node:
	## 合成切换请求信号，参数为旧 C# 或并行 GDScript 组件。
	signal CraftingToggleRequested(crafting)
	## 合成幂等打开请求信号，参数为旧 C# 或并行 GDScript 组件。
	signal CraftingOpenRequested(crafting)
	## GDScript CraftingComponent 的动态切换请求信号。
	signal CraftingNodeToggleRequested(crafting)
	## GDScript CraftingComponent 的动态幂等打开请求信号。
	signal CraftingNodeOpenRequested(crafting)


## 记录 HUD 输入桥的请求次数和请求发生时的 handled 状态。
class FakeHudGameplayPort extends Node:
	## 背包切换请求次数。
	var InventoryToggleRequestCount: int = 0
	## 合成切换请求次数。
	var CraftingToggleRequestCount: int = 0
	## 最近一次背包请求发生时，Viewport 是否已经消费输入。
	var InventoryHandledWhenRequested: bool = false
	## 最近一次合成请求发生时，Viewport 是否已经消费输入。
	var CraftingHandledWhenRequested: bool = false
	## 测试夹具用于观察 handled 时序的隔离 Viewport。
	var ObservedViewport: Viewport = null

	## 记录一次背包切换请求及其输入消费时机。
	## 返回值：无。
	func RequestToggleInventory() -> void:
		InventoryToggleRequestCount += 1
		InventoryHandledWhenRequested = ObservedViewport.is_input_handled()

	## 记录一次合成切换请求及其输入消费时机。
	## 返回值：无。
	func RequestToggleCrafting() -> void:
		CraftingToggleRequestCount += 1
		CraftingHandledWhenRequested = ObservedViewport.is_input_handled()


## 记录 InventoryUI 委托的最佳装备槽请求。
class FakeInventoryEquipment extends Node:
	## 装备状态变化信号。
	signal EquipmentChanged

	## 最佳槽位装备请求次数。
	var EquipBestSlotCallCount: int = 0
	## 最近一次请求的来源库存。
	var LastSourceInventory: Node = null
	## 最近一次请求的来源槽位。
	var LastSourceIndex: int = -1

	## 记录一次从背包装备到最佳槽位的请求。
	## 参数 source_inventory：来源背包。
	## 参数 from_index：来源槽位索引。
	## 返回值：始终返回 true，表示组件接受了测试请求。
	func EquipFromInventoryToBestSlot(source_inventory: Node, from_index: int) -> bool:
		EquipBestSlotCallCount += 1
		LastSourceInventory = source_inventory
		LastSourceIndex = from_index
		return true


## 返回 GodotAI 聚焦执行使用的稳定套件名。
func suite_name() -> String:
	return "inventory_component_contract"


## 验证玩家根脚本只通过稳定方法协议访问库存，不再要求具体 C# InventoryComponent。
## 返回值：无。
func test_player_inventory_access_uses_node_protocol() -> void:
	var player_source: String = FileAccess.get_file_as_string(PLAYER_SOURCE_PATH)
	assert_false(player_source.is_empty(), "Player.cs 必须能够以 UTF-8 文本读取。")
	assert_true(player_source.contains("private Node _inventory;"), "Player 库存字段必须使用通用 Node 边界。")
	assert_true(player_source.contains("GetNode<Node>(\"Components/InventoryComponent\")"), "Player 必须按稳定节点路径解析任一语言库存。")
	assert_true(player_source.contains("_inventory.Call(\"AddItem\", item, amount)"), "加入物品必须从跨语言堆叠读取稳定属性并委托库存的 AddItem 协议。")
	assert_false(player_source.contains("GetNode<InventoryComponent>(\"Components/InventoryComponent\")"), "Player 不得继续强制转换玩家库存为 C# InventoryComponent。")


## 验证玩家和采集链只通过稳定方法协议读取装备组件。
## 返回值：无。
func test_player_equipment_consumers_use_node_protocol() -> void:
	var player_source: String = FileAccess.get_file_as_string(PLAYER_SOURCE_PATH)
	var coordinator_source: String = FileAccess.get_file_as_string("res://core/gameflow/WorldInteractionCoordinator.cs")
	var executor_source: String = FileAccess.get_file_as_string("res://core/gameflow/TerrainInteractionExecutor.cs")
	var gathering_source: String = FileAccess.get_file_as_string("res://resources/interaction/GatheringInteraction.cs")
	var reusable_source: String = FileAccess.get_file_as_string("res://resources/interaction/ReusableGatheringInteraction.cs")
	assert_true(player_source.contains("public Node Equipment { get; private set; }"), "Player.Equipment 必须暴露通用 Node 边界。")
	assert_true(player_source.contains("GetNode<Node>(\"Components/EquipmentComponent\")"), "Player 必须按稳定节点路径解析任一语言装备组件。")
	assert_true(coordinator_source.contains("GetReusableEffectiveTimeCost(Resource interaction, Node equipment)"), "长按耗时入口必须接受通用装备节点。")
	assert_true(executor_source.contains("equipment.Call(\"GetNightEncounterChanceMultiplier\")"), "采集遭遇必须动态读取夜晚装备倍率。")
	assert_true(gathering_source.contains("Equipment.Call(\"GetGatheringYieldBonus\", GatheringTag)"), "一次性采集必须动态读取额外产量。")
	assert_true(reusable_source.contains("GetEffectiveTimeCost(Node equipment)"), "旧可重复采集兼容资源必须接受通用装备节点。")
	assert_true(reusable_source.contains("equipment.Call(\"GetGatheringTimeReduction\", GatheringTag, (int)EffectiveToolSlot)"), "旧可重复采集必须动态读取工具减免。")
	assert_false(player_source.contains("GetNode<EquipmentComponent>(\"Components/EquipmentComponent\")"), "Player 不得继续强制转换装备组件为 C# EquipmentComponent。")


## 验证玩家生产场景已经切换到 GDScript EquipmentComponent，并保留无 out 查询入口。
## 返回值：无。
func test_player_equipment_production_uses_gdscript() -> void:
	var player_scene := ResourceLoader.load("res://scenes/player_scenes/player.tscn", "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	assert_true(player_scene != null, "玩家生产场景必须能够加载。")
	if player_scene == null:
		return
	var player := player_scene.instantiate() as Node
	var equipment := player.get_node_or_null("Components/EquipmentComponent")
	assert_true(equipment != null, "玩家生产场景必须保留 EquipmentComponent 节点。")
	if equipment != null:
		var equipment_script := equipment.get_script() as Script
		assert_true(equipment_script != null, "生产装备组件必须保留脚本。")
		if equipment_script != null:
			assert_eq(equipment_script.resource_path, "res://entities/components/equipment_component.gd", "生产装备组件必须使用 GDScript。")
		assert_true(equipment.has_method("GetEquippedStack"), "生产装备组件必须保留无 out 参数查询入口。")
		assert_true(equipment.has_signal("EquipmentChanged"), "生产装备组件必须保留 EquipmentChanged 信号。")
	player.free()


## 验证玩家卡组及战斗请求通过 Node 边界切换为 GDScript，同时保留技能卡数组过滤。
## 返回值：无。
func test_player_battle_deck_production_uses_gdscript() -> void:
	var player_source: String = FileAccess.get_file_as_string(PLAYER_SOURCE_PATH)
	var port_source: String = FileAccess.get_file_as_string("res://core/application/GameplayPort.cs")
	assert_true(player_source.contains("public Node BattleDeck { get; private set; }"), "Player.BattleDeck 必须使用通用 Node 边界。")
	assert_true(port_source.contains("public Node PlayerBattleDeck"), "GameplayPort 必须暴露通用卡组节点。")
	assert_true(port_source.contains("public Array<Resource> GetPlayerSkillCards()"), "GameplayPort 必须提供跨语言技能卡 Resource 数组出口。")
	assert_true(port_source.contains("rawCard.AsGodotObject() is Resource skillCard") and port_source.contains('skillCard.HasMethod("ApplyEffect")'), "卡组出口必须按稳定方法过滤无效 Resource 元素。")
	var player_scene := ResourceLoader.load("res://scenes/player_scenes/player.tscn", "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	assert_true(player_scene != null, "玩家生产场景必须能够加载。")
	if player_scene == null:
		return
	var player := player_scene.instantiate() as Node
	var battle_deck := player.get_node_or_null("Components/BattleDeckComponent")
	assert_true(battle_deck != null, "玩家生产场景必须保留 BattleDeckComponent 节点。")
	if battle_deck != null:
		var deck_script := battle_deck.get_script() as Script
		assert_true(deck_script != null, "生产卡组必须保留脚本。")
		if deck_script != null:
			assert_eq(deck_script.resource_path, "res://entities/components/battle_deck_component.gd", "生产卡组必须使用 GDScript。")
		assert_true(battle_deck.has_method("GetSkillCards"), "生产卡组必须保留技能卡展开入口。")
	player.free()


## 验证玩家普通库存与卡组共享同一 GDScript 库存协议，不再形成半切换边界。
## 返回值：无。
func test_player_inventory_production_uses_gdscript() -> void:
	var player_scene := ResourceLoader.load("res://scenes/player_scenes/player.tscn", "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	assert_true(player_scene != null, "玩家生产场景必须能够加载。")
	if player_scene == null:
		return
	var player := player_scene.instantiate() as Node
	var inventory := player.get_node_or_null("Components/InventoryComponent")
	var battle_deck := player.get_node_or_null("Components/BattleDeckComponent")
	assert_true(inventory != null, "玩家生产场景必须保留 InventoryComponent 节点。")
	assert_true(battle_deck != null, "玩家生产场景必须保留 BattleDeckComponent 节点。")
	if inventory != null:
		var inventory_script := inventory.get_script() as Script
		assert_true(inventory_script != null, "生产玩家库存必须保留脚本。")
		if inventory_script != null:
			assert_eq(inventory_script.resource_path, "res://entities/components/inventory_component.gd", "生产玩家库存必须使用 GDScript。")
		assert_true(inventory.has_method("TryMoveStackToFirstAvailableSlot"), "生产玩家库存必须保留跨库存移动入口。")
	if battle_deck != null:
		assert_true(battle_deck.is_class("Node"), "生产卡组必须保持 Node 组件结构。")
		assert_true(battle_deck.has_method("TryMoveStackToFirstAvailableSlot"), "生产卡组必须继承同一跨库存移动协议。")
	player.free()


## 验证共享背包 UI 链的四个生产场景全部使用 GDScript。
## 返回值：无。
func test_inventory_shared_ui_scenes_use_gdscript() -> void:
	## 生产场景路径到预期 GDScript 路径的稳定映射。
	var expected_scripts: Dictionary = {
		SLOT_UI_SCENE_PATH: "res://core/ui/slot_ui.gd",
		EQUIPMENT_SLOT_UI_SCENE_PATH: "res://core/ui/equipment_slot_ui.gd",
		INVENTORY_UI_SCENE_PATH: "res://core/ui/inventory_ui.gd",
		WAREHOUSE_UI_SCENE_PATH: "res://core/ui/warehouse/warehouse_ui.gd",
		CRAFTING_UI_SCENE_PATH: "res://core/ui/crafting/crafting_ui.gd",
	}
	for scene_path: String in expected_scripts:
		## 强制从磁盘读取的生产 UI 场景。
		var packed_scene := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
		assert_true(packed_scene != null, "%s 必须能够加载。" % scene_path)
		if packed_scene == null:
			continue
		## 未进入场景树的生产 UI 根节点。
		var root := packed_scene.instantiate() as Control
		## 生产根节点当前实际挂载的脚本。
		var script := root.get_script() as Script
		assert_true(script != null, "%s 根节点必须保留脚本。" % scene_path)
		if script != null:
			assert_eq(script.resource_path, expected_scripts[scene_path], "%s 必须使用预期 GDScript。" % scene_path)
		root.free()


## 验证 Main 生产实例没有再用 C# 覆盖共享背包 UI 场景脚本。
func test_main_shared_ui_instances_use_gdscript() -> void:
	var main_scene := ResourceLoader.load("res://scenes/Main.tscn", "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	assert_true(main_scene != null, "Main 场景必须能够加载。")
	if main_scene == null:
		return
	var main_root := main_scene.instantiate() as Node
	var inventory_ui := main_root.get_node("UI/HUDLayer/HUDRoot/CenterOverlay/InventoryUI") as Control
	var warehouse_ui := main_root.get_node("UI/HUDLayer/HUDRoot/CenterOverlay/WarehouseUI") as Control
	assert_true(inventory_ui != null, "Main 必须包含 InventoryUI。")
	assert_true(warehouse_ui != null, "Main 必须包含 WarehouseUI。")
	if inventory_ui != null:
		var inventory_script := inventory_ui.get_script() as Script
		assert_true(inventory_script != null, "Main InventoryUI 必须保留脚本。")
		if inventory_script != null:
			assert_eq(inventory_script.resource_path, "res://core/ui/inventory_ui.gd", "Main InventoryUI 必须使用 GDScript。")
	if warehouse_ui != null:
		var warehouse_script := warehouse_ui.get_script() as Script
		assert_true(warehouse_script != null, "Main WarehouseUI 必须保留脚本。")
		if warehouse_script != null:
			assert_eq(warehouse_script.resource_path, "res://core/ui/warehouse/warehouse_ui.gd", "Main WarehouseUI 必须使用 GDScript。")
	main_root.free()


## 验证 CraftingUI 生产脚本保持配方展示、数量刷新、合成和 GameplayPort 请求契约。
func test_crafting_ui_preserves_cross_language_contract() -> void:
	var host := track(Node.new()) as Node
	var production_scene_root := CRAFTING_UI_SCENE.instantiate() as Control
	var crafting_ui: Control = CRAFTING_UI_SCRIPT.new() as Control
	crafting_ui.name = production_scene_root.name
	for production_child in production_scene_root.get_children():
		production_scene_root.remove_child(production_child)
		production_child.owner = null
		crafting_ui.add_child(production_child)
		production_child.owner = crafting_ui
		_assign_owner_recursive(production_child, crafting_ui)
	production_scene_root.free()
	host.add_child(crafting_ui)
	var gameplay_port := FakeCraftingGameplayPort.new()
	gameplay_port.name = "GameplayPort"
	host.add_child(gameplay_port)
	crafting_ui.set("GameplayPortPath", NodePath("../GameplayPort"))

	var component_owner := Node.new()
	component_owner.name = "Components"
	host.add_child(component_owner)
	var inventory: Node = INVENTORY_SCRIPT.new()
	inventory.name = "InventoryComponent"
	inventory.Capacity = 2
	component_owner.add_child(inventory)
	var component: Node = CRAFTING_COMPONENT_SCRIPT.new()
	component.name = "CraftingComponent"
	component_owner.add_child(component)

	var material: Resource = _new_item(&"crafting_ui_material", "UI 材料", 99)
	var output: Resource = _new_item(&"crafting_ui_output", "UI 产物", 2)
	var ingredient: Resource = CRAFTING_INGREDIENT_SCRIPT.new()
	ingredient.set("RequiredItem", material)
	ingredient.set("Amount", 2)
	var recipe: Resource = CRAFTING_RECIPE_SCRIPT.new()
	recipe.set("RecipeName", "UI 合成表")
	var inputs: Array[Resource] = [ingredient]
	recipe.set("Inputs", inputs)
	recipe.set("OutputItem", output)
	recipe.set("OutputAmount", 2)
	var book: Resource = RECIPE_BOOK_SCRIPT.new()
	var recipes: Array[Resource] = [recipe]
	book.set("Recipes", recipes)
	component.set("RecipeBook", book)

	# 非场景树夹具显式执行生命周期，复用生产节点的同级解析时序。
	inventory.call("_ready")
	component.call("_ready")
	inventory.call("AddItem", material, 2)
	crafting_ui.call("_ready")
	assert_false(crafting_ui.visible, "CraftingUI 初始化后必须隐藏。")

	gameplay_port.CraftingOpenRequested.emit(component)
	assert_true(crafting_ui.visible, "CraftingOpenRequested 必须幂等打开合成面板。")
	var recipe_grid := crafting_ui.get_node("%RecipeGrid") as GridContainer
	assert_eq(recipe_grid.get_child_count(), 1, "合成面板必须按配方数量生成按钮。")
	assert_eq(crafting_ui.get_node("%OutputNameLabel").text, "UI 合成表", "配方标题必须优先使用 RecipeName。")
	var ingredient_text := (crafting_ui.get_node("%IngredientList").get_child(0).get_child(1) as Label).text
	assert_true(ingredient_text.contains("需要 2 / 拥有 2"), "材料行必须显示需求与当前持有数量。")

	var craft_button := crafting_ui.get_node("%CraftButton") as Button
	craft_button.pressed.emit()
	assert_eq(inventory.call("ItemCnt", material), 0, "CraftingUI 合成必须委托组件扣除材料。")
	assert_eq(inventory.call("ItemCnt", output), 2, "CraftingUI 合成必须委托组件加入产物。")
	assert_true(crafting_ui.get_node("%StatusLabel").text.contains("UI 产物"), "成功合成后必须显示产物结果。")

	var close_button := crafting_ui.get_node("%CloseButton") as Button
	close_button.pressed.emit()
	assert_false(crafting_ui.visible, "关闭按钮必须隐藏合成面板。")
	gameplay_port.CraftingNodeOpenRequested.emit(component)
	assert_true(crafting_ui.visible, "CraftingNodeOpenRequested 必须幂等打开合成面板。")
	crafting_ui.call("Close")
	crafting_ui.call("_exit_tree")
	assert_false(gameplay_port.CraftingNodeToggleRequested.is_connected(Callable(crafting_ui, "_handle_crafting_toggle_request")), "退出时必须解除动态合成切换信号。")
	assert_false(gameplay_port.CraftingNodeOpenRequested.is_connected(Callable(crafting_ui, "_handle_crafting_open_request")), "退出时必须解除动态合成打开信号。")


## 创建具有指定字段的并行 ItemData，避免测试依赖生产资产修改。
func _new_item(identifier: StringName, name: String, max_stack: int) -> Resource:
	var item: Resource = ITEM_DATA_SCRIPT.new()
	item.set("CardId", identifier)
	item.set("CardName", name)
	item.set("MaxStackSize", max_stack)
	return item


## 创建并行技能卡，确保测试对象真正暴露 Skill 属性。
func _new_skill_card(identifier: StringName, name: String) -> Resource:
	var card: Resource = SKILL_CARD_PROBE_SCRIPT.new()
	card.set("CardId", identifier)
	card.set("CardName", name)
	card.set("MaxStackSize", 1)
	card.set("Skill", Resource.new())
	return card


## 创建包含属性、标签和并行装备组件的轻量 Components 节点。
func _new_equipment_context() -> Dictionary:
	var components: Node = track(Node.new()) as Node
	components.name = "Components"
	var attributes: FakeAttributeComponent = FakeAttributeComponent.new()
	attributes.name = "AttributeComponent"
	components.add_child(attributes)
	var tags: FakeTagComponent = FakeTagComponent.new()
	tags.name = "TagComponent"
	components.add_child(tags)
	var equipment: Node = EQUIPMENT_COMPONENT_SCRIPT.new()
	equipment.name = "EquipmentComponent"
	components.add_child(equipment)
	# 测试节点不进入 SceneTree，显式调用 _ready 复用与生产场景相同的同级解析路径。
	equipment._ready()
	return {
		"root": components,
		"attributes": attributes,
		"tags": tags,
		"equipment": equipment,
	}


## 创建保存指定装备 Resource 的并行 ItemStack。
func _new_stack(item: Resource, rolled_attributes: Dictionary = {}) -> Variant:
	var stack: Variant = ITEM_STACK_SCRIPT.new()
	stack.call("SetItem", item, 1)
	stack.set("RolledAttributes", rolled_attributes.duplicate(true))
	return stack


## 创建与生产 EquipmentSlotUI.tscn 相同必需节点路径的轻量 UI。
func _new_equipment_slot_ui() -> PanelContainer:
	var slot_ui: PanelContainer = track(EQUIPMENT_SLOT_UI_SCRIPT.new()) as PanelContainer
	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	slot_ui.add_child(margin)
	var column := VBoxContainer.new()
	column.name = "VBoxContainer"
	margin.add_child(column)
	var slot_label := Label.new()
	slot_label.name = "SlotLabel"
	column.add_child(slot_label)
	var icon := TextureRect.new()
	icon.name = "ItemIcon"
	column.add_child(icon)
	var amount_label := Label.new()
	amount_label.name = "AmountLabel"
	column.add_child(amount_label)
	slot_ui._ready()
	return slot_ui


## 创建与生产 SlotUI.tscn 相同必需节点路径的轻量 UI。
func _new_slot_ui() -> PanelContainer:
	var slot_ui: PanelContainer = track(SLOT_UI_SCRIPT.new()) as PanelContainer
	var icon := TextureRect.new()
	icon.name = "ItemIcon"
	slot_ui.add_child(icon)
	var amount_label := Label.new()
	amount_label.name = "AmountLabel"
	slot_ui.add_child(amount_label)
	slot_ui._ready()
	return slot_ui


## 打包一个实现稳定槽位协议的测试场景，供 WarehouseUI 动态生成。
func _new_slot_ui_packed_scene() -> PackedScene:
	var slot_ui := FakeWarehouseSlotUI.new()
	slot_ui.name = "SlotUI"
	var packed_scene := PackedScene.new()
	packed_scene.pack(slot_ui)
	slot_ui.free()
	return packed_scene


## 打包一个实现装备槽稳定协议的测试场景，供 InventoryUI 动态生成。
func _new_equipment_slot_ui_packed_scene() -> PackedScene:
	var slot_ui := FakeInventoryEquipmentSlotUI.new()
	slot_ui.name = "EquipmentSlotUI"
	var packed_scene := PackedScene.new()
	packed_scene.pack(slot_ui)
	slot_ui.free()
	return packed_scene


## 把生产场景子树的 owner 改为并行 GDScript 根，保留 % 唯一节点查找。
func _assign_owner_recursive(node: Node, new_owner: Node) -> void:
	for child in node.get_children():
		child.owner = new_owner
		_assign_owner_recursive(child, new_owner)


## 创建与指定动作临时匹配的键盘按下事件。
## 参数 action：需要映射的动作名。
## 参数 echo：是否模拟操作系统的键盘重复事件。
## 返回值：包含运行时事件、临时映射和动作是否由夹具创建的字典。
func _new_key_action_fixture(action: StringName, echo: bool) -> Dictionary:
	var added_action: bool = false
	if not InputMap.has_action(action):
		InputMap.add_action(action)
		added_action = true
	var mapping_event := InputEventKey.new()
	mapping_event.physical_keycode = KEY_F12
	InputMap.action_add_event(action, mapping_event)
	var input_event: InputEventKey = mapping_event.duplicate() as InputEventKey
	input_event.pressed = true
	input_event.echo = echo
	return {
		"added_action": added_action,
		"input_event": input_event,
		"mapping_event": mapping_event,
	}


## 移除键盘动作夹具，避免聚焦测试污染编辑器后续输入。
## 参数 action：夹具绑定的动作名。
## 参数 fixture：_new_key_action_fixture 返回的字典。
## 返回值：无。
func _remove_key_action_fixture(action: StringName, fixture: Dictionary) -> void:
	InputMap.action_erase_event(action, fixture["mapping_event"] as InputEvent)
	if bool(fixture["added_action"]):
		InputMap.erase_action(action)


## 创建 HUDController 及其最小场景依赖。
## 返回值：包含独立 Viewport、HUD、GameplayPort 和按钮的测试夹具。
func _new_hud_input_fixture() -> Dictionary:
	var viewport: SubViewport = track(SubViewport.new()) as SubViewport
	var hud: Control = HUD_CONTROLLER_SCRIPT.new() as Control
	hud.name = "HUDRoot"
	viewport.add_child(hud)
	var gameplay_port := FakeHudGameplayPort.new()
	gameplay_port.name = "GameplayPort"
	gameplay_port.ObservedViewport = viewport
	hud.add_child(gameplay_port)
	var backpack_button := Button.new()
	backpack_button.name = "BackpackButton"
	hud.add_child(backpack_button)
	hud.set("GameplayPortPath", NodePath("GameplayPort"))
	hud.set("BackpackButtonPath", NodePath("BackpackButton"))
	var scene_tree := Engine.get_main_loop() as SceneTree
	# 挂入编辑器 SceneTree 后，HUD 可使用真实 Viewport handled 状态，且隔离 SubViewport 不影响当前场景。
	scene_tree.root.add_child(viewport)
	return {
		"viewport": viewport,
		"hud": hud,
		"gameplay_port": gameplay_port,
		"backpack_button": backpack_button,
	}


## 验证固定槽位、同一 Resource 身份合并和容量溢出规则。
func test_inventory_fixed_slots_and_identity_stacking() -> void:
	var inventory: Node = track(INVENTORY_SCRIPT.new()) as Node
	var item: Resource = _new_item(&"wood", "木材", 3)
	var other_instance: Resource = _new_item(&"wood", "木材", 3)
	var changes: Array[int] = [0]
	inventory.InventoryChanged.connect(func() -> void: changes[0] += 1)
	inventory.Capacity = 2
	inventory.AddItem(item, 4)
	assert_eq(inventory.GetStackAt(0).get("Amount"), 3, "同一物品应先填满第一个堆叠。")
	assert_eq(inventory.GetStackAt(1).get("Amount"), 1, "溢出数量应进入下一个空槽。")
	assert_eq(inventory.ItemCnt(item), 4, "引用相同的物品应累计总数量。")
	assert_eq(inventory.ItemCnt(other_instance), 0, "不同 Resource 实例不得合并计数。")
	assert_eq(inventory.AddItem(item, 3), 1, "容量用尽后应返回未放入数量。")
	assert_true(changes[0] >= 2, "成功加入物品后应发出 InventoryChanged。")


## 验证出战卡组的技能卡过滤、扩容和尾部空槽契约。
func test_battle_deck_expands_and_keeps_trailing_empty_slot() -> void:
	var deck: Node = BATTLE_DECK_SCRIPT.new()
	var skill_card: Resource = _new_skill_card(&"skill", "测试技能")
	var regular_item: Resource = _new_item(&"regular", "普通物品", 1)
	var initial_capacity: int = int(deck.Capacity)
	assert_false(bool(deck.CanAddItem(regular_item, 1)), "出战卡组不得接收普通物品。")
	assert_true(bool(deck.CanAddItem(skill_card, initial_capacity + 1)), "技能卡批量加入前应允许自动扩容。")
	assert_eq(deck.AddItem(skill_card, initial_capacity + 1), 0, "出战卡组应完整接收超过初始容量的技能卡。")
	assert_eq(deck.GetSkillCards().size(), initial_capacity + 1, "技能卡列表应按数量展开。")
	assert_eq(deck.Capacity, initial_capacity + 2, "满载后应扩容并额外保留尾部空槽。")
	assert_true(bool(deck.GetStackAt(deck.Capacity - 1).get("IsEmpty")), "尾部槽位必须保持为空。")


## 验证跨库存移动只复制堆叠状态、不交换 Item Resource 身份。
func test_inventory_move_and_batch_signal_contract() -> void:
	var source: Node = INVENTORY_SCRIPT.new()
	var target: Node = WAREHOUSE_SCRIPT.new()
	source.Capacity = 2
	target.Capacity = 2
	var item: Resource = _new_item(&"ore", "矿石", 5)
	source.AddItem(item, 4)
	var source_changes: Array[int] = [0]
	var target_changes: Array[int] = [0]
	source.InventoryChanged.connect(func() -> void: source_changes[0] += 1)
	target.InventoryChanged.connect(func() -> void: target_changes[0] += 1)
	var moved: int = source.MoveAllMatchingStacksTo(target, func(candidate: Resource) -> bool: return bool(ITEM_DATA_COMPAT.call("same_item", candidate, item)))
	assert_eq(moved, 4, "批量移动应返回实际移动数量。")
	assert_true(bool(source.GetStackAt(0).get("IsEmpty")), "移动成功后来源槽位应清空。")
	assert_eq(target.GetStackAt(0).get("Amount"), 4, "目标槽位应接收完整堆叠。")
	assert_true(target.GetStackAt(0).get("Item") == item, "目标堆叠必须保留原始 Item Resource 身份。")
	assert_eq(source_changes[0], 1, "成功批量移动应只通知来源库存一次。")
	assert_eq(target_changes[0], 1, "成功批量移动应只通知目标库存一次。")


## 验证排序、标签查询、原子移除和旧 C# 物品资源兼容输入。
func test_inventory_sort_tags_atomic_remove_and_legacy_resource() -> void:
	var inventory: Node = INVENTORY_SCRIPT.new()
	inventory.Capacity = 3
	var first: Resource = _new_item(&"b", "B", 9)
	var second: Resource = _new_item(&"a", "A", 9)
	var ore_tags: Array[StringName] = [&"ore"]
	first.set("ItemTags", ore_tags)
	second.set("ItemTags", ore_tags)
	inventory.AddItem(first, 2)
	inventory.AddItem(second, 1)
	inventory.SortByCardName()
	assert_eq(inventory.GetStackAt(0).get("Item"), second, "排序应按 CardName 升序。")
	assert_eq(inventory.GetTotalAmountByTag(&"ore"), 3, "标签查询应累计所有匹配堆叠。")
	assert_false(inventory.TryRemoveItems({first: 3, second: 1}), "任一需求不足时批量移除应整体失败。")
	assert_eq(inventory.ItemCnt(first), 2, "批量移除失败不得改变已存在的槽位。")
	assert_true(inventory.TryRemoveItems({first: 2, second: 1}), "满足全部需求时批量移除应成功。")
	var legacy_item: Resource = load(LEGACY_ITEM_PATH)
	assert_true(legacy_item != null, "旧 C# 物品资源必须能作为并行库存输入加载。")
	if legacy_item != null:
		assert_true(bool(ITEM_DATA_COMPAT.call("is_item_resource", legacy_item)), "旧 C# ItemData 应通过兼容字段检查。")
		assert_eq(inventory.AddItem(legacy_item, 1), 0, "并行库存应接受旧 C# ItemData Resource。")


## 验证生产装备组件接受 GDScript 工具并保持槽位、采集和信号契约。
func test_equipment_component_production_tool_contract() -> void:
	var context: Dictionary = _new_equipment_context()
	var equipment: Node = context.equipment
	var tags: FakeTagComponent = context.tags
	var production_ax := ResourceLoader.load(PRODUCTION_AX_PATH, "Resource", ResourceLoader.CACHE_MODE_REPLACE) as Resource
	assert_true(production_ax != null, "生产 GDScript 斧头资源必须可加载。")
	if production_ax == null:
		return
	assert_eq(production_ax.get_script().resource_path, "res://resources/item/tool/tool_data.gd", "生产斧头必须使用 GDScript ToolData。")
	var stack: Variant = _new_stack(production_ax)
	var axe_slot: int = int(EQUIPMENT_TYPES.EquipmentSlot.Axe)
	var weapon_slot: int = int(EQUIPMENT_TYPES.EquipmentSlot.Weapon)
	assert_true(bool(EQUIPMENT_COMPONENT_SCRIPT.CanEquipStack(stack, axe_slot)), "显式 Axe=5 槽位必须允许生产斧头。")
	assert_false(bool(EQUIPMENT_COMPONENT_SCRIPT.CanEquipStack(stack, weapon_slot)), "显式槽位存在时不能用 CardId 兜底到 Weapon。")
	var changes: Array[int] = [0]
	equipment.EquipmentChanged.connect(func() -> void: changes[0] += 1)
	assert_true(bool(equipment.Equip(stack, axe_slot)), "生产 GDScript 工具必须能装备到生产组件。")
	var equipped_stack: Variant = equipment.TryGetEquippedStack(axe_slot)
	assert_true(equipped_stack != null, "装备后必须能读取槽位堆叠。")
	assert_true(equipped_stack != stack, "装备组件必须保存独立 ItemStack 副本。")
	assert_true(equipped_stack.get("Item") == production_ax, "堆叠副本必须保留原 ToolData Resource 身份。")
	assert_eq(equipment.GetGatheringYieldBonus(&"wood"), 0, "生产斧头默认额外产量必须保持 0。")
	assert_eq(equipment.GetGatheringTimeReduction(&"wood", axe_slot), 10, "生产斧头必须减少 10 点采集时间。")
	assert_eq(equipment.GetGatheringTimeReduction(&"earth", axe_slot), 0, "采集标签不匹配时不得减免。")
	assert_false(tags.HasTag(&"unused"), "未配置标签时不得注入额外标签。")
	equipment.Unequip(axe_slot)
	assert_true(equipment.TryGetEquippedStack(axe_slot) == null, "卸下后槽位必须为空。")

	var gd_tool: Resource = TOOL_DATA_SCRIPT.new()
	gd_tool.set("CardId", &"GdAxe")
	gd_tool.set("CardName", "GDScript 斧头")
	var gd_slots: Array[int] = [axe_slot]
	gd_tool.set("ValidSlots", gd_slots)
	gd_tool.set("TargetGatheringTag", &"wood")
	gd_tool.set("YieldGrowth", 3)
	gd_tool.set("GatheringTimeReduction", 12)
	var gd_tags: Array[StringName] = [&"gd_tool_tag"]
	gd_tool.set("GrantedTags", gd_tags)
	assert_true(equipment.Equip(_new_stack(gd_tool), axe_slot), "GDScript 工具必须能装备到并行组件。")
	assert_eq(equipment.GetGatheringYieldBonus(&"wood"), 3, "GDScript 工具额外产量必须参与汇总。")
	assert_eq(equipment.GetGatheringTimeReduction(&"wood", axe_slot), 12, "GDScript 工具时间减免必须保留。")
	assert_true(tags.HasTag(&"gd_tool_tag"), "GDScript 工具 GrantedTags 必须应用。")
	equipment.Unequip(axe_slot)
	assert_false(tags.HasTag(&"gd_tool_tag"), "卸下 GDScript 工具必须撤销 GrantedTags。")
	assert_eq(changes[0], 4, "两次装备与两次卸下必须各发出一次 EquipmentChanged。")


## 验证属性、标签与两件套阶级在装备变化时精确应用和撤销。
func test_equipment_component_item_and_set_effects() -> void:
	var context: Dictionary = _new_equipment_context()
	var equipment: Node = context.equipment
	var attributes: FakeAttributeComponent = context.attributes
	var tags: FakeTagComponent = context.tags

	var tier: Resource = SET_BONUS_TIER_SCRIPT.new()
	tier.set("RequiredPieces", 2)
	tier.set("AttributeBonuses", {4: 2.5})
	var tier_tags: Array[StringName] = [&"wooden_set_bonus"]
	tier.set("GrantedTags", tier_tags)
	var set_data: Resource = EQUIPMENT_SET_DATA_SCRIPT.new()
	set_data.set("SetType", int(EQUIPMENT_TYPES.EquipmentSet.Wooden))
	var tiers: Array[Resource] = [tier]
	set_data.set("Tiers", tiers)
	var set_database: Array[Resource] = [set_data]
	equipment.AllSetDatabase = set_database

	var helmet: Resource = EQUIPMENT_DATA_SCRIPT.new()
	_set_equipment_fields(helmet, &"WoodHelmet", int(EQUIPMENT_TYPES.EquipmentSlot.Helmet), &"helmet_tag")
	var chest: Resource = EQUIPMENT_DATA_SCRIPT.new()
	_set_equipment_fields(chest, &"WoodChest", int(EQUIPMENT_TYPES.EquipmentSlot.Chest), &"chest_tag")
	assert_true(equipment.Equip(_new_stack(helmet, {0: 5}), int(EQUIPMENT_TYPES.EquipmentSlot.Helmet)), "木头盔必须装备成功。")
	assert_eq(attributes.bonuses.get(0), 5.0, "装备洗炼属性必须立即应用。")
	assert_true(tags.HasTag(&"helmet_tag"), "装备 GrantedTags 必须立即应用。")
	assert_false(tags.HasTag(&"wooden_set_bonus"), "只有一件木套时不得激活两件套。")
	assert_true(equipment.Equip(_new_stack(chest, {1: 3}), int(EQUIPMENT_TYPES.EquipmentSlot.Chest)), "木胸甲必须装备成功。")
	assert_eq(attributes.bonuses.get(4), 2.5, "达到两件时必须应用套装属性。")
	assert_true(tags.HasTag(&"wooden_set_bonus"), "达到两件时必须应用套装标签。")
	equipment.Unequip(int(EQUIPMENT_TYPES.EquipmentSlot.Chest))
	assert_false(attributes.bonuses.has(1), "卸下胸甲必须撤销自身洗炼属性。")
	assert_false(attributes.bonuses.has(4), "套装不足两件时必须撤销套装属性。")
	assert_false(tags.HasTag(&"chest_tag"), "卸下胸甲必须撤销自身标签。")
	assert_false(tags.HasTag(&"wooden_set_bonus"), "套装不足两件时必须撤销套装标签。")


## 给测试装备写入共同的套装、槽位和标签字段。
func _set_equipment_fields(item: Resource, identifier: StringName, slot: int, tag: StringName) -> void:
	item.set("CardId", identifier)
	item.set("CardName", String(identifier))
	var slots: Array[int] = [slot]
	item.set("ValidSlots", slots)
	item.set("SetType", int(EQUIPMENT_TYPES.EquipmentSet.Wooden))
	var tags: Array[StringName] = [tag]
	item.set("GrantedTags", tags)


## 验证旧标识兜底、火把倍率限制和魔法物品精确标签规则。
func test_equipment_component_tagged_slot_fallbacks() -> void:
	var context: Dictionary = _new_equipment_context()
	var equipment: Node = context.equipment
	var torch: Resource = _new_item(&"flametorch", "火把", 1)
	var torch_stack: Variant = _new_stack(torch)
	var torch_slot: int = int(EQUIPMENT_TYPES.EquipmentSlot.Torch)
	assert_true(bool(EQUIPMENT_COMPONENT_SCRIPT.CanEquipStack(torch_stack, torch_slot)), "旧 flametorch 标识必须允许进入火把槽。")
	equipment.TorchNightEncounterChanceMultiplier = 0.4
	assert_true(equipment.Equip(torch_stack, torch_slot), "火把必须装备成功。")
	assert_eq(equipment.GetNightEncounterChanceMultiplier(), 0.4, "有效火把必须返回配置的夜晚倍率。")
	equipment.TorchNightEncounterChanceMultiplier = -1.0
	assert_eq(equipment.GetNightEncounterChanceMultiplier(), 0.0, "火把倍率必须限制到最小值 0。")
	equipment.Unequip(torch_slot)
	assert_eq(equipment.GetNightEncounterChanceMultiplier(), 1.0, "火把槽为空时必须回退到中性倍率 1。")

	var magic_item: Resource = _new_item(&"ordinary", "魔法物品", 1)
	var magic_tags: Array[StringName] = [&"MagicItem"]
	magic_item.set("ItemTags", magic_tags)
	var magic_stack: Variant = _new_stack(magic_item)
	assert_true(
		bool(EQUIPMENT_COMPONENT_SCRIPT.CanEquipStack(magic_stack, int(EQUIPMENT_TYPES.EquipmentSlot.MagicItem))),
		"MagicItem 精确标签必须允许进入魔法物品槽。"
	)
	var fake_magic: Resource = _new_item(&"MagicItemLike", "伪魔法物品", 1)
	assert_false(
		bool(EQUIPMENT_COMPONENT_SCRIPT.CanEquipStack(_new_stack(fake_magic), int(EQUIPMENT_TYPES.EquipmentSlot.MagicItem))),
		"魔法物品槽不得使用 CardId 片段兜底。"
	)


## 验证快速装备优先两个戒指空槽，并保持库存与装备堆叠互不别名。
func test_equipment_component_inventory_best_slot_contract() -> void:
	var context: Dictionary = _new_equipment_context()
	var equipment: Node = context.equipment
	var inventory: Node = INVENTORY_SCRIPT.new()
	inventory.Capacity = 2
	var first_ring: Resource = EQUIPMENT_DATA_SCRIPT.new()
	_set_equipment_fields(first_ring, &"FirstRing", int(EQUIPMENT_TYPES.EquipmentSlot.Ring1), &"first_ring")
	var first_slots: Array[int] = [int(EQUIPMENT_TYPES.EquipmentSlot.Ring1), int(EQUIPMENT_TYPES.EquipmentSlot.Ring2)]
	first_ring.set("ValidSlots", first_slots)
	var second_ring: Resource = EQUIPMENT_DATA_SCRIPT.new()
	_set_equipment_fields(second_ring, &"SecondRing", int(EQUIPMENT_TYPES.EquipmentSlot.Ring1), &"second_ring")
	second_ring.set("ValidSlots", first_slots)
	inventory.AddItem(first_ring, 1)
	assert_true(equipment.EquipFromInventoryToBestSlot(inventory, 0), "第一枚戒指必须优先进入 Ring1。")
	assert_true(equipment.TryGetEquippedStack(int(EQUIPMENT_TYPES.EquipmentSlot.Ring1)) != null, "Ring1 必须保存第一枚戒指。")
	assert_true(bool(inventory.GetStackAt(0).get("IsEmpty")), "快速装备后来源槽必须清空。")
	inventory.AddItem(second_ring, 1)
	assert_true(equipment.EquipFromInventoryToBestSlot(inventory, 0), "第二枚戒指必须进入仍为空的 Ring2。")
	var second_equipped: Variant = equipment.TryGetEquippedStack(int(EQUIPMENT_TYPES.EquipmentSlot.Ring2))
	assert_true(second_equipped != null, "Ring2 必须保存第二枚戒指。")
	assert_true(second_equipped.get("Item") == second_ring, "Ring2 必须保留第二枚戒指 Resource 身份。")
	assert_true(
		equipment.MoveEquipment(int(EQUIPMENT_TYPES.EquipmentSlot.Ring1), int(EQUIPMENT_TYPES.EquipmentSlot.Ring2)),
		"两枚都允许双戒指槽时必须能够交换。"
	)
	assert_true(
		equipment.TryGetEquippedStack(int(EQUIPMENT_TYPES.EquipmentSlot.Ring1)).get("Item") == second_ring,
		"交换后 Ring1 必须保存第二枚戒指。"
	)
	assert_true(
		equipment.TryGetEquippedStack(int(EQUIPMENT_TYPES.EquipmentSlot.Ring2)).get("Item") == first_ring,
		"交换后 Ring2 必须保存第一枚戒指。"
	)
	assert_true(bool(equipment.CanUnequipToInventory(int(EQUIPMENT_TYPES.EquipmentSlot.Ring1), inventory, 0)), "空库存格必须允许卸下 Ring1。")
	assert_true(equipment.UnequipToInventory(int(EQUIPMENT_TYPES.EquipmentSlot.Ring1), inventory, 0), "Ring1 必须能卸回库存。")
	assert_true(inventory.GetStackAt(0).get("Item") == second_ring, "交换后卸下 Ring1，库存必须得到第二枚戒指。")


## 验证拖拽载荷保持字段名、默认值和跨语言对象引用。
func test_draggable_data_preserves_cross_language_payload() -> void:
	var payload: RefCounted = DRAGGABLE_DATA_SCRIPT.new()
	assert_eq(payload.get("SourceSystem"), &"SystemInventory", "拖拽来源默认值必须保持 SystemInventory。")
	assert_eq(payload.get("FromIndex"), 0, "拖拽来源索引默认值必须保持 0。")
	assert_true(payload.get("SourceInventory") == null, "默认来源库存必须为空。")
	assert_true(payload.get("SourceEquipment") == null, "默认来源装备组件必须为空。")
	assert_eq(payload.get("FromEquipmentSlot"), 0, "默认装备槽必须保持 Helmet=0。")
	assert_true(payload.get("HeldStack") == null, "默认拖拽堆叠必须为空。")

	var inventory: Node = track(INVENTORY_SCRIPT.new()) as Node
	var equipment_context: Dictionary = _new_equipment_context()
	var equipment: Node = equipment_context.equipment
	var item: Resource = _new_item(&"drag_item", "拖拽物品", 1)
	var stack: RefCounted = _new_stack(item)
	payload.set("SourceSystem", &"SystemEquipment")
	payload.set("FromIndex", 3)
	payload.set("SourceInventory", inventory)
	payload.set("SourceEquipment", equipment)
	payload.set("FromEquipmentSlot", int(EQUIPMENT_TYPES.EquipmentSlot.Ring2))
	payload.set("HeldStack", stack)

	assert_eq(payload.get("SourceSystem"), &"SystemEquipment", "装备拖拽来源标识必须保留。")
	assert_eq(payload.get("FromIndex"), 3, "库存来源索引必须保留。")
	assert_true(payload.get("SourceInventory") == inventory, "载荷必须保留来源库存节点身份。")
	assert_true(payload.get("SourceEquipment") == equipment, "载荷必须保留来源装备节点身份。")
	assert_eq(payload.get("FromEquipmentSlot"), 13, "Ring2 槽位整数值必须保留为 13。")
	assert_true(payload.get("HeldStack") == stack, "载荷必须保留原 ItemStack 引用。")


## 验证 Presenter 以同一字段协议显示旧 C# 与新 GDScript 物品和堆叠。
func test_item_tooltip_presenter_accepts_cross_language_items() -> void:
	var panel: FakeItemTooltipPanel = track(FakeItemTooltipPanel.new()) as FakeItemTooltipPanel
	var presenter: RefCounted = ITEM_TOOLTIP_PRESENTER_SCRIPT.new(panel)
	var legacy_item: Resource = LEGACY_ITEM_DATA_SCRIPT.new() as Resource
	legacy_item.set("CardId", &"legacy_tooltip_probe")
	legacy_item.set("CardName", "旧 C# 提示物品")
	legacy_item.set("Description", "旧 C# 物品描述")

	var legacy_stack: RefCounted = LEGACY_ITEM_STACK_SCRIPT.new() as RefCounted
	legacy_stack.call("SetItem", legacy_item, 1)
	presenter.call("Show", legacy_stack)
	assert_eq(panel.shown_title, "旧 C# 提示物品", "旧 C# ItemStack 必须显示 ItemData 名称。")
	assert_eq(panel.shown_description, "旧 C# 物品描述", "旧 C# ItemStack 必须显示 ItemData 描述。")

	var gd_item: Resource = _new_item(&"tooltip_probe", "并行提示物品", 1)
	gd_item.set("Description", "")
	var gd_stack: RefCounted = _new_stack(gd_item) as RefCounted
	presenter.call("Show", gd_stack)
	assert_eq(panel.shown_title, "并行提示物品", "GDScript ItemStack 必须显示 ItemData 名称。")
	assert_eq(panel.shown_description, "暂无描述", "空白描述必须保持既有暂无描述文案。")
	assert_eq(panel.show_count, 2, "两个有效跨语言堆叠必须各产生一次立即显示请求。")

	presenter.call("Show", ITEM_STACK_SCRIPT.new())
	presenter.call("Show", null)
	assert_eq(panel.hide_count, 2, "空堆叠与空值必须各产生一次隐藏请求。")

	var empty_presenter: RefCounted = ITEM_TOOLTIP_PRESENTER_SCRIPT.call("Empty") as RefCounted
	assert_true(empty_presenter == ITEM_TOOLTIP_PRESENTER_SCRIPT.call("Empty"), "空 Presenter 必须保持共享实例语义。")
	empty_presenter.call("Show", gd_item)
	empty_presenter.call("Hide")


## 验证装备槽视图保持槽位文案、视觉、提示框和拖拽载荷协议。
func test_equipment_slot_ui_preserves_visual_and_drag_payload_contract() -> void:
	var equipment_context: Dictionary = _new_equipment_context()
	var equipment: Node = equipment_context.equipment
	var item: Resource = EQUIPMENT_DATA_SCRIPT.new()
	var icon_texture := GradientTexture1D.new()
	item.set("CardId", &"ui_weapon")
	item.set("CardName", "界面武器")
	item.set("Description", "装备槽提示")
	item.set("CardIcon", icon_texture)
	item.set("ValidSlots", [int(EQUIPMENT_TYPES.EquipmentSlot.Weapon)])
	var stack: RefCounted = _new_stack(item) as RefCounted
	assert_true(equipment.Equip(stack, int(EQUIPMENT_TYPES.EquipmentSlot.Weapon)), "夹具武器必须能装备到 Weapon 槽。")

	var panel: FakeItemTooltipPanel = track(FakeItemTooltipPanel.new()) as FakeItemTooltipPanel
	var presenter: RefCounted = ITEM_TOOLTIP_PRESENTER_SCRIPT.new(panel)
	var slot_ui: PanelContainer = _new_equipment_slot_ui()
	slot_ui.call("SetTooltipPresenter", presenter)
	slot_ui.call("Bind", equipment, int(EQUIPMENT_TYPES.EquipmentSlot.Weapon))
	assert_eq(slot_ui.get_node("MarginContainer/VBoxContainer/SlotLabel").text, "武器", "Weapon 槽必须保留中文文案。")
	assert_true(slot_ui.get_node("MarginContainer/VBoxContainer/ItemIcon").texture == icon_texture, "装备槽必须显示原 ItemData 图标。")
	assert_eq(slot_ui.get_node("MarginContainer/VBoxContainer/AmountLabel").text, "", "单件装备不得显示数量。")
	var equipped_stack: RefCounted = equipment.TryGetEquippedStack(int(EQUIPMENT_TYPES.EquipmentSlot.Weapon)) as RefCounted
	equipped_stack.call("SetItem", item, 2)
	assert_eq(slot_ui.get_node("MarginContainer/VBoxContainer/AmountLabel").text, "2", "堆叠变化信号必须刷新装备数量。")

	slot_ui.call("_on_mouse_entered")
	assert_eq(panel.shown_title, "界面武器", "鼠标进入装备槽必须显示物品标题。")
	assert_eq(panel.shown_description, "装备槽提示", "鼠标进入装备槽必须显示物品描述。")
	slot_ui.call("_on_mouse_exited")
	assert_eq(panel.hide_count, 1, "鼠标离开装备槽必须隐藏提示框。")

	var payload: RefCounted = slot_ui.call("_build_drag_data") as RefCounted
	assert_true(payload != null, "非空装备槽必须创建拖拽载荷。")
	assert_eq(payload.get("SourceSystem"), &"SystemEquipment", "装备槽拖拽来源必须保持 SystemEquipment。")
	assert_true(payload.get("SourceEquipment") == equipment, "拖拽载荷必须保留来源装备组件。")
	assert_eq(payload.get("FromEquipmentSlot"), int(EQUIPMENT_TYPES.EquipmentSlot.Weapon), "拖拽载荷必须保留来源槽位。")
	assert_true(payload.get("HeldStack") == equipment.TryGetEquippedStack(int(EQUIPMENT_TYPES.EquipmentSlot.Weapon)), "拖拽载荷必须保留当前装备堆叠引用。")
	assert_true(bool(slot_ui.call("_is_draggable_data", LEGACY_DRAGGABLE_DATA_SCRIPT.new())), "并行装备槽必须识别旧 C# DraggableData。")
	var preview: Control = track(slot_ui.call("_create_drag_preview")) as Control
	var preview_icon: TextureRect = preview.get_child(0) as TextureRect
	assert_true(preview_icon.texture == icon_texture, "拖拽预览必须显示原物品图标。")
	assert_eq(preview_icon.custom_minimum_size, Vector2(64.0, 64.0), "拖拽预览必须保持 64×64 尺寸。")
	assert_true(is_equal_approx(preview_icon.modulate.a, 0.8), "拖拽预览必须保持 0.8 透明度。")


## 验证装备槽把库存装备和槽位互换完整委托给 EquipmentComponent。
func test_equipment_slot_ui_delegates_drop_rules_to_component() -> void:
	var equipment_context: Dictionary = _new_equipment_context()
	var equipment: Node = equipment_context.equipment
	var inventory: Node = track(INVENTORY_SCRIPT.new()) as Node
	inventory.Capacity = 1
	var ring: Resource = EQUIPMENT_DATA_SCRIPT.new()
	ring.set("CardId", &"ui_ring")
	ring.set("CardName", "界面戒指")
	ring.set("ValidSlots", [int(EQUIPMENT_TYPES.EquipmentSlot.Ring1), int(EQUIPMENT_TYPES.EquipmentSlot.Ring2)])
	inventory.TrySetStackAt(0, _new_stack(ring))

	var ring_one_ui: PanelContainer = _new_equipment_slot_ui()
	ring_one_ui.call("Bind", equipment, int(EQUIPMENT_TYPES.EquipmentSlot.Ring1))
	var inventory_payload: RefCounted = DRAGGABLE_DATA_SCRIPT.new()
	inventory_payload.set("SourceInventory", inventory)
	inventory_payload.set("FromIndex", 0)
	assert_true(ring_one_ui._can_drop_data(Vector2.ZERO, inventory_payload), "Ring1 必须接受库存中的双槽戒指。")
	ring_one_ui._drop_data(Vector2.ZERO, inventory_payload)
	assert_true(equipment.TryGetEquippedStack(int(EQUIPMENT_TYPES.EquipmentSlot.Ring1)) != null, "放下后戒指必须装备到 Ring1。")
	assert_true(inventory.GetStackAt(0).get("IsEmpty"), "成功装备后来源库存格必须清空。")
	# 生产 InventoryUI 会在 EquipmentChanged 后重绑全部装备槽；孤立视图夹具显式复刻该步骤。
	ring_one_ui.call("Bind", equipment, int(EQUIPMENT_TYPES.EquipmentSlot.Ring1))

	var ring_two_ui: PanelContainer = _new_equipment_slot_ui()
	ring_two_ui.call("Bind", equipment, int(EQUIPMENT_TYPES.EquipmentSlot.Ring2))
	var equipment_payload: RefCounted = ring_one_ui.call("_build_drag_data") as RefCounted
	assert_true(ring_two_ui._can_drop_data(Vector2.ZERO, equipment_payload), "Ring2 必须接受来自 Ring1 的双槽戒指。")
	ring_two_ui._drop_data(Vector2.ZERO, equipment_payload)
	assert_true(equipment.TryGetEquippedStack(int(EQUIPMENT_TYPES.EquipmentSlot.Ring1)) == null, "槽位移动后 Ring1 必须为空。")
	assert_true(equipment.TryGetEquippedStack(int(EQUIPMENT_TYPES.EquipmentSlot.Ring2)) != null, "槽位移动后 Ring2 必须持有戒指。")


## 验证普通槽位保持公开绑定、视觉、快捷输入、提示框和拖拽载荷协议。
func test_slot_ui_preserves_binding_visual_shortcut_and_drag_contract() -> void:
	var inventory: Node = track(INVENTORY_SCRIPT.new()) as Node
	inventory.Capacity = 1
	var item: Resource = _new_item(&"slot_ui_item", "普通槽位物品", 9)
	var icon_texture := GradientTexture1D.new()
	item.set("CardIcon", icon_texture)
	item.set("Description", "普通槽位提示")
	inventory.TrySetStackAt(0, _new_stack(item))
	var bound_stack: RefCounted = inventory.GetStackAt(0) as RefCounted
	bound_stack.call("SetItem", item, 3)

	var panel: FakeItemTooltipPanel = track(FakeItemTooltipPanel.new()) as FakeItemTooltipPanel
	var presenter: RefCounted = ITEM_TOOLTIP_PRESENTER_SCRIPT.new(panel)
	var slot_ui: PanelContainer = _new_slot_ui()
	slot_ui.call("SetTooltipPresenter", presenter)
	slot_ui.call("Bind", 0, bound_stack, inventory)
	assert_eq(slot_ui.get("SlotIndex"), 0, "公开 SlotIndex 必须返回绑定索引。")
	assert_true(slot_ui.get("Inventory") == inventory, "公开 Inventory 必须返回绑定组件。")
	assert_true(slot_ui.get("CurrentStack") == bound_stack, "公开 CurrentStack 必须保留堆叠引用。")
	assert_true(slot_ui.get_node("ItemIcon").texture == icon_texture, "槽位必须显示原 ItemData 图标。")
	assert_eq(slot_ui.get_node("AmountLabel").text, "3", "多件堆叠必须显示数量。")

	bound_stack.call("Add", 1)
	assert_eq(slot_ui.get_node("AmountLabel").text, "4", "堆叠变化信号必须刷新数量。")
	slot_ui.size = Vector2(48.0, 20.0)
	slot_ui.call("_on_resized")
	assert_true(is_equal_approx(slot_ui.custom_minimum_size.y, slot_ui.size.x), "槽位最小高度必须跟随当前实际宽度。")
	slot_ui.call("_on_mouse_entered")
	assert_eq(panel.shown_title, "普通槽位物品", "鼠标进入必须显示物品标题。")
	slot_ui.call("_on_mouse_exited")
	assert_eq(panel.hide_count, 1, "鼠标离开必须隐藏提示框。")

	var shortcut_events: Array[int] = []
	var shortcut_slots: Array[Variant] = []
	var shortcut_handler: Callable = func(received_slot: Variant, shortcut_kind: int) -> void:
		shortcut_slots.append(received_slot)
		shortcut_events.append(shortcut_kind)
	slot_ui.call("SetShortcutHandler", shortcut_handler)
	var alt_event := InputEventMouseButton.new()
	alt_event.button_index = MOUSE_BUTTON_LEFT
	alt_event.pressed = true
	alt_event.alt_pressed = true
	assert_true(bool(slot_ui.call("_handle_shortcut_input", alt_event)), "Alt+左键必须被识别为快捷输入。")
	var shift_event := InputEventMouseButton.new()
	shift_event.button_index = MOUSE_BUTTON_LEFT
	shift_event.pressed = true
	shift_event.shift_pressed = true
	assert_true(bool(slot_ui.call("_handle_shortcut_input", shift_event)), "Shift+左键必须被识别为快捷输入。")
	assert_eq(shortcut_events, [1, 0], "快捷类型整数值必须保持 AltClick=1、ShiftClick=0。")
	assert_true(shortcut_slots[0] == slot_ui and shortcut_slots[1] == slot_ui, "快捷回调必须收到当前槽位实例。")

	var payload: RefCounted = slot_ui.call("_build_drag_data") as RefCounted
	assert_eq(payload.get("SourceSystem"), &"SystemInventory", "普通背包拖拽来源必须保持 SystemInventory。")
	assert_eq(payload.get("FromIndex"), 0, "拖拽载荷必须保留来源索引。")
	assert_true(payload.get("SourceInventory") == inventory, "拖拽载荷必须保留来源库存组件。")
	assert_true(payload.get("HeldStack") == bound_stack, "拖拽载荷必须保留当前堆叠引用。")
	assert_true(bool(slot_ui.call("_is_draggable_data", LEGACY_DRAGGABLE_DATA_SCRIPT.new())), "并行普通槽必须识别旧 C# DraggableData。")
	var preview: Control = track(slot_ui.call("_create_drag_preview")) as Control
	var preview_icon: TextureRect = preview.get_child(0) as TextureRect
	assert_true(preview_icon.texture == icon_texture, "普通槽拖拽预览必须显示原物品图标。")
	assert_eq(preview_icon.custom_minimum_size, Vector2(64.0, 64.0), "普通槽拖拽预览必须保持 64×64 尺寸。")
	assert_true(is_equal_approx(preview_icon.modulate.a, 0.8), "普通槽拖拽预览必须保持 0.8 透明度。")


## 验证普通槽把库存移动和装备卸下完整委托给对应组件。
func test_slot_ui_delegates_inventory_and_equipment_drop_rules() -> void:
	var source_inventory: Node = track(INVENTORY_SCRIPT.new()) as Node
	var target_inventory: Node = track(INVENTORY_SCRIPT.new()) as Node
	source_inventory.Capacity = 1
	target_inventory.Capacity = 1
	var item: Resource = _new_item(&"move_probe", "移动物品", 5)
	source_inventory.TrySetStackAt(0, _new_stack(item))
	var source_ui: PanelContainer = _new_slot_ui()
	source_ui.call("Bind", 0, source_inventory.GetStackAt(0), source_inventory)
	var target_ui: PanelContainer = _new_slot_ui()
	target_ui.call("Bind", 0, target_inventory.GetStackAt(0), target_inventory)
	var inventory_payload: RefCounted = source_ui.call("_build_drag_data") as RefCounted
	assert_true(target_ui._can_drop_data(Vector2.ZERO, inventory_payload), "空目标库存格必须接受来源库存物品。")
	target_ui._drop_data(Vector2.ZERO, inventory_payload)
	assert_true(source_inventory.GetStackAt(0).get("IsEmpty"), "库存移动后来源格必须为空。")
	assert_true(target_inventory.GetStackAt(0).get("Item") == item, "库存移动后目标格必须保留原 Item Resource。")

	var equipment_context: Dictionary = _new_equipment_context()
	var equipment: Node = equipment_context.equipment
	var ring: Resource = EQUIPMENT_DATA_SCRIPT.new()
	ring.set("CardId", &"unequip_probe")
	ring.set("CardName", "卸下戒指")
	var ring_slots: Array[int] = [int(EQUIPMENT_TYPES.EquipmentSlot.Ring1)]
	ring.set("ValidSlots", ring_slots)
	assert_true(equipment.Equip(_new_stack(ring), int(EQUIPMENT_TYPES.EquipmentSlot.Ring1)), "夹具戒指必须先装备到 Ring1。")
	var unequip_inventory: Node = track(INVENTORY_SCRIPT.new()) as Node
	unequip_inventory.Capacity = 1
	var unequip_ui: PanelContainer = _new_slot_ui()
	unequip_ui.call("Bind", 0, unequip_inventory.GetStackAt(0), unequip_inventory)
	var equipment_payload: RefCounted = DRAGGABLE_DATA_SCRIPT.new()
	equipment_payload.set("SourceEquipment", equipment)
	equipment_payload.set("FromEquipmentSlot", int(EQUIPMENT_TYPES.EquipmentSlot.Ring1))
	assert_true(unequip_ui._can_drop_data(Vector2.ZERO, equipment_payload), "空库存格必须接受 Ring1 装备。")
	unequip_ui._drop_data(Vector2.ZERO, equipment_payload)
	assert_true(equipment.TryGetEquippedStack(int(EQUIPMENT_TYPES.EquipmentSlot.Ring1)) == null, "卸下后 Ring1 必须为空。")
	assert_true(unequip_inventory.GetStackAt(0).get("Item") == ring, "卸下后库存必须保留原装备 Resource。")


## 验证仓库面板保持请求、双库存槽位、重绑复用、提示框和关闭契约。
func test_warehouse_ui_preserves_cross_language_panel_contract() -> void:
	var production_scene_root := WAREHOUSE_UI_SCENE.instantiate() as Control
	var warehouse_ui: Control = track(WAREHOUSE_UI_SCRIPT.new()) as Control
	# 编辑器内 set_script 会把非 @tool 脚本降为 placeholder；迁入生产子树可同时验证真实节点路径。
	for production_child in production_scene_root.get_children():
		production_scene_root.remove_child(production_child)
		production_child.owner = null
		warehouse_ui.add_child(production_child)
	production_scene_root.free()
	var gameplay_port := FakeWarehouseGameplayPort.new()
	gameplay_port.name = "GameplayPort"
	warehouse_ui.add_child(gameplay_port)
	var tooltip_panel := FakeItemTooltipPanel.new()
	tooltip_panel.name = "TooltipPanel"
	warehouse_ui.add_child(tooltip_panel)
	warehouse_ui.set("SlotPrefab", _new_slot_ui_packed_scene())
	warehouse_ui.set("GameplayPortPath", NodePath("GameplayPort"))
	warehouse_ui.set("TooltipPanelPath", NodePath("TooltipPanel"))
	# 生产脚本不是 @tool，编辑器内测试需显式执行生命周期；游戏运行时仍由 Godot 自动调用。
	warehouse_ui.call("_ready")

	assert_false(warehouse_ui.visible, "WarehouseUI 初始化后必须隐藏。")
	var close_button := warehouse_ui.get_node("MainPanel/VBoxContainer/TitleBar/CloseButton") as Button
	var normal_style := close_button.get_theme_stylebox("normal") as StyleBoxFlat
	var hover_style := close_button.get_theme_stylebox("hover") as StyleBoxFlat
	assert_eq(normal_style.bg_color, Color(0.25, 0.25, 0.25, 1.0), "关闭按钮常态颜色必须保持运行时覆盖值。")
	assert_eq(hover_style.bg_color, Color(0.35, 0.35, 0.35, 1.0), "关闭按钮悬停颜色必须保持运行时覆盖值。")
	assert_eq(normal_style.corner_radius_top_left, 4, "关闭按钮圆角必须保持 4。")
	var player_grid := warehouse_ui.get_node("MainPanel/VBoxContainer/ContentSplit/BackpackSection/BackpackScroll/BackpackMargin/PlayerSlotGrid") as GridContainer
	var warehouse_grid := warehouse_ui.get_node("MainPanel/VBoxContainer/ContentSplit/WarehouseSection/WarehouseScroll/WarehouseMargin/WarehouseSlotGrid") as GridContainer

	var player_inventory: Node = track(INVENTORY_SCRIPT.new()) as Node
	player_inventory.Capacity = 2
	var warehouse_inventory: Node = track(INVENTORY_SCRIPT.new()) as Node
	warehouse_inventory.Capacity = 3
	var item: Resource = _new_item(&"warehouse_ui_item", "仓库界面物品", 5)
	player_inventory.TrySetStackAt(0, _new_stack(item))
	gameplay_port.WarehouseRequested.emit(player_inventory, warehouse_inventory)
	assert_true(warehouse_ui.visible, "WarehouseRequested 必须打开仓库面板。")
	warehouse_ui.hide()
	gameplay_port.WarehouseNodeRequested.emit(player_inventory, warehouse_inventory)
	assert_true(warehouse_ui.visible, "WarehouseNodeRequested 必须打开仓库面板。")

	assert_eq(player_grid.get_child_count(), 2, "玩家槽位数必须匹配玩家库存容量。")
	assert_eq(warehouse_grid.get_child_count(), 3, "仓库槽位数必须匹配仓库容量。")
	var first_player_slot: Control = player_grid.get_child(0) as Control
	var first_warehouse_slot: Control = warehouse_grid.get_child(0) as Control
	assert_true(first_player_slot.get("Inventory") == player_inventory, "玩家槽位必须绑定玩家库存。")
	assert_true(first_player_slot.get("CurrentStack").get("Item") == item, "玩家槽位必须绑定当前物品堆叠。")
	assert_true(first_warehouse_slot.get("Inventory") == warehouse_inventory, "仓库槽位必须绑定全局仓库。")
	var first_player_id: int = int(first_player_slot.get_instance_id())
	var first_warehouse_id: int = int(first_warehouse_slot.get_instance_id())

	warehouse_ui.call("Open", player_inventory, warehouse_inventory)
	assert_eq(int(player_grid.get_child(0).get_instance_id()), first_player_id, "相同容量重绑必须复用玩家槽位节点。")
	assert_eq(int(warehouse_grid.get_child(0).get_instance_id()), first_warehouse_id, "相同容量重绑必须复用仓库槽位节点。")
	assert_true(player_inventory.is_connected("InventoryChanged", Callable(warehouse_ui, "_on_player_inventory_changed")), "面板必须连接玩家 InventoryChanged。")
	assert_true(warehouse_inventory.is_connected("InventoryChanged", Callable(warehouse_ui, "_on_warehouse_inventory_changed")), "面板必须连接仓库 InventoryChanged。")

	close_button.pressed.emit()
	assert_false(warehouse_ui.visible, "关闭按钮必须隐藏仓库面板。")
	assert_eq(tooltip_panel.hide_count, 1, "关闭仓库面板必须隐藏提示框。")
	warehouse_ui._exit_tree()
	assert_false(gameplay_port.WarehouseRequested.is_connected(Callable(warehouse_ui, "_handle_warehouse_requested")), "退出时必须解除 GameplayPort 信号。")
	assert_false(gameplay_port.WarehouseNodeRequested.is_connected(Callable(warehouse_ui, "_handle_warehouse_requested")), "退出时必须解除动态仓库信号。")
	assert_false(player_inventory.is_connected("InventoryChanged", Callable(warehouse_ui, "_on_player_inventory_changed")), "退出时必须解除玩家库存信号。")
	assert_false(warehouse_inventory.is_connected("InventoryChanged", Callable(warehouse_ui, "_on_warehouse_inventory_changed")), "退出时必须解除仓库库存信号。")


## 验证背包父面板保持三组槽位、快捷移动、合成请求与信号清理契约。
func test_inventory_ui_preserves_cross_language_parent_contract() -> void:
	var production_scene_root := INVENTORY_UI_SCENE.instantiate() as Control
	var inventory_ui: Control = track(INVENTORY_UI_SCRIPT.new()) as Control
	inventory_ui.name = production_scene_root.name
	# 迁入生产场景子树，并重建 owner 以保留 C# 原实现使用的 % 唯一节点路径。
	for production_child in production_scene_root.get_children():
		production_scene_root.remove_child(production_child)
		production_child.owner = null
		inventory_ui.add_child(production_child)
		production_child.owner = inventory_ui
		_assign_owner_recursive(production_child, inventory_ui)
	production_scene_root.free()
	var legacy_attribute_summary := inventory_ui.get_node("MainPanel/VBoxContainer/ContentSplit/CharacterSection/AttributeSummaryUI")
	var attribute_summary_parent := legacy_attribute_summary.get_parent()
	var attribute_summary_index: int = legacy_attribute_summary.get_index()
	attribute_summary_parent.remove_child(legacy_attribute_summary)
	legacy_attribute_summary.free()
	var attribute_summary := FakeInventoryAttributeSummaryUI.new()
	attribute_summary.name = "AttributeSummaryUI"
	attribute_summary.unique_name_in_owner = true
	attribute_summary_parent.add_child(attribute_summary)
	attribute_summary_parent.move_child(attribute_summary, attribute_summary_index)
	attribute_summary.owner = inventory_ui

	var gameplay_port := FakeInventoryGameplayPort.new()
	gameplay_port.name = "GameplayPort"
	inventory_ui.add_child(gameplay_port)
	var tooltip_panel := FakeItemTooltipPanel.new()
	tooltip_panel.name = "TooltipPanel"
	inventory_ui.add_child(tooltip_panel)
	inventory_ui.set("SlotPrefab", _new_slot_ui_packed_scene())
	inventory_ui.set("EquipmentSlotPrefab", _new_equipment_slot_ui_packed_scene())
	inventory_ui.set("GameplayPortPath", NodePath("GameplayPort"))
	inventory_ui.set("TooltipPanelPath", NodePath("TooltipPanel"))
	# 生产脚本不是 @tool，编辑器内测试显式执行生命周期；游戏运行时仍由 Godot 自动调用。
	inventory_ui.call("_ready")
	assert_false(inventory_ui.visible, "InventoryUI 初始化后必须隐藏。")

	var player_inventory: Node = track(INVENTORY_SCRIPT.new()) as Node
	player_inventory.Capacity = 2
	var battle_deck: Node = track(BATTLE_DECK_SCRIPT.new()) as Node
	battle_deck.Capacity = 2
	var equipment := track(FakeInventoryEquipment.new()) as FakeInventoryEquipment
	var attributes := track(Node.new()) as Node
	var player := track(FakeInventoryPlayer.new()) as FakeInventoryPlayer
	player.Attributes = attributes
	player.Equipment = equipment
	gameplay_port.Player = player
	gameplay_port.PlayerBattleDeck = battle_deck

	gameplay_port.InventoryToggleRequested.emit(player_inventory)
	assert_true(inventory_ui.visible, "InventoryToggleRequested 必须打开隐藏的背包面板。")
	var slot_grid := inventory_ui.get_node("%SlotGrid") as GridContainer
	var equipment_grid := inventory_ui.get_node("%EquipmentSlotGrid") as GridContainer
	var deck_grid := inventory_ui.get_node("%DeckSlotGrid") as GridContainer
	assert_eq(slot_grid.get_child_count(), 2, "玩家槽位数必须匹配背包容量。")
	assert_eq(equipment_grid.get_child_count(), EQUIPMENT_TYPES.EquipmentSlot.size(), "装备槽位数必须覆盖全部稳定枚举值。")
	assert_eq(deck_grid.get_child_count(), 2, "卡组槽位数必须匹配初始容量。")
	var first_slot := slot_grid.get_child(0) as FakeWarehouseSlotUI
	var first_equipment_slot := equipment_grid.get_child(0) as FakeInventoryEquipmentSlotUI
	var first_deck_slot := deck_grid.get_child(0) as FakeWarehouseSlotUI
	assert_true(first_slot.Inventory == player_inventory, "普通槽位必须绑定玩家背包。")
	assert_true(first_equipment_slot.Equipment == equipment, "装备槽必须绑定玩家装备组件。")
	assert_eq(first_equipment_slot.EquipmentSlot, int(EQUIPMENT_TYPES.EquipmentSlot.Helmet), "首个装备槽必须保持 Helmet=0。")
	assert_true(first_deck_slot.Inventory == battle_deck, "卡组槽位必须绑定 BattleDeckComponent。")
	assert_true(first_slot.TooltipPresenter != null and first_slot.ShortcutHandler.is_valid(), "普通槽位必须收到共享 Presenter 与快捷回调。")

	var first_slot_id: int = int(first_slot.get_instance_id())
	var first_equipment_id: int = int(first_equipment_slot.get_instance_id())
	var first_deck_id: int = int(first_deck_slot.get_instance_id())
	inventory_ui.call("Open", player_inventory)
	assert_eq(int(slot_grid.get_child(0).get_instance_id()), first_slot_id, "相同背包容量重开必须复用普通槽位。")
	assert_eq(int(equipment_grid.get_child(0).get_instance_id()), first_equipment_id, "相同装备组件重开必须复用装备槽位。")
	assert_eq(int(deck_grid.get_child(0).get_instance_id()), first_deck_id, "相同卡组容量重开必须复用卡组槽位。")

	player_inventory.SetCapacity(3)
	player_inventory.InventoryChanged.emit()
	assert_eq(slot_grid.get_child_count(), 3, "背包扩容后必须只补足缺少的槽位。")
	assert_eq(int(slot_grid.get_child(0).get_instance_id()), first_slot_id, "背包扩容不得替换既有槽位。")
	battle_deck.SetCapacity(3)
	battle_deck.InventoryChanged.emit()
	assert_eq(deck_grid.get_child_count(), 3, "卡组扩容后必须同步视图数量。")
	assert_eq(int(deck_grid.get_child(0).get_instance_id()), first_deck_id, "卡组扩容不得替换既有槽位。")
	var bind_count_before: int = first_equipment_slot.BindCount
	equipment.EquipmentChanged.emit()
	assert_eq(first_equipment_slot.BindCount, bind_count_before + 1, "EquipmentChanged 必须重绑既有装备槽。")

	var skill_card: Resource = _new_skill_card(&"inventory_ui_skill", "背包快捷技能")
	assert_eq(player_inventory.AddItem(skill_card, 2), 0, "快捷测试技能卡必须完整加入玩家背包。")
	first_slot = slot_grid.get_child(0) as FakeWarehouseSlotUI
	first_slot.ShortcutHandler.call(first_slot, 1)
	assert_eq(player_inventory.ItemCnt(skill_card), 0, "Alt 单击必须把玩家背包中的全部技能卡移入卡组。")
	assert_eq(battle_deck.ItemCnt(skill_card), 2, "卡组必须收到全部匹配技能卡。")
	first_deck_slot = deck_grid.get_child(0) as FakeWarehouseSlotUI
	first_deck_slot.ShortcutHandler.call(first_deck_slot, 1)
	assert_eq(player_inventory.ItemCnt(skill_card), 2, "卡组 Alt 单击必须把全部技能卡移回玩家背包。")
	assert_eq(battle_deck.ItemCnt(skill_card), 0, "批量移回后卡组不得残留匹配技能卡。")

	first_slot = slot_grid.get_child(0) as FakeWarehouseSlotUI
	first_slot.ShortcutHandler.call(first_slot, 0)
	assert_eq(player_inventory.ItemCnt(skill_card), 1, "玩家技能卡 Shift 单击必须只移动一个堆叠。")
	assert_eq(battle_deck.ItemCnt(skill_card), 1, "卡组必须收到单个技能卡堆叠。")
	first_deck_slot = deck_grid.get_child(0) as FakeWarehouseSlotUI
	first_deck_slot.ShortcutHandler.call(first_deck_slot, 0)
	assert_eq(player_inventory.ItemCnt(skill_card), 2, "卡组技能卡 Shift 单击必须移回玩家背包。")

	var equipment_item: Resource = _new_item(&"inventory_ui_equipment", "快捷装备", 1)
	assert_eq(player_inventory.AddItem(equipment_item, 1), 0, "快捷测试装备必须加入剩余槽位。")
	var equipment_source_slot := slot_grid.get_child(2) as FakeWarehouseSlotUI
	equipment_source_slot.ShortcutHandler.call(equipment_source_slot, 0)
	assert_eq(equipment.EquipBestSlotCallCount, 1, "普通物品 Shift 单击必须委托最佳装备槽选择。")
	assert_true(equipment.LastSourceInventory == player_inventory, "装备委托必须保留来源背包引用。")
	assert_eq(equipment.LastSourceIndex, 2, "装备委托必须保留来源槽位索引。")

	var crafting_button := inventory_ui.get_node("%CraftingButton") as Button
	crafting_button.pressed.emit()
	assert_false(inventory_ui.visible, "合成按钮必须先隐藏背包面板。")
	assert_eq(gameplay_port.CraftingOpenRequestCount, 1, "合成按钮必须经 GameplayPort 请求幂等打开。")
	gameplay_port.InventoryToggleRequested.emit(player_inventory)
	assert_true(inventory_ui.visible, "隐藏后再次切换必须重新打开背包。")
	var close_button := inventory_ui.get_node("%CloseButton") as Button
	close_button.pressed.emit()
	assert_false(inventory_ui.visible, "关闭按钮必须隐藏背包面板。")
	gameplay_port.InventoryNodeToggleRequested.emit(player_inventory)
	assert_true(inventory_ui.visible, "InventoryNodeToggleRequested 必须打开 GDScript 玩家背包。")
	inventory_ui.call("Close")

	inventory_ui.call("_exit_tree")
	assert_false(gameplay_port.InventoryToggleRequested.is_connected(Callable(inventory_ui, "_handle_inventory_toggle_request")), "退出时必须解除 GameplayPort 信号。")
	assert_false(gameplay_port.InventoryNodeToggleRequested.is_connected(Callable(inventory_ui, "_handle_inventory_toggle_request")), "退出时必须解除动态背包信号。")
	assert_false(player_inventory.is_connected("InventoryChanged", Callable(inventory_ui, "_on_inventory_changed")), "退出时必须解除玩家背包信号。")
	assert_false(equipment.EquipmentChanged.is_connected(Callable(inventory_ui, "_on_equipment_changed")), "退出时必须解除装备信号。")
	assert_false(battle_deck.is_connected("InventoryChanged", Callable(inventory_ui, "_on_battle_deck_changed")), "退出时必须解除卡组信号。")


## 验证 HUD 快捷键与背包按钮保持输入阶段、echo 和 handled 时序。
func test_hud_input_bridge_preserves_keyboard_and_button_contract() -> void:
	var crafting_fixture: Dictionary = _new_hud_input_fixture()
	var crafting_viewport: SubViewport = crafting_fixture["viewport"] as SubViewport
	var crafting_hud: Control = crafting_fixture["hud"] as Control
	var crafting_port := crafting_fixture["gameplay_port"] as FakeHudGameplayPort
	var crafting_action_fixture: Dictionary = _new_key_action_fixture(&"toggle_crafting", false)
	var crafting_event: InputEventKey = crafting_action_fixture["input_event"] as InputEventKey
	crafting_hud.call("_input", crafting_event)
	_remove_key_action_fixture(&"toggle_crafting", crafting_action_fixture)
	assert_eq(crafting_port.CraftingToggleRequestCount, 1, "合成快捷键必须经 GameplayPort 切换合成界面。")
	assert_false(crafting_port.CraftingHandledWhenRequested, "合成请求发出前不得提前消费输入。")
	assert_true(crafting_viewport.is_input_handled(), "合成请求发出后必须把输入标记为 handled。")

	var crafting_echo_fixture: Dictionary = _new_hud_input_fixture()
	var crafting_echo_viewport: SubViewport = crafting_echo_fixture["viewport"] as SubViewport
	var crafting_echo_hud: Control = crafting_echo_fixture["hud"] as Control
	var crafting_echo_port := crafting_echo_fixture["gameplay_port"] as FakeHudGameplayPort
	var crafting_echo_action_fixture: Dictionary = _new_key_action_fixture(&"toggle_crafting", true)
	var crafting_echo_event: InputEventKey = crafting_echo_action_fixture["input_event"] as InputEventKey
	crafting_echo_hud.call("_input", crafting_echo_event)
	_remove_key_action_fixture(&"toggle_crafting", crafting_echo_action_fixture)
	assert_eq(crafting_echo_port.CraftingToggleRequestCount, 0, "键盘 echo 不得重复切换合成界面。")
	assert_false(crafting_echo_viewport.is_input_handled(), "被忽略的合成 echo 不得消费输入。")

	var inventory_fixture: Dictionary = _new_hud_input_fixture()
	var inventory_viewport: SubViewport = inventory_fixture["viewport"] as SubViewport
	var inventory_hud: Control = inventory_fixture["hud"] as Control
	var inventory_port := inventory_fixture["gameplay_port"] as FakeHudGameplayPort
	var inventory_action_fixture: Dictionary = _new_key_action_fixture(&"toggle_inventory", false)
	var inventory_event: InputEventKey = inventory_action_fixture["input_event"] as InputEventKey
	inventory_hud.call("_unhandled_input", inventory_event)
	_remove_key_action_fixture(&"toggle_inventory", inventory_action_fixture)
	assert_eq(inventory_port.InventoryToggleRequestCount, 1, "背包快捷键必须经 GameplayPort 切换背包界面。")
	assert_false(inventory_port.InventoryHandledWhenRequested, "背包请求发出前不得提前消费输入。")
	assert_true(inventory_viewport.is_input_handled(), "背包请求发出后必须把输入标记为 handled。")

	var inventory_echo_fixture: Dictionary = _new_hud_input_fixture()
	var inventory_echo_viewport: SubViewport = inventory_echo_fixture["viewport"] as SubViewport
	var inventory_echo_hud: Control = inventory_echo_fixture["hud"] as Control
	var inventory_echo_port := inventory_echo_fixture["gameplay_port"] as FakeHudGameplayPort
	var inventory_echo_action_fixture: Dictionary = _new_key_action_fixture(&"toggle_inventory", true)
	var inventory_echo_event: InputEventKey = inventory_echo_action_fixture["input_event"] as InputEventKey
	inventory_echo_hud.call("_unhandled_input", inventory_echo_event)
	_remove_key_action_fixture(&"toggle_inventory", inventory_echo_action_fixture)
	assert_eq(inventory_echo_port.InventoryToggleRequestCount, 0, "键盘 echo 不得重复切换背包界面。")
	assert_false(inventory_echo_viewport.is_input_handled(), "被忽略的背包 echo 不得消费输入。")

	var button_viewport: SubViewport = track(SubViewport.new()) as SubViewport
	var button_port := FakeHudGameplayPort.new()
	button_port.name = "GameplayPort"
	button_port.ObservedViewport = button_viewport
	button_viewport.add_child(button_port)
	var backpack_button: Button = BACKPACK_BUTTON_SCRIPT.new() as Button
	backpack_button.name = "BackpackButton"
	button_viewport.add_child(backpack_button)
	backpack_button.set("GameplayPortPath", NodePath("../GameplayPort"))
	var scene_tree := Engine.get_main_loop() as SceneTree
	scene_tree.root.add_child(button_viewport)
	backpack_button.call("_pressed")
	assert_eq(button_port.InventoryToggleRequestCount, 1, "背包按钮点击必须经 GameplayPort 切换背包界面。")


## 验证生产场景和 TalentManager 预制体都指向 GDScript 卡片。
func test_talent_card_production_scenes_use_gdscript() -> void:
	var card_scene := ResourceLoader.load(
		TALENT_CARD_SCENE_PATH,
		"PackedScene",
		ResourceLoader.CACHE_MODE_REPLACE
	) as PackedScene
	assert_true(card_scene != null, "天赋卡生产场景必须能够加载。")
	if card_scene == null:
		return
	var card := card_scene.instantiate() as Control
	var card_script := card.get_script() as Script
	assert_true(card_script != null, "天赋卡根节点必须保留脚本。")
	if card_script != null:
		assert_eq(card_script.resource_path, TALENT_CARD_SCRIPT_PATH, "天赋卡必须使用 GDScript 实现。")
	card.free()

	var screen_scene := ResourceLoader.load(
		TALENT_SCREEN_SCENE_PATH,
		"PackedScene",
		ResourceLoader.CACHE_MODE_REPLACE
	) as PackedScene
	assert_true(screen_scene != null, "天赋选择场景必须能够加载。")
	if screen_scene == null:
		return
	var screen := screen_scene.instantiate() as CanvasLayer
	var configured_card_scene: PackedScene = screen.get("CardScenePrefab") as PackedScene
	assert_true(configured_card_scene != null, "TalentManager 必须保留天赋卡预制体。")
	if configured_card_scene != null:
		var configured_card := configured_card_scene.instantiate() as Control
		var configured_script := configured_card.get_script() as Script
		assert_true(configured_script != null, "TalentManager 的卡片预制体必须保留脚本。")
		if configured_script != null:
			assert_eq(configured_script.resource_path, TALENT_CARD_SCRIPT_PATH, "TalentManager 必须实例化新卡片脚本。")
		configured_card.free()
	screen.free()


## 验证生产卡片保留节点结构、导出引用和跨语言方法/信号协议。
func test_talent_card_serialized_node_contract() -> void:
	var packed_scene := load(TALENT_CARD_SCENE_PATH) as PackedScene
	assert_true(packed_scene != null, "天赋卡场景必须能够加载。")
	if packed_scene == null:
		return
	var card := packed_scene.instantiate() as Control
	var title := card.get_node("TitleText") as Label
	var description := card.get_node("DescText") as RichTextLabel
	var texture := card.get_node("Texture") as TextureRect
	var click_area := card.get_node("ClickArea") as Button
	assert_true(title != null, "天赋卡必须保留 TitleText Label。")
	assert_true(description != null, "天赋卡必须保留 DescText RichTextLabel。")
	assert_true(texture != null, "天赋卡必须保留 Texture TextureRect。")
	assert_true(click_area != null, "天赋卡必须保留 ClickArea Button。")
	assert_true(card.get("_titleLabel") == title, "_titleLabel 必须继续引用 TitleText。")
	assert_true(card.get("_descLabel") == description, "_descLabel 必须继续引用 DescText。")
	assert_true(card.get("_texture") == texture, "_texture 必须继续引用 Texture。")
	assert_true(card.get("_clickArea") == click_area, "_clickArea 必须继续引用 ClickArea。")
	assert_true(card.has_method("Initialize"), "TalentManager 必须仍可调用 Initialize。")
	assert_true(card.has_signal("OnCardClicked"), "TalentManager 必须仍可连接 OnCardClicked。")
	card.free()


## 验证生产选择界面保留序列化字段、节点和公开选择入口。
func test_talent_manager_production_scene_contract() -> void:
	var packed_scene := load(TALENT_SCREEN_SCENE_PATH) as PackedScene
	assert_true(packed_scene != null, "天赋选择生产场景必须能够加载。")
	if packed_scene == null:
		return
	var screen := packed_scene.instantiate() as CanvasLayer
	var manager_script := screen.get_script() as Script
	var cards_container := screen.get_node("HBoxContainer") as HBoxContainer
	var all_talents: Array = screen.get("AllTalentsPool")
	var card_scene := screen.get("CardScenePrefab") as PackedScene
	assert_true(manager_script != null, "天赋选择根节点必须保留脚本。")
	if manager_script != null:
		assert_eq(manager_script.resource_path, TALENT_MANAGER_SCRIPT_PATH, "天赋选择界面必须使用 GDScript Manager。")
	assert_eq(all_talents.size(), 0, "生产场景的空天赋池默认值必须保持不变。")
	assert_true(card_scene != null, "CardScenePrefab 必须继续引用天赋卡场景。")
	if card_scene != null:
		assert_eq(card_scene.resource_path, TALENT_CARD_SCENE_PATH, "CardScenePrefab 路径必须保持不变。")
	assert_true(screen.get("CardsContainer") == cards_container, "CardsContainer 必须继续引用 HBoxContainer。")
	assert_true(screen.has_method("OnTalentSelected"), "卡片点击必须仍可调用公开选择入口。")
	assert_eq(screen.process_mode, Node.PROCESS_MODE_ALWAYS, "暂停期间天赋界面必须继续处理输入。")
	screen.free()


## 验证天赋数据与两种效果保留原序列化字段和动态应用协议。
func test_talent_resource_schema_contract() -> void:
	var base_effect := TALENT_EFFECT_SCRIPT.new() as Resource
	var data := TALENT_DATA_SCRIPT.new() as Resource
	var attribute_effect := ATTRIBUTE_TALENT_EFFECT_SCRIPT.new() as Resource
	var tag_effect := TAG_TALENT_EFFECT_SCRIPT.new() as Resource
	assert_true(data != null, "TalentData GDScript 必须能够实例化。")
	assert_true(base_effect != null and base_effect.has_method("Apply"), "TalentEffect 基类必须保留 Apply 协议。")
	assert_true(attribute_effect != null, "AttributeTalentEffect GDScript 必须能够实例化。")
	assert_true(tag_effect != null, "TagTalentEffect GDScript 必须能够实例化。")
	data.set("TalentName", "契约天赋")
	data.set("Description", "保留说明")
	data.set("TalentTexture", load("res://res/environment/tree.png"))
	var effects: Array = data.get("Effects")
	effects.append(attribute_effect)
	effects.append(tag_effect)
	data.set("Effects", effects)
	attribute_effect.set("TargetAttribute", 14)
	attribute_effect.set("BonusValue", 2.5)
	tag_effect.set("TagToGrant", &"talent_contract")
	assert_eq(data.get("TalentName"), "契约天赋", "TalentName 必须保持原字段名和值。")
	assert_eq(data.get("Description"), "保留说明", "Description 必须保持原字段名和值。")
	assert_true(data.get("TalentTexture") != null, "TalentTexture 必须接受原 Texture2D。")
	assert_eq((data.get("Effects") as Array).size(), 2, "Effects 必须接受通用 Resource 数组。")
	assert_eq(attribute_effect.get("TargetAttribute"), 14, "TargetAttribute 必须保留固定枚举整数。")
	assert_true(is_equal_approx(float(attribute_effect.get("BonusValue")), 2.5), "BonusValue 必须保留浮点数值。")
	assert_eq(tag_effect.get("TagToGrant"), &"talent_contract", "TagToGrant 必须保留 StringName。")
	assert_true(attribute_effect.has_method("Apply"), "属性效果必须实现 Apply。")
	assert_true(tag_effect.has_method("Apply"), "标签效果必须实现 Apply。")
