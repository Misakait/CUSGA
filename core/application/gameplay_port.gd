extends Node

## GameplayPort 的 GDScript 生产实现。
##
## 该门面只负责解析玩家组件、转发 UI/玩法请求和广播稳定信号；
## 具体库存、合成、战斗和遭遇规则仍由对应组件或服务负责。旧 C#
## GameplayPort.cs 继续作为兼容垫片保留，不在此处复制下游业务规则。

## 玩家节点路径，保持 Main.tscn 的序列化键和值。
@export var PlayerPath: NodePath
## 玩家普通库存节点路径。
@export var PlayerInventoryPath: NodePath = NodePath("Components/InventoryComponent")
## 玩家战斗卡组节点路径。
@export var PlayerBattleDeckPath: NodePath = NodePath("Components/BattleDeckComponent")
## 玩家生命组件节点路径。
@export var PlayerHealthPath: NodePath = NodePath("Components/HealthComponent")
## 玩家合成组件节点路径。
@export var PlayerCraftingPath: NodePath = NodePath("Components/CraftingComponent")
## 全局仓库节点路径。
@export var GlobalWarehousePath: NodePath = NodePath("/root/GlobalWarehouse")

## 背包切换请求信号，参数为玩家库存节点。
signal InventoryToggleRequested(inventory)
## 背包切换的通用 Node 请求信号，用于 GDScript 库存组件。
signal InventoryNodeToggleRequested(inventory)
## 合成切换请求信号，参数为玩家合成节点。
signal CraftingToggleRequested(crafting)
## 合成打开请求信号，参数为玩家合成节点。
signal CraftingOpenRequested(crafting)
## 合成切换的通用 Node 请求信号，用于 GDScript 合成组件。
signal CraftingNodeToggleRequested(crafting)
## 合成打开的通用 Node 请求信号，用于 GDScript 合成组件。
signal CraftingNodeOpenRequested(crafting)
## 农场面板请求信号，参数为地形 Resource。
signal FarmingPanelRequested(terrain)
## 仓库打开请求信号，参数为玩家和仓库库存节点。
signal WarehouseRequested(player_inventory, warehouse_inventory)
## 仓库打开的通用 Node 请求信号，用于任一端已经迁移为 GDScript 的情况。
signal WarehouseNodeRequested(player_inventory, warehouse_inventory)
## 遭遇请求信号，参数为地形、技能卡数组、怪物数组和提示文本。
signal EncounterRequested(terrain, battle_deck, monsters, message)

## 解析出的玩家节点。
var Player: Node = null
## 解析出的玩家库存节点。
var PlayerInventory: Node = null
## 玩家库存的通用 Node 别名，与旧 C# GameplayPort 公共协议一致。
var PlayerInventoryNode: Node = null
## 解析出的玩家生命节点。
var PlayerHealth: Node = null
## 解析出的玩家卡组节点。
var PlayerBattleDeck: Node = null
## 解析出的玩家合成节点。
var PlayerCrafting: Node = null
## 玩家合成组件的通用 Node 别名，与旧 C# GameplayPort 公共协议一致。
var PlayerCraftingNode: Node = null
## 解析出的全局仓库节点。
var GlobalWarehouseInventory: Node = null
## 全局仓库的通用 Node 别名，与旧 C# GameplayPort 公共协议一致。
var GlobalWarehouseNode: Node = null


## 初始化所有跨语言节点引用。
func _ready() -> void:
	if PlayerPath.is_empty():
		push_error("GameplayPort.PlayerPath 未设置")
		return
	Player = get_node_or_null(PlayerPath) as Node
	if Player == null:
		push_error("GameplayPort 未找到 Player 节点。")
		return
	PlayerInventory = Player.get_node_or_null(PlayerInventoryPath)
	PlayerInventoryNode = PlayerInventory
	PlayerBattleDeck = Player.get_node_or_null(PlayerBattleDeckPath)
	PlayerHealth = Player.get_node_or_null(PlayerHealthPath)
	PlayerCrafting = Player.get_node_or_null(PlayerCraftingPath)
	PlayerCraftingNode = PlayerCrafting
	GlobalWarehouseInventory = get_node_or_null(GlobalWarehousePath)
	GlobalWarehouseNode = GlobalWarehouseInventory


## 请求切换背包。
func RequestToggleInventory() -> void:
	if _is_csharp_script_instance(PlayerInventory):
		InventoryToggleRequested.emit(PlayerInventory)
		return
	InventoryNodeToggleRequested.emit(PlayerInventoryNode)

## 请求切换合成界面。
func RequestToggleCrafting() -> void:
	if _is_csharp_script_instance(PlayerCrafting):
		CraftingToggleRequested.emit(PlayerCrafting)
		return
	CraftingNodeToggleRequested.emit(PlayerCraftingNode)

## 请求打开合成界面；该请求是幂等打开而不是切换。
func RequestOpenCrafting() -> void:
	if _is_csharp_script_instance(PlayerCrafting):
		CraftingOpenRequested.emit(PlayerCrafting)
		return
	CraftingNodeOpenRequested.emit(PlayerCraftingNode)

