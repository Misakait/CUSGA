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
## 背包使用建筑牌时发出，item 为实际库存持有的资源。
signal BuildingPlacementRequested(item: Resource)

## 怪物数据的跨语言字段协议：C# MonsterData 为 [Export]，GDScript monster_data.gd 为 @export。
## 判定只看字段面，不看类型名或脚本路径，避免把语言身份写进生产逻辑。
const MONSTER_DATA_REQUIRED_FIELDS: Array[StringName] = [
	&"MonsterName",
	&"ElementalProperty",
	&"SkillSet",
]

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
## 背包组件已全部迁移到 GDScript，因此只广播通用 Node 信号；
## 旧的强类型信号 InventoryToggleRequested 仍保留在节点 API 上，供外部按原信号名对接。
func RequestToggleInventory() -> void:
	InventoryNodeToggleRequested.emit(PlayerInventoryNode)

## 请求切换合成界面。
## 同上：C# 组件退役后只保留通用 Node 信号路径。
func RequestToggleCrafting() -> void:
	CraftingNodeToggleRequested.emit(PlayerCraftingNode)

## 请求打开合成界面；该请求是幂等打开而不是切换。
func RequestOpenCrafting() -> void:
	CraftingNodeOpenRequested.emit(PlayerCraftingNode)


## 转发建筑牌使用意图；item 为库存建筑资源，返回是否接受请求。
## 只检查持有关系，落点校验与扣牌由建筑系统处理。
func RequestPlaceBuilding(item: Resource) -> bool:
	if item == null or not item.has_method("IsBuildingCard") or not bool(item.call("IsBuildingCard")):
		return false
	if PlayerInventory == null or not bool(PlayerInventory.call("HasItem", item, 1)):
		return false
	if get_signal_connection_list("BuildingPlacementRequested").is_empty():
		return false
	BuildingPlacementRequested.emit(item)
	return true

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
	WarehouseNodeRequested.emit(PlayerInventoryNode, GlobalWarehouseNode)

## 请求进入遭遇流程。
## @param terrain 当前地形 Resource。
## @param monster_or_monsters 单个怪物 Resource 或怪物数组。
## @param message 遭遇提示文本。
func RequestEncounter(terrain: Variant, monster_or_monsters: Variant, message: String = "") -> void:
	var monsters: Array[Resource] = _filter_monsters(monster_or_monsters)
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


## 把单个怪物或动态数组转换为战斗边界要求的怪物资源数组。
## @param source 单个怪物数据、任意数组或空值。
## @return 仅包含有效怪物数据的新数组，保持原顺序和 Resource 身份。
func _filter_monsters(source: Variant) -> Array[Resource]:
	var monsters: Array[Resource] = []
	if source is Array:
		for raw_monster: Variant in source:
			if _is_monster_data(raw_monster):
				monsters.append(raw_monster as Resource)
	elif _is_monster_data(source):
		monsters.append(source as Resource)
	return monsters


## 判断资源是否为旧 C# MonsterData 或迁移后的 GDScript 怪物数据。
##
## 两侧实现共用同一组导出字段，因此判定只扫字段面（属性表）。
##
## @param value 待判断的动态值。
## @return 属于两种怪物数据实现之一时返回 true。
func _is_monster_data(value: Variant) -> bool:
	if not (value is Resource):
		return false

	var resource: Resource = value
	var present: Dictionary = {}
	for property: Dictionary in resource.get_property_list():
		present[StringName(property.get("name", ""))] = true

	for field: StringName in MONSTER_DATA_REQUIRED_FIELDS:
		if not present.has(field):
			return false

	return true


## 解析遭遇倍率桥；生产 Main 由同级 WorldInteractionCoordinator 完成动态数组过滤。
## @return 优先返回同级协调器；否则回退到同级或全局 EncounterManager。
func _get_encounter_scaler() -> Node:
	var coordinator := get_node_or_null("../WorldInteractionCoordinator") as Node
	if coordinator != null and coordinator.has_method("ScaleEncounterMonsters"):
		return coordinator
	var sibling_manager := get_node_or_null("../EncounterManager") as Node
	if sibling_manager != null:
		return sibling_manager
	if is_inside_tree():
		var root_manager := get_node_or_null("/root/EncounterManager") as Node
		if root_manager != null:
			return root_manager
	push_error("GameplayPort 未找到可安全接收动态怪物数组的遭遇倍率桥。")
	return null