## 将堆叠交给玩家库存。
## @param stack 要加入的 ItemStack 或兼容对象。
## @return 玩家节点成功接收时返回 true。
func TryAddItemToInventory(stack: Variant) -> bool:
	if stack == null or Player == null or not Player.has_method("TryAddItemToInventory"):
		return false
	return bool(Player.call("TryAddItemToInventory", stack))

## 请求打开农场面板。
## @param terrain 当前地形 Resource。
func RequestOpenFarmingPanel(terrain: Variant) -> void:
	FarmingPanelRequested.emit(terrain)

## 请求打开仓库；缺少仓库节点时保持旧错误语义并停止广播。
func RequestOpenWarehouse() -> void:
	if GlobalWarehouseNode == null:
		push_error("GameplayPort 未绑定全局仓库节点。")
		return
	if _is_csharp_script_instance(PlayerInventory) and _is_csharp_script_instance(GlobalWarehouseInventory):
		WarehouseRequested.emit(PlayerInventory, GlobalWarehouseInventory)
		return
	WarehouseNodeRequested.emit(PlayerInventoryNode, GlobalWarehouseNode)

## 请求进入遭遇流程。
## @param terrain 当前地形 Resource。
## @param monster_or_monsters 单个怪物 Resource 或怪物数组。
## @param message 遭遇提示文本。
func RequestEncounter(terrain: Variant, monster_or_monsters: Variant, message: String = "") -> void:
	var monsters: Array[MonsterData] = _filter_monsters(monster_or_monsters)
	var scaled_monsters: Variant = monsters
	var encounter_scaler: Node = _get_encounter_scaler()
	if encounter_scaler != null and encounter_scaler.has_method("ScaleEncounterMonsters"):
		# C# 桥接点接收非泛型 Array 后逐项过滤，再调用 EncounterManager 的强类型倍率入口。
		var scaled_result: Variant = encounter_scaler.call("ScaleEncounterMonsters", terrain, monsters)
		if scaled_result is Array:
			scaled_monsters = scaled_result
		else:
			push_error("GameplayPort 收到无效的怪物倍率结果，已保留原怪物数组。")
	EncounterRequested.emit(terrain, GetPlayerSkillCards(), scaled_monsters, message if message != null else "")


## 获取按堆叠数量展开的玩家技能卡，并过滤迁移期数组中的无效元素。
## @return 保持原顺序和 Resource 身份的技能卡 Resource 数组。
func GetPlayerSkillCards() -> Array[Resource]:
	var cards: Array[Resource] = []
	if PlayerBattleDeck == null or not PlayerBattleDeck.has_method("GetSkillCards"):
		return cards
	var raw_cards: Variant = PlayerBattleDeck.call("GetSkillCards")
	if not (raw_cards is Array):
		return cards
	for raw_card: Variant in raw_cards:
		if raw_card is Resource and raw_card.has_method("ApplyEffect"):
			cards.append(raw_card as Resource)
	return cards


## 把单个怪物或动态数组转换为战斗边界要求的强类型数组。
## @param source 单个 MonsterData、任意数组或空值。
## @return 仅包含有效 MonsterData 的新数组，保持原顺序和 Resource 身份。
func _filter_monsters(source: Variant) -> Array[MonsterData]:
	var monsters: Array[MonsterData] = []
	if source is Array:
		for raw_monster: Variant in source:
			if raw_monster is MonsterData:
				monsters.append(raw_monster)
	elif source is MonsterData:
		monsters.append(source)
	return monsters


## 解析遭遇倍率桥；生产 Main 由同级 WorldInteractionCoordinator 完成动态数组过滤。
## @return 优先返回同级协调器；仅允许 GDScript EncounterManager 走直接兼容回退。
func _get_encounter_scaler() -> Node:
	var coordinator := get_node_or_null("../WorldInteractionCoordinator") as Node
	if coordinator != null and coordinator.has_method("ScaleEncounterMonsters"):
		return coordinator
	var sibling_manager := get_node_or_null("../EncounterManager") as Node
	if sibling_manager != null and not _is_csharp_script_instance(sibling_manager):
		return sibling_manager
	if is_inside_tree():
		var root_manager := get_node_or_null("/root/EncounterManager") as Node
		if root_manager != null and not _is_csharp_script_instance(root_manager):
			return root_manager
	push_error("GameplayPort 未找到可安全接收动态怪物数组的遭遇倍率桥。")
	return null


## 判断节点是否仍由 C# 脚本实现，用于选择旧强类型信号或通用 Node 信号。
## @param node 待检查的组件节点。
## @return 节点脚本扩展名为 .cs 时返回 true。
func _is_csharp_script_instance(node: Node) -> bool:
	if node == null:
		return false
	var node_script := node.get_script() as Script
	return node_script != null and node_script.resource_path.get_extension().to_lower() == "cs"
