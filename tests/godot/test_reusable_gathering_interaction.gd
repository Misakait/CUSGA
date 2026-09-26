@tool
extends McpTestSuite

## 可重复采集 GDScript Resource 的最小行为回归套件。
## 资源规则优先使用轻量假对象；生产边界切换另用聚焦契约验证跨语言场景端口。

const INTERACTION_SCRIPT: GDScript = preload("res://resources/interaction/reusable_gathering_interaction.gd")
const GATHERING_INTERACTION_SCRIPT: GDScript = preload("res://resources/interaction/gathering_interaction.gd")
const FARMING_INTERACTION_SCRIPT: GDScript = preload("res://resources/interaction/farming_interaction.gd")
const VAULT_INTERACTION_SCRIPT: GDScript = preload("res://resources/interaction/vault_interaction.gd")
const BOSS_INTERACTION_SCRIPT: GDScript = preload("res://resources/interaction/boss_interaction.gd")
const EQUIPMENT_TYPES_SCRIPT: GDScript = preload("res://core/constants/equipment_types.gd")
const RANGE_SCRIPT: GDScript = preload("res://resources/encounters/monster_stat_multiplier_range.gd")
const GATHERING_RULE_SCRIPT: GDScript = preload("res://resources/encounters/gathering_encounter_rule.gd")
const MODIFIER_SCRIPT: GDScript = preload("res://resources/map/passage_guard_probability_modifier.gd")
const PASSAGE_GUARD_ENCOUNTER_SCRIPT: GDScript = preload("res://resources/map/passage_guard_encounter_data.gd")
const MONSTER_SKILL_ENTRY_SCRIPT: GDScript = preload("res://resources/monster/monster_skill_entry_data.gd")
const MONSTER_SKILL_SET_SCRIPT: GDScript = preload("res://resources/monster/monster_skill_set_data.gd")
const MONSTER_SKILL_COMPONENT_SCRIPT: GDScript = preload("res://entities/components/monster_skill_component.gd")
const MONSTER_SKILL_PREVIEW_SCRIPT: GDScript = preload("res://resources/monster/monster_skill_preview.gd")
const CURRENT_MAP_BACKGROUND_RESOLVER_SCRIPT: GDScript = preload("res://core/gameflow/current_map_background_resolver.gd")
const LOOT_DROP_SCRIPT: GDScript = preload("res://resources/loot/loot_drop.gd")
const LOOT_TABLE_SCRIPT: GDScript = preload("res://resources/loot/loot_table.gd")
## C# 兼容垫片路径：迁移期用作跨语言对照输入，C# 退役后自动换成等价的生产 GDScript 实现。
const LEGACY_ITEM_DATA_CS_PATH: String = "res://resources/item/ItemData.cs"
const LEGACY_ITEM_STACK_CS_PATH: String = "res://core/inventory/ItemStack.cs"
## 上述两个 C# 垫片退役后的等价 GDScript 实现路径。
const PRODUCTION_ITEM_STACK_GD_PATH: String = "res://resources/item/item_stack.gd"
## C# 可选助手：C# 缺席时安全替代或收起跨语言对照，避免解析期错误与假通过。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")
const ITEM_STACK_SCRIPT: GDScript = preload("res://resources/item/item_stack.gd")
const BASE_CARD_DATA_SCRIPT_PATH: String = "res://resources/item/base_card_data.gd"
const ITEM_DATA_SCRIPT_PATH: String = "res://resources/item/item_data.gd"
const RESOURCE_CARD_DATA_SCRIPT_PATH: String = "res://resources/item/card/resource_card_data.gd"
const SKILL_CARD_DATA_SCRIPT_PATH: String = "res://resources/item/card/skill_card_data.gd"
const LEGACY_COMBAT_SKILL_CS_PATH: String = "res://core/combat/skills/CombatSkillData.cs"
const ITEM_DATA_COMPAT_SCRIPT: GDScript = preload("res://resources/item/item_data_compat.gd")
const CRAFTING_INGREDIENT_SCRIPT: GDScript = preload("res://resources/recipe/crafting_ingredient.gd")
const CRAFTING_RECIPE_SCRIPT: GDScript = preload("res://resources/recipe/crafting_recipe.gd")
const RECIPE_BOOK_SCRIPT: GDScript = preload("res://resources/recipe/recipe_book_data.gd")
const CRAFTING_SERVICE_SCRIPT: GDScript = preload("res://core/crafting/crafting_service.gd")
const CRAFTING_COMPONENT_SCRIPT: GDScript = preload("res://entities/components/crafting_component.gd")
const SHOP_SERVICE_SCRIPT: GDScript = preload("res://core/shop/shop_service.gd")
const SHOP_TRADE_BRIDGE_SCRIPT: GDScript = preload("res://core/shop/shop_trade_bridge.gd")
const PLAYER_WALLET_SCRIPT: GDScript = preload("res://core/autoloads/player_wallet.gd")
const PLAYER_PROGRESSION_SCRIPT: GDScript = preload("res://core/progression/player_progression.gd")
const TIME_SYSTEM_SCRIPT: GDScript = preload("res://core/autoloads/time_system.gd")
const PRODUCTION_PLAIN_ITEM_ASSET_PATH: String = "res://items/items/applecore.tres"
const PRODUCTION_PLAIN_ITEM_COUNT: int = 103
const RESOURCE_CARD_ASSET_PATHS: Array[String] = [
	"res://resources/item/card/res_cards/branch.tres",
	"res://resources/item/card/res_cards/charcoal.tres",
	"res://resources/item/card/res_cards/stone.tres",
	"res://resources/item/card/res_cards/torch.tres",
	"res://resources/item/card/res_cards/axe.tres",
]
const WEATHER_DATA_SCRIPT: GDScript = preload("res://resources/weather/weather_data.gd")
const WEATHER_MANAGER_SCRIPT: GDScript = preload("res://core/autoloads/weather_manager.gd")
const PASSAGE_GUARD_STATE_SCRIPT: GDScript = preload("res://core/map/passage_guard_state.gd")
const PASSAGE_GUARD_SETTINGS_SCRIPT: GDScript = preload("res://resources/map/passage_guard_settings.gd")
const PASSAGE_GUARD_PROVIDER_SCRIPT: GDScript = preload("res://core/map/passage_guard_probability_provider.gd")
const ROOM_TERRAIN_POOL_ENTRY_SCRIPT: GDScript = preload("res://core/map/room_terrain_pool_entry.gd")
const ROOM_TERRAIN_PROFILE_SCRIPT: GDScript = preload("res://core/map/room_terrain_profile.gd")
const TERRAIN_CARD_DATA_SCRIPT: GDScript = preload("res://resources/interaction/terrain_card_data.gd")
const SHOP_CATALOG_SCRIPT: GDScript = preload("res://resources/shop/shop_catalog.gd")
const STARTING_STATS_SCRIPT: GDScript = preload("res://resources/stats/starting_stats.gd")
const EQUIPMENT_DATA_SCRIPT: GDScript = preload("res://resources/item/equipment/equipment_data.gd")
const TOOL_DATA_SCRIPT: GDScript = preload("res://resources/item/tool/tool_data.gd")
const SET_BONUS_TIER_SCRIPT: GDScript = preload("res://resources/item/equipment/set_bonus_tier.gd")
const EQUIPMENT_SET_DATA_SCRIPT: GDScript = preload("res://resources/item/equipment/equipment_set_data.gd")
const EQUIPMENT_DATA_COMPAT_SCRIPT: GDScript = preload("res://resources/item/equipment/equipment_data_compat.gd")
const PRODUCTION_TOOL_ASSET_PATHS: Array[String] = [
	"res://items/tool/Ax.tres",
	"res://items/tool/Pickaxe.tres",
]
const LEGACY_TOOL_DATA_CS_PATH: String = "res://resources/item/tool/ToolData.cs"
const MONSTER_SKILL_ASSETS: Array[String] = [
	"res://resources/monster/anvil_cuihuotiewei.tres",
	"res://resources/monster/anvil_duantiezhano.tres",
	"res://resources/monster/test_monster_1.tres",
	"res://resources/monster/test_monster_2.tres",
]
const LOOT_DROP_ASSETS: Array[String] = [
	"res://resources/monster/anvil_cuihuotiewei.tres",
	"res://resources/monster/test_monster_1.tres",
	"res://resources/monster/tree_gulinshuren.tres",
]
const TERRAIN_RANGE_ASSETS: Array[String] = [
	"res://resources/map/terrain/earth_terrain.tres",
	"res://resources/map/terrain/fire_terrain.tres",
	"res://resources/map/terrain/gold_terrain.tres",
	"res://resources/map/terrain/normal_terrain.tres",
	"res://resources/map/terrain/reusable_wood_terrain.tres",
	"res://resources/map/terrain/water_terrain.tres",
	"res://resources/map/terrain/wood_terrain.tres",
]
const STARTING_STATS_ASSETS: Array[String] = [
	"res://resources/monster/anvil_cuihuotiewei.tres",
	"res://resources/monster/test_monster_1.tres",
	"res://resources/debug/default_inventory_loadout.tres",
]
const GATHERING_CARD_ASSETS: Array[Dictionary] = [
	{"path": "res://res/terrain/under_lake.tres", "tag": &"lake"},
	{"path": "res://res/terrain/sand.tres", "tag": &"sand"},
	{"path": "res://res/terrain/berryubush.tres", "tag": &"bush"},
]
const GATHERING_PROFILE_ASSETS: Array[Dictionary] = [
	{"path": "res://resources/map/terrain/wood_terrain.tres", "tag": &"wood"},
	{"path": "res://resources/map/terrain/gold_terrain.tres", "tag": &"gold"},
	{"path": "res://resources/map/terrain/water_terrain.tres", "tag": &"water"},
	{"path": "res://resources/map/terrain/fire_terrain.tres", "tag": &"fire"},
	{"path": "res://resources/map/terrain/earth_terrain.tres", "tag": &"earth"},
	{"path": "res://resources/map/terrain/normal_terrain.tres", "tag": &"wood"},
]


## 模拟 TerrainInstance 的可写运行时状态。
class FakeTerrain extends RefCounted:
	## 是否已经完成一次性采集。
	var IsHarvested: bool = false
	## 是否已经被农场等玩法占用。
	var IsOccupied: bool = false
	## 剩余采集次数。
	var RemainingGatheringCount: int = -1
	## 下一次刷新所需的游戏总时间。
	var RefreshReadyTotalTime: int = 0


## 模拟 EquipmentComponent 暴露给 GDScript 资源的两个查询方法。
class FakeEquipment extends RefCounted:
	## 工具提供的采集时间减免。
	var reduction: int = 0
	## 工具提供的额外掉落数量。
	var yield_bonus: int = 0
	## 允许生效的装备槽位。
	var reduction_slot: int = 5

	## 返回与资源标签和槽位匹配时的时间减免。
	func GetGatheringTimeReduction(_tag: StringName, slot: int) -> int:
		return reduction if slot == reduction_slot else 0

	## 返回本次采集的额外掉落数量。
	func GetGatheringYieldBonus(_tag: StringName) -> int:
		return yield_bonus


## 模拟 Player 的 Equipment 属性。
class FakePlayer extends RefCounted:
	## 当前装备组件。
	var Equipment: FakeEquipment


## 模拟 LootTable 的稳定 RollLoot 方法并记录额外产量输入。
class FakeLootTable extends Resource:
	## 预设返回的掉落对象。
	var drops: Array = []
	## 最近一次收到的额外产量。
	var received_extra_yield: int = -1

	## 返回预设掉落，并保存调用方传入的额外产量。
	func RollLoot(extra_yield: int) -> Array:
		received_extra_yield = extra_yield
		return drops


## 模拟 CombatSkillData 的显示字段和 Execute 方法，验证技能卡只负责委托。
class FakeCombatSkill extends Resource:
	## 技能导出的卡牌名称；与保留 C# CombatSkillData 的序列化字段一致。
	var CardName: String = "协议技能"
	## 技能导出的卡牌描述；与保留 C# CombatSkillData 的序列化字段一致。
	var Description: String = "协议技能描述"
	## 技能导出的卡牌图标；与保留 C# CombatSkillData 的序列化字段一致。
	var CardIcon: Texture2D = null
	## 技能五行枚举值。
	var Element: int = 5
	## Execute 累计调用次数。
	var execute_count: int = 0
	## 最近一次收到的执行上下文。
	var last_context: RefCounted = null

	## 记录技能卡委托的执行上下文。
	## 参数 context：技能卡传入的上下文对象。
	## 返回值：无。
	func Execute(context: RefCounted) -> void:
		execute_count += 1
		last_context = context


## 提供 ShopService 使用的最小钱包协议，记录扣款与进账次数。
class FakeShopWallet extends RefCounted:
	## 当前金币余额。
	var Gold: int = 0
	## 尝试扣款次数。
	var spend_count: int = 0
	## 增加金币次数。
	var add_count: int = 0

	## 余额足够时扣除金币。
	func TrySpend(amount: int) -> bool:
		spend_count += 1
		if amount <= 0 or Gold < amount:
			return false
		Gold -= amount
		return true

	## 增加金币，忽略非正数。
	func Add(amount: int) -> void:
		if amount <= 0:
			return
		add_count += 1
		Gold += amount


## 提供 PlayerProgression 使用的最小仓库容量协议。
class FakeProgressionWarehouse extends RefCounted:
	## 当前仓库槽位数。
	var Capacity: int = 27

	## 接收升级后的仓库容量。
	func SetCapacity(capacity: int) -> void:
		Capacity = capacity


## 模拟 CombatSkillData 暴露的技能说明字段，验证预览回退不依赖 C# 类型声明。
class FakeSkill extends Resource:
	## 技能自身的预览说明。
	var Description: String = ""
	## 技能稳定标识与展示字段。
	var CardId: StringName = &""
	var CardName: String = ""
	var CardIcon: Texture2D
	## 与旧 C# 枚举对应的整数值。
	var Element: int = 0
	var TargetingType: int = 0


## 提供当前房间字段的最小 MapInstantiator 夹具。
class FakeBackgroundMapInstantiator extends Node:
	var current_scene: Node


## 模拟 TagComponent 的稳定 HasTag 方法，隔离概率服务与 C# 节点实现。
class FakeTags extends RefCounted:
	## 当前拥有的标签集合。
	var active_tags: Dictionary = {}

	## 为测试对象增加一个可匹配标签。
	func add_tag(tag: StringName) -> void:
		active_tags[tag] = true

	## 返回测试对象是否拥有指定标签。
	func HasTag(tag: StringName) -> bool:
		return active_tags.has(tag)


## 返回套件名称，便于 test_run 精确过滤。
func suite_name() -> String:
	return "reusable_gathering"


## 验证只有配置槽位且标签匹配的工具才会降低耗时，且不低于下限。
func test_effective_time_cost_respects_slot_and_minimum() -> void:
	var interaction: Resource = INTERACTION_SCRIPT.new()
	interaction.set("TimeCost", 20)
	interaction.set("GatheringTag", &"wood")
	interaction.set("MinimumTimeCost", 5)
	interaction.set("EffectiveToolSlot", 5)
	var equipment := FakeEquipment.new()
	equipment.reduction = 10

	assert_eq(interaction.call("get_effective_time_cost", equipment), 10, "匹配槽位工具应降低有效采集耗时。")
	equipment.reduction_slot = 4
	assert_eq(interaction.call("get_effective_time_cost", equipment), 20, "其它装备槽位不应影响采集耗时。")
	equipment.reduction_slot = 5
	equipment.reduction = 99
	assert_eq(interaction.call("get_effective_time_cost", equipment), 5, "工具减免后耗时不得低于 MinimumTimeCost。")


## 验证采集次数耗尽后按游戏时间恢复完整次数。
func test_harvest_count_refreshes_by_total_time() -> void:
	var interaction: Resource = INTERACTION_SCRIPT.new()
	interaction.set("MaxHarvestCount", 2)
	interaction.set("RefreshTimeCost", 30)
	var terrain := FakeTerrain.new()

	assert_true(interaction.call("can_harvest", terrain, 0), "未初始化资源点应先恢复为可采集状态。")
	assert_eq(terrain.RemainingGatheringCount, 2, "初始化次数应等于 MaxHarvestCount。")
	interaction.call("record_successful_harvest", terrain, 10)
	interaction.call("record_successful_harvest", terrain, 20)
	assert_eq(terrain.RemainingGatheringCount, 0, "两次采集后次数应耗尽。")
	assert_eq(terrain.RefreshReadyTotalTime, 50, "耗尽时应记录完成采集时间加刷新消耗。")
	assert_false(interaction.call("can_harvest", terrain, 49), "冷却未到期时不得恢复采集。")
	assert_true(interaction.call("can_harvest", terrain, 50), "到达刷新时间后应恢复采集。")
	assert_eq(terrain.RemainingGatheringCount, 2, "刷新后应恢复完整采集次数。")


## 验证输入开始时的耗时快照和操作顺序，并确认没有移除资源卡操作。
func test_build_ops_keeps_snapshot_and_source_card() -> void:
	var interaction: Resource = INTERACTION_SCRIPT.new()
	interaction.set("GatheringTag", &"wood")
	interaction.set("MaxHarvestCount", 1)
	var terrain := FakeTerrain.new()
	var player := FakePlayer.new()
	player.Equipment = FakeEquipment.new()

	var ops: Array = interaction.call("build_ops", player, terrain, 17)
	assert_eq(ops.size(), 3, "有标签采集应生成耗时、遭遇检查和状态记录三类操作。")
	assert_eq(ops[0].get("type"), "pass_time", "第一步必须先结算时间。")
	assert_eq(ops[0].get("amount"), 17, "应使用输入开始时传入的有效耗时快照。")
	assert_eq(ops[1].get("type"), "check_gathering_encounter", "第二步应检查采集遭遇。")
	assert_eq(ops[2].get("type"), "record_reusable_gathering", "最后一步应记录资源点次数。")
	for op: Dictionary in ops:
		assert_ne(op.get("type"), "remove_source_card", "可重复采集不得移除资源卡。")


## 验证长按秒数继续复用统一的行动值换算规则。
func test_required_hold_seconds_uses_world_timing() -> void:
	var interaction: Resource = INTERACTION_SCRIPT.new()
	interaction.set("TimeCost", 20)
	interaction.set("MinimumTimeCost", 1)
	assert_true(
		is_equal_approx(float(interaction.call("get_required_hold_seconds", null)), 2.0),
		"20 点有效耗时应对应 2 秒长按。"
	)


## 验证一次性采集保留字段、额外产量、已采集判断和完整操作顺序。
func test_gathering_interaction_build_ops_preserves_order() -> void:
	var interaction: Resource = GATHERING_INTERACTION_SCRIPT.new()
	assert_eq(interaction.get("TimeCost"), 20, "一次性采集默认耗时必须保持为 20。")
	assert_eq(interaction.get("GatheringTag"), &"", "一次性采集默认标签必须为空。")
	assert_eq(interaction.get("DropTable"), null, "一次性采集默认掉落表必须为空。")

	var player := FakePlayer.new()
	player.Equipment = FakeEquipment.new()
	player.Equipment.yield_bonus = 3
	var terrain := FakeTerrain.new()
	var drop := Resource.new()
	var table := FakeLootTable.new()
	table.drops = [drop]
	interaction.set("TimeCost", 41)
	interaction.set("GatheringTag", &"wood")
	interaction.set("DropTable", table)

	var ops: Array = interaction.call("build_ops", player, terrain, 9)
	assert_eq(table.received_extra_yield, 3, "掉落表必须收到原装备额外产量。")
	assert_eq(ops.size(), 5, "有掉落的一次性采集必须生成五个操作。")
	assert_eq(ops[0].get("type"), "pass_time", "一次性采集必须先推进时间。")
	assert_eq(ops[0].get("amount"), 41, "一次性采集必须保持旧实现并使用资源自身耗时。")
	assert_eq(ops[1].get("type"), "mark_harvested", "时间结算后必须标记地形已采集。")
	assert_eq(ops[2].get("type"), "spawn_loot", "未采集地形必须在标记后生成掉落。")
	assert_eq(ops[2].get("drops")[0], drop, "掉落操作必须保留掉落对象身份。")
	assert_eq(ops[3].get("type"), "check_gathering_encounter", "掉落后必须检查采集遭遇。")
	assert_eq(ops[3].get("gathering_tag"), &"wood", "采集遭遇必须收到原标签。")
	assert_eq(ops[4].get("type"), "remove_source_card", "一次性采集必须最后移除源卡。")

	terrain.IsHarvested = true
	table.received_extra_yield = -1
	ops = interaction.call("build_ops", player, terrain)
	assert_eq(ops.size(), 4, "已采集地形必须跳过掉落但保留其它操作。")
	assert_eq(table.received_extra_yield, -1, "已采集地形不得再次滚动掉落表。")
	assert_eq(ops[2].get("type"), "check_gathering_encounter", "已采集地形仍保持旧遭遇检查顺序。")
	assert_eq(ops[3].get("type"), "remove_source_card", "已采集地形仍必须移除源卡。")


## 验证农场交互保留默认耗时、占用判断和操作顺序。
func test_farming_interaction_build_ops_preserves_occupancy() -> void:
	var interaction: Resource = FARMING_INTERACTION_SCRIPT.new()
	assert_eq(interaction.get("TimeCost"), 20, "农场交互默认耗时必须保持为 20。")
	interaction.set("TimeCost", 36)
	var terrain := FakeTerrain.new()

	var ops: Array = interaction.call("build_ops", null, terrain, 7)
	assert_eq(ops.size(), 2, "未占用地形必须生成时间与打开农场面板两个操作。")
	assert_eq(ops[0].get("type"), "pass_time", "农场交互必须先推进时间。")
	assert_eq(ops[0].get("amount"), 36, "农场交互必须使用资源自身耗时，而不是长按快照。")
	assert_eq(ops[1].get("type"), "open_farming_panel", "未占用地形必须请求打开农场面板。")

	terrain.IsOccupied = true
	ops = interaction.call("build_ops", null, terrain)
	assert_eq(ops.size(), 1, "已占用地形必须只保留时间操作。")
	assert_eq(ops[0].get("type"), "pass_time", "已占用地形仍必须保持旧时间结算行为。")


## 验证十个一次性采集生产资产全部切换到 GDScript 且保留标签与掉落表。
func test_gathering_production_assets_use_gdscript() -> void:
	for entry: Dictionary in GATHERING_CARD_ASSETS:
		var card: Resource = load(String(entry["path"])) as Resource
		_assert_gathering_card(card, StringName(entry["tag"]), String(entry["path"]))

	for entry: Dictionary in GATHERING_PROFILE_ASSETS:
		var profile: Resource = load(String(entry["path"])) as Resource
		assert_true(profile != null, "%s 必须能够加载。" % entry["path"])
		if profile == null:
			continue
		var pool: Array = profile.get("TerrainPool")
		assert_false(pool.is_empty(), "%s 必须保留地形池条目。" % entry["path"])
		if pool.is_empty():
			continue
		var card: Resource = pool[0].get("TerrainData") as Resource
		_assert_gathering_card(card, StringName(entry["tag"]), String(entry["path"]))

	var desert_scene: PackedScene = load("res://scenes/map_scenes/map_son_scenes/map_desert.tscn")
	assert_true(desert_scene != null, "沙漠地图必须能够加载。")
	if desert_scene == null:
		return
	var desert_map: Node = desert_scene.instantiate()
	var desert_profile: Resource = desert_map.get("terrain_profile") as Resource
	assert_true(desert_profile != null, "沙漠地图必须保留地形布局配置。")
	if desert_profile != null:
		var pool: Array = desert_profile.get("TerrainPool")
		assert_false(pool.is_empty(), "沙漠地图必须保留石头采集条目。")
		if not pool.is_empty():
			var card: Resource = pool[0].get("TerrainData") as Resource
			_assert_gathering_card(card, &"stone", "沙漠地图")
	desert_map.free()

	var generator_source := FileAccess.get_file_as_string("res://scripts/generated/create_terrain_profiles.gd")
	assert_true(
		generator_source.contains("res://resources/interaction/gathering_interaction.gd"),
		"地形 Profile 生成脚本必须写入新的 GDScript 交互路径。"
	)
	assert_false(
		generator_source.contains("res://resources/interaction/GatheringInteraction.cs"),
		"地形 Profile 生成脚本不得重新写回旧 C# 交互路径。"
	)


## 断言一个生产地形卡的一次性采集脚本、字段和值保持兼容。
func _assert_gathering_card(card: Resource, expected_tag: StringName, context: String) -> void:
	assert_true(card != null, "%s 必须保留地形卡数据。" % context)
	if card == null:
		return
	var interaction: Resource = card.get("InteractionBehavior") as Resource
	assert_true(interaction != null, "%s 必须保留一次性采集交互。" % context)
	if interaction == null:
		return
	assert_eq(
		interaction.get_script().resource_path,
		"res://resources/interaction/gathering_interaction.gd",
		"%s 必须使用 GDScript 一次性采集交互。" % context
	)
	assert_eq(interaction.get("TimeCost"), 20, "%s 必须保留默认采集耗时。" % context)
	assert_eq(interaction.get("GatheringTag"), expected_tag, "%s 必须保留原采集标签。" % context)
	var drop_table: Resource = interaction.get("DropTable") as Resource
	assert_true(drop_table != null, "%s 必须保留原掉落表。" % context)
	if drop_table != null:
		assert_eq(
			drop_table.get_script().resource_path,
			"res://resources/loot/loot_table.gd",
			"%s 必须使用生产 GDScript LootTable。" % context
		)


## 验证密库交互保留默认耗时、序列化字段和操作顺序。
func test_vault_interaction_build_ops_preserves_order() -> void:
	var interaction: Resource = VAULT_INTERACTION_SCRIPT.new()
	assert_eq(interaction.get("TimeCost"), 20, "密库默认耗时必须保持为 20。")
	interaction.set("TimeCost", 37)
	var ops: Array = interaction.call("build_ops", null, null, 11)
	assert_eq(ops.size(), 2, "密库交互必须生成两个操作。")
	assert_eq(ops[0].get("type"), "pass_time", "密库必须先推进时间。")
	assert_eq(ops[0].get("amount"), 37, "密库必须保持旧实现并使用当前序列化耗时，而不是长按快照。")
	assert_eq(ops[1].get("type"), "enter_vault", "密库必须在时间结算后请求打开仓库。")


## 验证火山地图的密库卡已经切换到 GDScript 交互资源。
func test_volcanic_vault_interaction_uses_gdscript() -> void:
	var volcanic_scene: PackedScene = load("res://scenes/map_scenes/map_son_scenes/map_volcanic.tscn")
	assert_true(volcanic_scene != null, "火山地图场景必须能够加载。")
	if volcanic_scene == null:
		return
	var volcanic_map: Node = volcanic_scene.instantiate()
	var profile: Resource = volcanic_map.get("terrain_profile") as Resource
	assert_true(profile != null, "火山地图必须保留地形布局配置。")
	if profile != null:
		var pool: Array = profile.get("TerrainPool")
		assert_eq(pool.size(), 1, "火山地图必须保留唯一密库地形条目。")
		if not pool.is_empty():
			var card: Resource = pool[0].get("TerrainData") as Resource
			var interaction: Resource = card.get("InteractionBehavior") as Resource
			assert_true(interaction != null, "火山密库卡必须保留交互资源。")
			if interaction != null:
				assert_eq(
					interaction.get_script().resource_path,
					"res://resources/interaction/vault_interaction.gd",
					"火山密库必须使用 GDScript 交互资源。"
				)
				assert_eq(interaction.get("TimeCost"), 20, "生产密库资源必须保留原耗时。")
	volcanic_map.free()


## 验证 Boss 交互保留序列化字段、Monster 身份和操作顺序。
func test_boss_interaction_build_ops_preserves_order() -> void:
	var interaction: Resource = BOSS_INTERACTION_SCRIPT.new()
	assert_eq(interaction.get("TimeCost"), 20, "Boss 交互默认耗时必须保持为 20。")
	assert_eq(interaction.get("Monster"), null, "Boss 交互默认怪物必须为空。")
	var monster := Resource.new()
	interaction.set("TimeCost", 43)
	interaction.set("Monster", monster)
	var ops: Array = interaction.call("build_ops", null, null, 12)
	assert_eq(ops.size(), 3, "Boss 交互必须生成三个操作。")
	assert_eq(ops[0].get("type"), "pass_time", "Boss 交互必须先推进时间。")
	assert_eq(ops[0].get("amount"), 43, "Boss 交互必须保持旧实现并使用当前序列化耗时。")
	assert_eq(ops[1].get("type"), "spawn_monster", "Boss 交互必须在时间结算后请求遭遇。")
	assert_eq(ops[1].get("monster"), monster, "Boss 操作必须保留原 Monster Resource 身份。")
	assert_eq(ops[2].get("type"), "remove_source_card", "Boss 交互必须最后移除源卡。")


## 验证两个 Boss 地图都已切换到 GDScript，同时保留原 C# MonsterData。
func test_boss_map_interactions_use_gdscript() -> void:
	var scene_paths: Array[String] = [
		"res://scenes/map_scenes/map_son_scenes/map_boss_room.tscn",
		"res://scenes/map_scenes/map_son_scenes/map_snowfield.tscn",
	]
	for scene_path: String in scene_paths:
		var packed_scene: PackedScene = load(scene_path)
		assert_true(packed_scene != null, "%s 必须能够加载。" % scene_path)
		if packed_scene == null:
			continue
		var map_node: Node = packed_scene.instantiate()
		var profile: Resource = map_node.get("terrain_profile") as Resource
		assert_true(profile != null, "%s 必须保留地形布局配置。" % scene_path)
		if profile != null:
			var pool: Array = profile.get("TerrainPool")
			assert_eq(pool.size(), 1, "%s 必须保留唯一 Boss 地形条目。" % scene_path)
			if not pool.is_empty():
				var card: Resource = pool[0].get("TerrainData") as Resource
				var interaction: Resource = card.get("InteractionBehavior") as Resource
				assert_true(interaction != null, "%s 必须保留 Boss 交互资源。" % scene_path)
				if interaction != null:
					assert_eq(
						interaction.get_script().resource_path,
						"res://resources/interaction/boss_interaction.gd",
						"%s 必须使用 GDScript Boss 交互资源。" % scene_path
					)
					assert_eq(interaction.get("TimeCost"), 20, "%s 必须保留原 Boss 耗时。" % scene_path)
					var monster: Resource = interaction.get("Monster") as Resource
					assert_true(monster != null, "%s 必须保留原怪物数据资源。" % scene_path)
					if monster != null:
						assert_eq(
							monster.get_script().resource_path,
							"res://resources/monster/monster_data.gd",
							"%s 的 Boss 怪物必须使用 GDScript 怪物数据生产实现。" % scene_path
						)
						assert_true(
							str(monster.get("MonsterName")) != "",
							"%s 的 Boss 怪物必须保留名称字段。" % scene_path
						)
		map_node.free()


## 验证现有 reusable_wood 资源链已经指向 GDScript Resource，而非旧 C# 脚本。
func test_reusable_terrain_resource_uses_gdscript() -> void:
	var profile: Resource = load("res://resources/map/terrain/reusable_wood_terrain.tres")
	assert_true(profile != null, "可重复树木地形资源必须能够加载。")
	var terrain_pool: Array = profile.get("TerrainPool")
	assert_true(not terrain_pool.is_empty(), "可重复树木资源必须保留地形池配置。")
	var terrain_card: Resource = terrain_pool[0].get("TerrainData")
	var interaction: Resource = terrain_card.get("InteractionBehavior")
	assert_true(interaction != null, "地形卡必须保留可重复采集交互资源。")
	assert_eq(
		interaction.get_script().resource_path,
		"res://resources/interaction/reusable_gathering_interaction.gd",
		"可重复树木地形必须使用 GDScript 交互资源。"
	)


## 验证地形池条目保留字段默认值，并确认实际地形资产已切换到 GDScript Resource。
func test_room_terrain_pool_entry_migrated() -> void:
	var entry: Resource = ROOM_TERRAIN_POOL_ENTRY_SCRIPT.new()
	assert_eq(entry.get("TerrainData"), null, "新建地形池条目的 TerrainData 默认应为空。")
	assert_true(is_equal_approx(float(entry.get("Weight")), 1.0), "地形池条目的默认权重应为 1。")

	var profile: Resource = load("res://resources/map/terrain/reusable_wood_terrain.tres")
	assert_true(profile != null, "可重复树木地形配置必须能够加载。")
	if profile == null:
		return

	var pool: Array = profile.get("TerrainPool")
	assert_true(not pool.is_empty(), "地形配置必须保留至少一个地形池条目。")
	if pool.is_empty():
		return

	assert_eq(
		pool[0].get_script().resource_path,
		"res://core/map/room_terrain_pool_entry.gd",
		"地形池条目必须使用 GDScript Resource。"
	)


## 验证地形布局配置保留字段默认值，并确认代表性地形资源已切换到 GDScript。
func test_room_terrain_profile_migrated() -> void:
	var profile: Resource = ROOM_TERRAIN_PROFILE_SCRIPT.new()
	assert_eq(profile.get("TerrainPool").size(), 0, "新建地形布局配置的地形池应为空。")
	assert_eq(profile.get("MinCount"), 1, "地形布局配置的最小数量默认值应为 1。")
	assert_eq(profile.get("MaxCount"), 3, "地形布局配置的最大数量默认值应为 3。")
	assert_eq(profile.get("GridColumns"), 6, "地形布局配置的网格列数默认值应为 6。")
	assert_eq(profile.get("GridRows"), 4, "地形布局配置的网格行数默认值应为 4。")

	var asset: Resource = load("res://resources/map/terrain/reusable_wood_terrain.tres")
	assert_true(asset != null, "可重复树木地形布局配置必须能够加载。")
	if asset == null:
		return
	assert_eq(
		asset.get_script().resource_path,
		"res://core/map/room_terrain_profile.gd",
		"地形布局配置必须使用 GDScript Resource。"
	)


## 验证地形卡 Resource 保留原有字段，并且代表性地图资产都使用新脚本。
func test_terrain_card_resource_migrated() -> void:
	var terrain_card: Resource = TERRAIN_CARD_DATA_SCRIPT.new()
	assert_eq(terrain_card.get("CardId"), &"", "地形卡默认 CardId 必须为空标签。")
	assert_eq(terrain_card.get("CardName"), "", "地形卡默认 CardName 必须为空字符串。")
	assert_eq(terrain_card.get("InteractionBehavior"), null, "地形卡默认交互资源必须为空。")

	var asset_paths: Array[String] = [
		"res://resources/map/terrain/earth_terrain.tres",
		"res://resources/map/terrain/fire_terrain.tres",
		"res://resources/map/terrain/gold_terrain.tres",
		"res://resources/map/terrain/normal_terrain.tres",
		"res://resources/map/terrain/reusable_wood_terrain.tres",
		"res://resources/map/terrain/water_terrain.tres",
		"res://resources/map/terrain/wood_terrain.tres",
	]
	for asset_path: String in asset_paths:
		var profile: Resource = load(asset_path)
		assert_true(profile != null, "%s 必须能够加载。" % asset_path)
		if profile == null:
			continue
		var pool: Array = profile.get("TerrainPool")
		assert_true(not pool.is_empty(), "%s 必须保留地形池。" % asset_path)
		for entry: Resource in pool:
			var card: Resource = entry.get("TerrainData")
			assert_true(card != null, "%s 的地形池条目必须保留 TerrainData。" % asset_path)
			if card != null:
				assert_eq(card.get_script().resource_path, "res://resources/interaction/terrain_card_data.gd", "%s 的地形卡必须使用 GDScript Resource。" % asset_path)
				assert_true(card.get("InteractionBehavior") != null, "%s 的地形卡必须保留交互资源。" % asset_path)

	var direct_card_paths: Array[String] = [
		"res://res/terrain/under_lake.tres",
		"res://res/terrain/sand.tres",
		"res://res/terrain/berryubush.tres",
	]
	for asset_path: String in direct_card_paths:
		var card: Resource = load(asset_path)
		assert_true(card != null, "%s 必须能够加载。" % asset_path)
		if card == null:
			continue
		assert_eq(card.get_script().resource_path, "res://resources/interaction/terrain_card_data.gd", "%s 的直接地形卡必须使用 GDScript Resource。" % asset_path)
		assert_true(card.get("InteractionBehavior") != null, "%s 必须保留交互资源。" % asset_path)
		assert_false(card.has_meta("_custom_type_script"), "%s 不得保留旧 C# 地形卡类型元数据。" % asset_path)


## 验证 StartingStats 的字段默认值和代表性资产均已切换到 GDScript Resource。
func test_starting_stats_resource_migrated() -> void:
	var stats: Resource = STARTING_STATS_SCRIPT.new()
	var expected_defaults: Dictionary = {
		"BasePhysAtk": 100.0,
		"PhysAtkGrowth": 25.0,
		"BasePhysDef": 100.0,
		"PhysDefGrowth": 20.0,
		"BaseMagPower": 100.0,
		"MagPowerGrowth": 30.0,
		"BaseMagResist": 100.0,
		"MagResistGrowth": 20.0,
		"BaseSpeed": 100.0,
		"SpeedGrowth": 5.0,
		"BaseMaxHealth": 1000.0,
		"BaseMaxEnergy": 100.0,
		"BaseCritDamage": 1.5,
	}
	for property_name: String in expected_defaults:
		assert_true(
			is_equal_approx(float(stats.get(property_name)), float(expected_defaults[property_name])),
			"StartingStats 默认字段 %s 必须保持原值。" % property_name
		)

	for asset_path: String in STARTING_STATS_ASSETS:
		var asset: Resource = load(asset_path)
		assert_true(asset != null, "%s 必须能够加载。" % asset_path)
		if asset == null:
			continue
		var nested_stats: Resource = asset.get("InitialAttributes") as Resource
		if nested_stats == null:
			nested_stats = asset.get("PlayerStartingStats") as Resource
		assert_true(nested_stats != null, "%s 必须保留 StartingStats 配置。" % asset_path)
		if nested_stats != null:
			assert_eq(
				nested_stats.get_script().resource_path,
				"res://resources/stats/starting_stats.gd",
				"%s 的 StartingStats 必须使用 GDScript Resource。" % asset_path
			)


## 验证遭遇倍率范围资源的默认值、上下界独立性和实际地形资产引用。
func test_monster_stat_multiplier_range_migrated() -> void:
	var range: Resource = RANGE_SCRIPT.new()
	assert_true(is_equal_approx(float(range.get("MinMaxHealth")), 1.0), "倍率下界默认值应为 1。")
	assert_true(is_equal_approx(float(range.get("MaxSpeed")), 1.0), "倍率上界默认值应为 1。")
	range.set("MinPhysAtk", 0.9)
	range.set("MaxPhysAtk", 1.2)
	var minimums: Dictionary = range.call("get_min")
	var maximums: Dictionary = range.call("get_max")
	assert_true(is_equal_approx(float(minimums["PhysAtk"]), 0.9), "下界快照应读取 MinPhysAtk。")
	assert_true(is_equal_approx(float(maximums["PhysAtk"]), 1.2), "上界快照应读取 MaxPhysAtk。")

	for terrain_path: String in TERRAIN_RANGE_ASSETS:
		var profile: Resource = load(terrain_path)
		assert_true(profile != null, "%s 必须能够加载。" % terrain_path)
		var variance: Resource = profile.get("EncounterVarianceRange")
		assert_true(variance != null, "%s 必须保留遭遇倍率范围。" % terrain_path)
		assert_eq(
			variance.get_script().resource_path,
			"res://resources/encounters/monster_stat_multiplier_range.gd",
			"%s 必须使用 GDScript 倍率范围资源。" % terrain_path
		)
		assert_true(is_equal_approx(float(variance.get("MinMaxHealth")), 0.9), "%s 必须保留下界倍率。" % terrain_path)
		assert_true(is_equal_approx(float(variance.get("MaxMaxHealth")), 1.2), "%s 必须保留上界倍率。" % terrain_path)


## 验证通道驻守概率修正资源保留原 C# 资源的字段名称与默认值。
func test_passage_guard_probability_modifier_defaults() -> void:
	var modifier: Resource = MODIFIER_SCRIPT.new()
	assert_eq(modifier.get("RequiredTag"), &"", "RequiredTag 默认应为空标签。")
	assert_true(is_equal_approx(float(modifier.get("AdditiveChance")), 0.0), "AdditiveChance 默认应为 0。")
	assert_true(is_equal_approx(float(modifier.get("Multiplier")), 1.0), "Multiplier 默认应为 1。")


## 验证默认驻守配置中的中性修正已经切换到 GDScript Resource。
func test_default_passage_guard_settings_uses_gdscript_modifier() -> void:
	var settings: Resource = load("res://resources/map/default_passage_guard_settings.tres")
	assert_true(settings != null, "默认通道驻守配置应当能够加载。")
	if settings == null:
		return

	var modifiers: Array = settings.get("ProbabilityModifiers")
	assert_eq(modifiers.size(), 1, "默认配置应保留一个中性概率修正样本。")
	if modifiers.is_empty():
		return

	var modifier: Resource = modifiers[0]
	assert_eq(
		modifier.get_script().resource_path,
		"res://resources/map/passage_guard_probability_modifier.gd",
		"默认配置中的概率修正应使用 GDScript 脚本。"
	)
	assert_true(is_equal_approx(float(modifier.get("AdditiveChance")), 0.0), "中性修正不应改变加法概率。")
	assert_true(is_equal_approx(float(modifier.get("Multiplier")), 1.0), "中性修正不应改变乘法概率。")


## 验证采集遭遇规则 Resource 保留旧字段名称与默认提示语。
func test_gathering_encounter_rule_defaults() -> void:
	var rule: Resource = GATHERING_RULE_SCRIPT.new()
	assert_eq(rule.get("TriggerTag"), &"", "TriggerTag 默认应为空标签。")
	assert_eq(rule.get("MonsterToSpawn").size(), 0, "MonsterToSpawn 默认应为空数组。")
	assert_eq(rule.get("SpawnMessage"), "糟糕！采集物变成了怪物！", "SpawnMessage 默认提示语必须保持原文。")
	assert_true(is_equal_approx(float(rule.get("ExtraChanceMultiplier")), 1.0), "ExtraChanceMultiplier 默认应为 1。")


## 验证通道驻守 encounter Resource 保留怪物数组字段和默认空值。
func test_passage_guard_encounter_data_defaults() -> void:
	var encounter: Resource = PASSAGE_GUARD_ENCOUNTER_SCRIPT.new()
	assert_eq(encounter.get("Monsters").size(), 0, "新建驻守 encounter 的怪物数组应为空。")

	var settings: Resource = load("res://resources/map/default_passage_guard_settings.tres")
	assert_true(settings != null, "默认通道驻守配置应当能够加载。")
	if settings == null:
		return

	var pool: Array = settings.get("DefaultGuardPool")
	assert_eq(pool.size(), 2, "默认驻守池应保留两个 encounter。")
	if pool.is_empty():
		return
	assert_eq(
		pool[0].get_script().resource_path,
		"res://resources/map/passage_guard_encounter_data.gd",
		"默认驻守池应使用 GDScript encounter Resource。"
	)


## 验证怪物技能条目的默认值、预览覆盖和技能说明回退行为。
func test_monster_skill_entry_preview_fallback() -> void:
	var entry: Resource = MONSTER_SKILL_ENTRY_SCRIPT.new()
	assert_true(entry.get("VisibleInPreview"), "怪物技能条目默认应在预览中显示。")
	assert_eq(entry.get("PreviewDescriptionOverride"), "", "预览覆盖文本默认应为空。")
	assert_eq(entry.call("GetPreviewDescription"), "", "缺少技能时预览说明应为空。")

	var skill := FakeSkill.new()
	skill.Description = "技能自身说明"
	entry.set("Skill", skill)
	assert_eq(entry.call("GetPreviewDescription"), "技能自身说明", "未设置覆盖文本时应回退到技能 Description。")
	entry.set("PreviewDescriptionOverride", "  自定义预览  ")
	assert_eq(entry.call("GetPreviewDescription"), "  自定义预览  ", "非空白覆盖文本应保持原文返回。")
	entry.set("PreviewDescriptionOverride", " \t\n")
	assert_eq(entry.call("GetPreviewDescription"), "技能自身说明", "仅空白覆盖文本应继续回退到技能说明。")


## 验证怪物技能集合默认数组及代表性怪物资源的脚本引用和条目内容。
func test_monster_skill_set_assets_use_gdscript() -> void:
	var empty_set: Resource = MONSTER_SKILL_SET_SCRIPT.new()
	assert_eq(empty_set.get("Skills").size(), 0, "新建怪物技能集合的 Skills 默认应为空数组。")

	for asset_path: String in MONSTER_SKILL_ASSETS:
		var monster: Resource = load(asset_path)
		assert_true(monster != null, "%s 必须能够加载。" % asset_path)
		if monster == null:
			continue
		var skill_set: Resource = monster.get("SkillSet")
		assert_true(skill_set != null, "%s 必须保留 SkillSet。" % asset_path)
		if skill_set == null:
			continue
		assert_eq(
			skill_set.get_script().resource_path,
			"res://resources/monster/monster_skill_set_data.gd",
			"%s 的 SkillSet 必须使用 GDScript Resource。" % asset_path
		)
		var entries: Array = skill_set.get("Skills")
		assert_true(entries != null, "%s 的 SkillSet 必须保留 Skills 数组。" % asset_path)
		if asset_path.ends_with("test_monster_2.tres"):
			assert_true(entries.is_empty(), "测试怪物 2 原本没有技能条目，迁移后仍应保持空数组。")
		else:
			assert_true(not entries.is_empty(), "%s 的 SkillSet 必须保留技能条目。" % asset_path)
		for entry: Resource in entries:
			assert_eq(
				entry.get_script().resource_path,
				"res://resources/monster/monster_skill_entry_data.gd",
				"%s 的技能条目必须使用 GDScript Resource。" % asset_path
			)


## 验证怪物技能组件与预览值对象保留旧 C# 的稳定方法、字段和过滤顺序。
func test_monster_skill_component_and_preview_contract() -> void:
	var skill: FakeSkill = FakeSkill.new()
	skill.CardId = &"probe_skill"
	skill.CardName = "探针技能"
	skill.Description = "技能说明"
	skill.Element = 4
	skill.TargetingType = 2

	var visible_entry: Resource = MONSTER_SKILL_ENTRY_SCRIPT.new()
	visible_entry.set("Skill", skill)
	var hidden_entry: Resource = MONSTER_SKILL_ENTRY_SCRIPT.new()
	hidden_entry.set("Skill", skill)
	hidden_entry.set("VisibleInPreview", false)
	var skill_set: Resource = MONSTER_SKILL_SET_SCRIPT.new()
	var configured_skills: Array[Resource] = [visible_entry, hidden_entry]
	skill_set.set("Skills", configured_skills)

	var component = MONSTER_SKILL_COMPONENT_SCRIPT.new()
	component.Initialize(skill_set)
	var combat_skills: Array = component.GetCombatSkills()
	assert_eq(combat_skills.size(), 2, "技能组件应保留两个有效技能条目")
	assert_true(combat_skills[0] == skill, "技能组件不得复制 CombatSkillData Resource")

	var previews: Array = component.GetSkillPreviews()
	assert_eq(previews.size(), 1, "技能预览应过滤 VisibleInPreview=false 条目")
	if previews.is_empty():
		return
	var preview: RefCounted = previews[0]
	assert_eq(preview.get_script().resource_path, MONSTER_SKILL_PREVIEW_SCRIPT.resource_path, "预览对象应来自 GDScript 值对象")
	assert_eq(preview.get("SkillId"), &"probe_skill", "预览应保留 SkillId")
	assert_eq(preview.get("DisplayName"), "探针技能", "预览应保留 CardName")
	assert_eq(preview.get("Description"), "技能说明", "预览应保留说明")
	assert_eq(preview.get("ElementId"), 4, "预览应保留元素枚举整数值")
	assert_eq(preview.get("TargetingTypeId"), 2, "预览应保留目标类型枚举整数值")

	var scene_text: String = FileAccess.get_file_as_string("res://scenes/monster_scenes/monster.tscn")
	assert_true(scene_text.contains("res://entities/components/monster_skill_component.gd"), "生产怪物场景应切换到 GDScript 技能组件")
	assert_true(not scene_text.contains("res://entities/components/MonsterSkillComponent.cs"), "生产怪物场景不应继续引用技能组件 C# 脚本")


## 验证当前地图背景解析器优先使用 current_scene，并保留视觉属性与稳定名称。
func test_current_map_background_resolver_contract() -> void:
	var map_system := Node.new()
	var map_instantiator := FakeBackgroundMapInstantiator.new()
	map_instantiator.name = "MapInstantiator"
	map_system.add_child(map_instantiator)

	var first_room := Node2D.new()
	var first_background := Sprite2D.new()
	first_background.name = "Background"
	first_background.modulate = Color.RED
	first_room.add_child(first_background)
	map_instantiator.add_child(first_room)

	var current_room := Node2D.new()
	var current_background := Sprite2D.new()
	current_background.name = "Background"
	current_background.modulate = Color.GREEN
	current_background.self_modulate = Color(0.8, 0.8, 0.8, 1.0)
	current_room.add_child(current_background)
	map_instantiator.add_child(current_room)
	map_instantiator.current_scene = current_room

	var resolver = CURRENT_MAP_BACKGROUND_RESOLVER_SCRIPT.new()
	var duplicated: Sprite2D = resolver.DuplicateCurrentBackground(map_system)
	assert_true(duplicated != null, "背景解析器应复制当前房间的 Background")
	if duplicated == null:
		map_system.free()
		return
	assert_eq(duplicated.name, "MapBackground", "复制背景应使用战斗场景稳定名称")
	assert_eq(duplicated.modulate, Color.GREEN, "复制背景必须来自 current_scene，而不是缓存首个房间")
	assert_eq(duplicated.self_modulate, Color(0.8, 0.8, 0.8, 1.0), "复制背景应原样保留源背景的 self_modulate")
	duplicated.free()
	map_system.free()
	assert_eq(resolver.get_script().resource_path, CURRENT_MAP_BACKGROUND_RESOLVER_SCRIPT.resource_path, "解析器实例应来自 GDScript 并行实现")

	## C# 源文对照：C# 退役后 read() 返回空串，整块按条件收起而不是假通过。
	var presenter_source := CS_OPTIONAL.read("res://core/gameflow/WorldCombatScenePresenter.cs")
	if not presenter_source.is_empty():
		assert_true(presenter_source.contains("res://core/gameflow/current_map_background_resolver.gd"), "生产 Presenter 必须加载 GDScript 背景解析器。")
		assert_true(presenter_source.contains('resolverScript.Call("new")'), "C# Presenter 必须通过 Script 动态工厂创建 GDScript Resolver。")
		assert_true(presenter_source.contains('resolver.Call("DuplicateCurrentBackground", mapSystem)'), "生产调用必须使用稳定方法协议。")
		assert_false(presenter_source.contains("CurrentMapBackgroundResolver.DuplicateCurrentBackground"), "生产 Presenter 不得继续静态调用旧 C# Resolver。")


## 验证掉落条目迁移后的默认字段和代表性怪物资产嵌套资源引用。
func test_loot_drop_assets_use_gdscript() -> void:
	var drop: Resource = LOOT_DROP_SCRIPT.new()
	assert_eq(drop.get("Item"), null, "新建掉落条目的物品默认应为空。")
	assert_true(is_equal_approx(float(drop.get("DropChance")), 100.0), "掉落概率默认应为 100。")
	assert_eq(drop.get("MinAmount"), 1, "最小掉落数量默认应为 1。")
	assert_eq(drop.get("MaxAmount"), 1, "最大掉落数量默认应为 1。")

	for asset_path: String in LOOT_DROP_ASSETS:
		var monster: Resource = load(asset_path)
		assert_true(monster != null, "%s 必须能够加载掉落表。" % asset_path)
		if monster == null:
			continue
		var loot_table: Resource = monster.get("LootTable")
		assert_true(loot_table != null, "%s 必须保留 LootTable。" % asset_path)
		if loot_table == null:
			continue
		assert_eq(
			loot_table.get_script().resource_path,
			"res://resources/loot/loot_table.gd",
			"%s 的掉落表必须使用生产 GDScript Resource。" % asset_path
		)
		var drops: Array = loot_table.get("Drops")
		assert_true(drops != null, "%s 的 LootTable 必须保留 Drops 数组。" % asset_path)
		for entry: Resource in drops:
			assert_eq(
				entry.get_script().resource_path,
				"res://resources/loot/loot_drop.gd",
				"%s 的掉落条目必须使用 GDScript Resource。" % asset_path
			)


## 验证生产掉落表的默认值、GDScript 物品堆边界、产量修正和无效输入过滤。
func test_loot_table_production_roll_contract() -> void:
	## 新建的生产掉落表。
	var table: Resource = LOOT_TABLE_SCRIPT.new()
	assert_eq(table.get("Drops").size(), 0, "新建掉落表的 Drops 默认应为空数组。")
	# 编辑器工具态会把部分 .tres 降为基础 Resource；直接实例化脚本才能验证真实强类型调用边界。
	# 迁移期优先用旧 C# 垫片，C# 退役后自动换成等价的生产 GDScript ItemData。
	var item: Resource = CS_OPTIONAL.script_or(LEGACY_ITEM_DATA_CS_PATH, ITEM_DATA_SCRIPT_PATH).new() as Resource
	item.set("CardId", &"loot_table_contract_item")
	item.set("CardName", "掉落表契约物品")
	## 固定数量且必定命中的掉落条目。
	var guaranteed: Resource = LOOT_DROP_SCRIPT.new()
	guaranteed.set("Item", item)
	guaranteed.set("DropChance", 100.0)
	guaranteed.set("MinAmount", 2)
	guaranteed.set("MaxAmount", 2)
	## 显式构造 Resource 类型数组，保持导出字段类型稳定。
	var guaranteed_drops: Array[Resource] = [guaranteed, null]
	table.set("Drops", guaranteed_drops)
	## 应用额外产量后的掉落结果。
	var generated: Array = table.call("RollLoot", 3)
	assert_eq(generated.size(), 1, "100% 条目必须生成一个物品堆叠，并忽略空条目。")
	assert_eq(generated[0].get("Item"), item, "生成堆叠必须保留原物品 Resource 身份。")
	assert_eq(generated[0].get("Amount"), 5, "最终数量必须等于固定基础数量加额外产量。")
	assert_eq(
		generated[0].get_script().resource_path,
		"res://resources/item/item_stack.gd",
		"生产掉落表必须生成 GDScript ItemStack。"
	)

	## 负产量抵消基础数量后的结果。
	var filtered: Array = table.call("RollLoot", -2)
	assert_true(filtered.is_empty(), "最终数量不大于零时不得生成物品堆叠。")
	guaranteed.set("DropChance", -1.0)
	## 不可能命中的概率结果。
	var missed: Array = table.call("RollLoot", 0)
	assert_true(missed.is_empty(), "随机值高于掉落概率时不得生成物品堆叠。")
	guaranteed.set("DropChance", 100.0)
	guaranteed.set("Item", null)
	## 缺少物品引用的结果。
	var invalid: Array = table.call("RollLoot", 0)
	assert_true(invalid.is_empty(), "缺少 Item 的条目必须被忽略。")

	var generator_source: String = FileAccess.get_file_as_string("res://scripts/generated/create_terrain_profiles.gd")
	assert_true(
		generator_source.contains("res://resources/loot/loot_table.gd"),
		"地形 Profile 生成脚本必须写入生产 GDScript LootTable。"
	)
	assert_false(
		generator_source.contains("res://resources/loot/LootTable.cs"),
		"地形 Profile 生成脚本不得重新写回旧 C# LootTable。"
	)


## 验证棋盘可按同一稳定属性协议接收生产 GDScript 与旧 C# ItemStack。
## 返回值：无。
func test_board_loot_stack_cross_language_contract() -> void:
	## 两种 ItemStack 共同保存的物品 Resource（迁移期优先旧 C# 垫片，C# 退役后换等价 GDScript）。
	var item: Resource = CS_OPTIONAL.script_or(LEGACY_ITEM_DATA_CS_PATH, ITEM_DATA_SCRIPT_PATH).new() as Resource
	item.set("CardName", "棋盘掉落契约物品")

	## 生产 GDScript 物品堆叠。
	var gdscript_stack: RefCounted = ITEM_STACK_SCRIPT.new() as RefCounted
	gdscript_stack.call("SetItem", item, 3)
	## 兼容物品堆叠：迁移期是旧 C# 垫片，C# 退役后是等价的生产 GDScript 堆叠。
	var legacy_stack: RefCounted = CS_OPTIONAL.script_or(LEGACY_ITEM_STACK_CS_PATH, PRODUCTION_ITEM_STACK_GD_PATH).new() as RefCounted
	legacy_stack.call("SetItem", item, 2)
	assert_true(gdscript_stack.get("Item") == item, "GDScript 堆叠必须保留原物品 Resource 身份。")
	assert_eq(int(gdscript_stack.get("Amount")), 3, "GDScript 堆叠必须公开 Amount。")
	assert_false(bool(gdscript_stack.get("IsEmpty")), "GDScript 堆叠必须公开 IsEmpty。")
	assert_true(legacy_stack.get("Item") == item, "旧 C# 堆叠必须保留原物品 Resource 身份。")
	assert_eq(int(legacy_stack.get("Amount")), 2, "旧 C# 堆叠必须继续公开 Amount。")
	assert_false(bool(legacy_stack.get("IsEmpty")), "旧 C# 堆叠必须继续公开 IsEmpty。")

	## 棋盘生产链的源码协议；实际场景实例化由 Main 运行时冒烟覆盖。
	## C# 源文对照：C# 退役后 read() 返回空串，相关断言按条件收起而不是假通过。
	var state_source := CS_OPTIONAL.read("res://core/board/BoardCardState.cs")
	var controller_source := FileAccess.get_file_as_string("res://core/board/board_controller.gd")
	var controller_shim_source := CS_OPTIONAL.read("res://core/board/BoardController.cs")
	var executor_source := CS_OPTIONAL.read("res://core/gameflow/TerrainInteractionExecutor.cs")
	var player_source := CS_OPTIONAL.read("res://entities/Player.cs")
	var spawn_op_source := CS_OPTIONAL.read("res://resources/interaction/operations/SpawnLootOp.cs")
	var state_gd: Script = load("res://core/board/board_card_state.gd")
	assert_true(state_gd != null, "棋盘卡状态必须存在等价 GDScript 实现。")
	assert_true(controller_source.contains('res://core/board/board_card_state.gd'), "BoardController 必须通过 GDScript 状态脚本创建卡牌状态。")
	assert_false(controller_source.contains("BoardCardState"), "生产棋盘控制器不得引用 C# BoardCardState 具体类型。")
	if not controller_shim_source.is_empty():
		assert_true(
			controller_shim_source.contains(
				"public Node2D SpawnTerrainCard(RefCounted terrainInstance, Vector2 globalPosition)"
			),
			"旧 C# 棋盘控制器兼容垫片必须保留跨语言地形入口。"
		)
	if state_gd != null:
		var state := state_gd.call("new") as RefCounted
		assert_true(state.call("InitializeLoot", gdscript_stack), "GDScript 状态必须接受生产 ItemStack。")
		assert_true(state.call("IsLoot"), "掉落状态必须保留 loot 类型。")
		assert_true(state.call("GetCardData") == item, "掉落状态必须保留原物品 Resource 身份。")
		assert_eq(int(state.call("GetStackAmount")), 3, "掉落状态必须保留数量。")
		assert_true(state.call("CanShowAmount"), "数量大于 1 时必须显示数量标签。")
	assert_true(controller_source.contains("func SpawnLootCards(stacks: Array"), "棋盘批量入口必须接收非泛型数组。")
	if not state_source.is_empty():
		assert_true(state_source.contains("public RefCounted LootStack"), "棋盘状态必须以 RefCounted 保存跨语言堆叠。")
	if not executor_source.is_empty():
		assert_true(executor_source.contains("ItemStackProtocol.TryRead(stack"), "地形执行器必须过滤跨语言堆叠协议。")
	if not player_source.is_empty():
		assert_true(player_source.contains("TryAddItemToInventory(RefCounted stack)"), "玩家拾取入口必须接收跨语言堆叠。")
	if not spawn_op_source.is_empty():
		assert_true(spawn_op_source.contains("public SpawnLootOp(Array<ItemStack> drops)"), "旧 C# 交互数组构造入口必须继续保留。")
		assert_true(spawn_op_source.contains("public SpawnLootOp(Array drops)"), "GDScript 非泛型数组构造入口必须存在。")


## 验证基础物品 GDScript Resource 与旧 C# 数据类保持字段和显示回退契约。
func test_item_data_gdscript_contract_defaults() -> void:
	var base_script: Script = load(BASE_CARD_DATA_SCRIPT_PATH)
	var item_script: Script = load(ITEM_DATA_SCRIPT_PATH)
	assert_true(base_script != null, "基础卡牌 GDScript Resource 必须能够加载。")
	assert_true(item_script != null, "物品 GDScript Resource 必须能够加载。")
	if base_script == null or item_script == null:
		return

	var base: Resource = base_script.new()
	assert_eq(base.get("CardId"), &"", "基础卡牌 CardId 默认值必须为空。")
	assert_eq(base.get("CardName"), "", "基础卡牌 CardName 默认值必须为空。")
	assert_eq(base.get("Description"), "", "基础卡牌 Description 默认值必须为空。")
	assert_eq(base.get("DisplayName"), "", "基础卡牌 DisplayName 必须回退到 CardName。")
	assert_eq(base.get("DisplayDescription"), "", "基础卡牌 DisplayDescription 必须回退到 Description。")
	assert_eq(base.get("DisplayIcon"), null, "基础卡牌 DisplayIcon 默认必须为空。")
	base.set("CardId", &"gd_item_probe")
	base.set("CardName", "GDScript 物品")
	base.set("Description", "基础契约测试")
	assert_eq(base.get("DisplayName"), "GDScript 物品", "DisplayName 必须反映 CardName。")
	assert_eq(base.get("DisplayDescription"), "基础契约测试", "DisplayDescription 必须反映 Description。")

	var item: Resource = item_script.new()
	assert_eq(item.get("MaxStackSize"), 99, "ItemData MaxStackSize 默认值必须保持为 99。")
	assert_eq(item.get("ItemTags").size(), 0, "ItemData ItemTags 默认必须为空数组。")
	assert_eq(item.get("BuyPrice"), 0, "ItemData BuyPrice 默认值必须保持为 0。")
	assert_eq(item.get("SellPrice"), 0, "ItemData SellPrice 默认值必须保持为 0。")
	assert_eq(item.get("ActualMaxStackSize"), 99, "ItemData ActualMaxStackSize 必须回退到 MaxStackSize。")
	item.set("MaxStackSize", 16)
	assert_eq(item.get("ActualMaxStackSize"), 16, "ItemData ActualMaxStackSize 必须跟随 MaxStackSize。")
	assert_eq(item.get_script().resource_path, ITEM_DATA_SCRIPT_PATH, "实例脚本路径必须指向 GDScript ItemData。")


## 验证并行 SkillCardData 保持显示回退、单张堆叠和 C# 战斗技能委托协议。
func test_skill_card_data_gdscript_dynamic_contract() -> void:
	var skill_card_script: Script = load(SKILL_CARD_DATA_SCRIPT_PATH)
	assert_true(skill_card_script != null, "SkillCardData GDScript 必须能够加载。")
	if skill_card_script == null:
		return

	var card := skill_card_script.new() as Resource
	assert_true(card != null, "SkillCardData GDScript 必须能够实例化。")
	if card == null:
		return
	assert_eq(card.get("Skill"), null, "Skill 默认必须为空。")
	assert_eq(int(card.get("cost")), 10, "技能卡默认费用必须保持 10。")
	assert_eq((card.get("CardTags") as Array).size(), 0, "技能卡标签默认必须为空数组。")
	assert_eq(int(card.get("ActualMaxStackSize")), 1, "技能卡实际堆叠上限必须保持 1。")
	assert_eq(int(card.get("MaxStackSize")), 99, "继承的原始 MaxStackSize 默认值必须保持 99。")

	var fallback_icon := GradientTexture1D.new()
	var direct_icon := GradientTexture1D.new()
	var skill := FakeCombatSkill.new()
	skill.CardIcon = fallback_icon
	card.set("Skill", skill)
	assert_eq(card.get("DisplayName"), "协议技能", "空卡名必须回退到 CombatSkillData 导出的 CardName。")
	assert_eq(card.get("DisplayDescription"), "协议技能描述", "空描述必须回退到 CombatSkillData 导出的 Description。")
	assert_true(card.get("DisplayIcon") == fallback_icon, "空图标必须回退到 CombatSkillData 导出的 CardIcon。")
	assert_eq(int(card.get("Element")), 5, "技能卡元素必须读取实际 CombatSkillData。")
	card.set("CardName", "独立卡名")
	card.set("Description", "独立描述")
	card.set("CardIcon", direct_icon)
	var card_tags: Array[String] = ["单体伤害", " ", "火属性"]
	card.set("CardTags", card_tags)
	assert_eq(card.get("DisplayName"), "独立卡名", "卡牌独立名称必须优先于技能名称。")
	assert_eq(card.get("DisplayDescription"), "独立描述", "卡牌独立描述必须优先于技能描述。")
	assert_true(card.get("DisplayIcon") == direct_icon, "卡牌独立图标必须优先于技能图标。")
	assert_eq(card.get("DisplayTag"), "单体伤害\n火属性", "空白标签必须过滤，其余标签按换行连接。")
	var context := RefCounted.new()
	card.call("ApplyEffect", context)
	assert_eq(skill.execute_count, 1, "ApplyEffect 必须精确委托一次 CombatSkillData.Execute。")
	assert_true(skill.last_context == context, "ApplyEffect 必须保持原执行上下文身份。")

	var legacy_fallback_icon := GradientTexture1D.new()
	## 兼容战斗技能：迁移期是旧 C# 垫片，C# 退役后是等价的生产 GDScript 技能。
	var legacy_skill := CS_OPTIONAL.script_or(LEGACY_COMBAT_SKILL_CS_PATH, "res://core/combat/skills/combat_skill_data.gd").new() as Resource
	assert_true(legacy_skill != null and legacy_skill.has_method("Execute"), "并行技能卡必须继续接受 C# CombatSkillData。")
	legacy_skill.set("CardName", "C# 协议技能")
	legacy_skill.set("Description", "C# 协议技能描述")
	legacy_skill.set("CardIcon", legacy_fallback_icon)
	card.set("CardName", "")
	card.set("Description", "")
	card.set("CardIcon", null)
	card.set("Skill", legacy_skill)
	assert_true(card.get("Skill") == legacy_skill, "C# CombatSkillData Resource 身份不得被复制或包装。")
	assert_eq(card.get("DisplayName"), "C# 协议技能", "C# 技能回退必须读取导出的 CardName，而不是不可动态访问的计算属性。")
	assert_eq(card.get("DisplayDescription"), "C# 协议技能描述", "C# 技能回退必须读取导出的 Description。")
	assert_true(card.get("DisplayIcon") == legacy_fallback_icon, "C# 技能回退必须读取导出的 CardIcon。")


## 验证全部普通生产物品切换到 GDScript，并保持稳定字段与 CardId 唯一性。
func test_production_plain_item_assets_use_gdscript_item_data() -> void:
	var item_paths: Array[String] = _collect_production_plain_item_paths("res://items")
	assert_eq(item_paths.size(), PRODUCTION_PLAIN_ITEM_COUNT, "普通生产物品资产数量必须保持为 103。")
	var seen_card_ids: Dictionary = {}
	for path: String in item_paths:
		var source: String = FileAccess.get_file_as_string(path)
		assert_true(source.contains('uid="uid://dypewmj21sddd" path="res://resources/item/item_data.gd"'), "%s 必须引用 GDScript ItemData UID。" % path)
		assert_false(source.contains('script_class="ItemData"'), "%s 不得保留 C# 全局类型标头。" % path)
		assert_true(source.contains('metadata/_custom_type_script = "uid://dypewmj21sddd"'), "%s 必须同步自定义脚本元数据。" % path)

		var item := ResourceLoader.load(path, "Resource", ResourceLoader.CACHE_MODE_REPLACE) as Resource
		assert_true(item != null, "%s 必须能够加载。" % path)
		if item == null:
			continue
		assert_eq(item.get_script().resource_path, ITEM_DATA_SCRIPT_PATH, "%s 必须使用生产 ItemData GDScript。" % path)
		assert_true(bool(ITEM_DATA_COMPAT_SCRIPT.call("is_item_resource", item)), "%s 必须满足稳定物品字段协议。" % path)
		var card_id: StringName = ITEM_DATA_COMPAT_SCRIPT.call("get_card_id", item, &"")
		assert_false(card_id.is_empty(), "%s 的 CardId 不得丢失。" % path)
		assert_false(seen_card_ids.has(card_id), "普通生产物品 CardId 必须唯一：%s。" % card_id)
		seen_card_ids[card_id] = path

	var wood := ResourceLoader.load("res://items/element/wood.tres", "Resource", ResourceLoader.CACHE_MODE_REPLACE) as Resource
	assert_true(wood != null, "代表性元素物品 wood.tres 必须能够加载。")
	if wood != null:
		assert_eq(wood.get("CardId"), &"wood", "木元素 CardId 必须保持不变。")
		assert_eq(int(wood.get("MaxStackSize")), 5, "木元素堆叠上限必须保持 5。")
		assert_eq(int(wood.get("BuyPrice")), 150, "木元素买价必须保持 150。")
		assert_eq(int(wood.get("SellPrice")), 75, "木元素卖价必须保持 75。")
		assert_eq((wood.get("ItemTags") as Array).size(), 2, "木元素的两个标签不得丢失。")


## 验证五张资源卡切换到 GDScript Resource，并保持原字段、图标和默认物品协议。
func test_resource_card_assets_use_gdscript_item_data() -> void:
	var expected: Dictionary = {
		"branch.tres": {"id": &"branch", "name": "树枝", "description": "树枝而已"},
		"charcoal.tres": {"id": &"charcoal", "name": "木炭", "description": "木炭，没有材质用雪的"},
		"stone.tres": {"id": &"stone", "name": "石头", "description": "小石子"},
		"torch.tres": {"id": &"torch", "name": "火把", "description": "火把罢了"},
		"axe.tres": {"id": &"StoneAxe", "name": "石斧", "description": "较垃圾的石斧"},
	}
	for path: String in RESOURCE_CARD_ASSET_PATHS:
		var source: String = FileAccess.get_file_as_string(path)
		var filename: String = path.get_file()
		assert_true(source.contains('path="res://resources/item/card/resource_card_data.gd"'), "%s 必须引用 GDScript ResourceCardData。" % path)
		assert_false(source.contains("ResourceCardData.cs"), "%s 不得保留 ResourceCardData.cs 路径。" % path)
		assert_false(source.contains('script_class="ResourceCardData"'), "%s 不得保留旧 C# 脚本类标头。" % path)
		assert_false(source.contains("metadata/_custom_type_script"), "%s 不得保留旧 C# 自定义脚本元数据。" % path)

		var card := ResourceLoader.load(path, "Resource", ResourceLoader.CACHE_MODE_REPLACE) as Resource
		assert_true(card != null, "%s 必须能够加载。" % path)
		if card == null:
			continue
		assert_eq(card.get_script().resource_path, RESOURCE_CARD_DATA_SCRIPT_PATH, "%s 必须使用 GDScript ResourceCardData。" % path)
		assert_eq(card.get("CardId"), expected[filename]["id"], "%s 的 CardId 不得改变。" % path)
		assert_eq(card.get("CardName"), expected[filename]["name"], "%s 的 CardName 不得改变。" % path)
		assert_eq(card.get("Description"), expected[filename]["description"], "%s 的 Description 不得改变。" % path)
		assert_eq(int(card.get("MaxStackSize")), 99, "%s 必须继承 ItemData 的默认堆叠上限。" % path)
		assert_eq(int(card.get("BuyPrice")), 0, "%s 必须保持未定价默认值。" % path)
		assert_eq(int(card.get("SellPrice")), 0, "%s 必须保持未定价默认值。" % path)
		assert_true(bool(ITEM_DATA_COMPAT_SCRIPT.call("is_item_resource", card)), "%s 必须满足通用物品字段协议。" % path)


## 递归收集明确引用生产 GDScript ItemData 的普通物品资产。
## 参数 dir_path：需要扫描的 res:// 目录。
## 返回值：按路径排序的普通物品 .tres 列表。
func _collect_production_plain_item_paths(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full_path: String = dir_path.path_join(entry)
			if dir.current_is_dir():
				result.append_array(_collect_production_plain_item_paths(full_path))
			elif entry.ends_with(".tres"):
				var source: String = FileAccess.get_file_as_string(full_path)
				if source.contains('path="res://resources/item/item_data.gd"'):
					result.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result


## 验证兼容工具同时读取 GDScript 物品和旧 C# 物品，并保留对象身份比较语义。
func test_item_data_compat_bridge_accepts_legacy_and_gdscript_resources() -> void:
	var gd_item: Resource = load(ITEM_DATA_SCRIPT_PATH).new()
	gd_item.set("CardId", &"gd_bridge_item")
	gd_item.set("CardName", "GDScript Bridge Item")
	gd_item.set("Description", "GDScript Bridge Description")
	gd_item.set("MaxStackSize", 16)
	var gd_tags: Array[StringName] = [&"material", &"bridge"]
	gd_item.set("ItemTags", gd_tags)
	gd_item.set("BuyPrice", 101)
	gd_item.set("SellPrice", 0)

	assert_true(bool(ITEM_DATA_COMPAT_SCRIPT.call("is_item_resource", gd_item)), "GDScript ItemData 必须通过兼容字段检查。")
	assert_eq(ITEM_DATA_COMPAT_SCRIPT.call("get_card_id", gd_item), &"gd_bridge_item", "兼容工具必须读取 GDScript CardId。")
	assert_eq(ITEM_DATA_COMPAT_SCRIPT.call("get_display_name", gd_item), "GDScript Bridge Item", "兼容工具必须读取 GDScript 显示名称。")
	assert_eq(ITEM_DATA_COMPAT_SCRIPT.call("get_display_description", gd_item), "GDScript Bridge Description", "兼容工具必须读取 GDScript 描述。")
	assert_eq(ITEM_DATA_COMPAT_SCRIPT.call("get_max_stack_size", gd_item), 16, "兼容工具必须读取 GDScript 堆叠上限。")
	var bridge_tags: Array = ITEM_DATA_COMPAT_SCRIPT.call("get_item_tags", gd_item)
	assert_eq(bridge_tags.size(), 2, "兼容工具必须保留 GDScript 标签数量。")
	if bridge_tags.size() == 2:
		assert_eq(StringName(bridge_tags[0]), &"material", "兼容工具必须保留第一个 GDScript 标签。")
		assert_eq(StringName(bridge_tags[1]), &"bridge", "兼容工具必须保留第二个 GDScript 标签。")
	assert_eq(ITEM_DATA_COMPAT_SCRIPT.call("get_resolved_sell_price", gd_item), 50, "兼容工具必须按买价折半回退卖价。")
	assert_true(bool(ITEM_DATA_COMPAT_SCRIPT.call("same_item", gd_item, gd_item)), "同一 GDScript 资源必须被识别为同一物品。")
	assert_false(bool(ITEM_DATA_COMPAT_SCRIPT.call("same_item", gd_item, load(ITEM_DATA_SCRIPT_PATH).new())), "不同 GDScript 资源实例不得合并堆叠。")

	## 兼容物品：迁移期是旧 C# 垫片，C# 退役后是等价的生产 GDScript ItemData。
	var legacy_item := CS_OPTIONAL.script_or(LEGACY_ITEM_DATA_CS_PATH, ITEM_DATA_SCRIPT_PATH).new() as Resource
	legacy_item.set("CardId", &"legacy_item_compat")
	legacy_item.set("CardName", "旧 C# 兼容物品")
	legacy_item.set("Description", "保留类型输入")
	legacy_item.set("MaxStackSize", 8)
	var legacy_item_tags: Array[StringName] = [&"legacy"]
	legacy_item.set("ItemTags", legacy_item_tags)
	legacy_item.set("BuyPrice", 120)
	legacy_item.set("SellPrice", 60)
	assert_true(legacy_item != null, "保留的 C# ItemData 必须能够实例化，才能作为兼容输入。")
	if legacy_item == null:
		return
	assert_true(bool(ITEM_DATA_COMPAT_SCRIPT.call("is_item_resource", legacy_item)), "旧 C# ItemData 必须通过兼容字段检查。")
	assert_eq(ITEM_DATA_COMPAT_SCRIPT.call("get_display_name", legacy_item), String(legacy_item.get("CardName")), "兼容工具必须读取旧 C# 显示名称回退。")
	assert_eq(ITEM_DATA_COMPAT_SCRIPT.call("get_display_description", legacy_item), String(legacy_item.get("Description")), "兼容工具必须读取旧 C# 描述回退。")
	assert_eq(ITEM_DATA_COMPAT_SCRIPT.call("get_max_stack_size", legacy_item), int(legacy_item.get("MaxStackSize")), "兼容工具必须读取旧 C# 堆叠上限。")
	var legacy_tags: Array = ITEM_DATA_COMPAT_SCRIPT.call("get_item_tags", legacy_item)
	assert_eq(legacy_tags.size(), 1, "兼容工具必须读取旧 C# 标签数组。")
	if legacy_tags.size() == 1:
		assert_eq(StringName(legacy_tags[0]), StringName(legacy_item.get("ItemTags")[0]), "兼容工具必须保留旧 C# 标签值。")
	assert_eq(ITEM_DATA_COMPAT_SCRIPT.call("get_buy_price", legacy_item), int(legacy_item.get("BuyPrice")), "兼容工具必须读取旧 C# 买价。")
	assert_eq(ITEM_DATA_COMPAT_SCRIPT.call("get_sell_price", legacy_item), int(legacy_item.get("SellPrice")), "兼容工具必须读取旧 C# 卖价。")
	assert_eq(ITEM_DATA_COMPAT_SCRIPT.call("get_resolved_sell_price", legacy_item), int(legacy_item.get("SellPrice")), "兼容工具必须保留旧 C# 显式卖价。")
	assert_true(bool(ITEM_DATA_COMPAT_SCRIPT.call("same_item", legacy_item, legacy_item)), "同一旧 C# 资源必须保持引用相等。")


## 验证天气资源保留原字段名称和默认值。
func test_weather_data_defaults_and_dictionary_shape() -> void:
	var weather: Resource = WEATHER_DATA_SCRIPT.new()
	assert_eq(weather.get("WeatherName"), "晴天", "天气名称默认值必须保持为晴天。")
	assert_true(weather.get("ElementModifiers").is_empty(), "元素修正默认应为空字典。")
	assert_true(
		is_equal_approx(float(weather.get("CropGrowthSpeedMultiplier")), 1.0),
		"作物生长倍率默认应为 1.0。"
	)
	assert_false(bool(weather.get("CanExtinguishCampfire")), "默认天气不应熄灭篝火。")

	weather.set("ElementModifiers", {1: 1.5, 4: 0.5})
	var modifiers: Dictionary = weather.get("ElementModifiers")
	assert_true(is_equal_approx(float(modifiers[1]), 1.5), "元素修正应保留整数键 1 的倍率。")
	assert_true(is_equal_approx(float(modifiers[4]), 0.5), "元素修正应保留整数键 4 的倍率。")
	assert_eq(
		weather.get_script().resource_path,
		"res://resources/weather/weather_data.gd",
		"天气资源必须由 GDScript 脚本提供。"
	)


## 验证 GDScript 驻守状态保持无向边查询和清理语义。
func test_passage_guard_state_keeps_undirected_edges() -> void:
	var state: RefCounted = PASSAGE_GUARD_STATE_SCRIPT.new()
	var first := Vector2i(1, 1)
	var second := Vector2i(1, 2)
	state.call("AddGuard", first, second)
	assert_true(bool(state.call("IsGuarded", first, second)), "驻守边应支持原方向查询。")
	assert_true(bool(state.call("IsGuarded", second, first)), "驻守边应支持反方向查询。")
	assert_eq(int(state.get("Count")), 1, "同一无向边反向查询不应产生重复驻守记录。")
	state.call("ClearGuard", second, first)
	assert_false(bool(state.call("IsGuarded", first, second)), "清理驻守边后正向查询应返回 false。")
	state.call("AddGuard", first, second)
	state.call("ClearAll")
	assert_eq(int(state.get("Count")), 0, "ClearAll 应清空全部驻守边。")


## 验证驻守概率服务保留加法、乘法和标签过滤顺序。
func test_passage_guard_probability_provider_keeps_modifier_order() -> void:
	var settings: Resource = PASSAGE_GUARD_SETTINGS_SCRIPT.new()
	settings.set("BaseGuardChance", 0.3)
	var active_modifier: Resource = MODIFIER_SCRIPT.new()
	active_modifier.set("RequiredTag", &"quiet_night")
	active_modifier.set("AdditiveChance", 0.1)
	active_modifier.set("Multiplier", 1.0)
	var multiplier_modifier: Resource = MODIFIER_SCRIPT.new()
	multiplier_modifier.set("RequiredTag", &"guard_discount")
	multiplier_modifier.set("Multiplier", 0.5)
	var inactive_modifier: Resource = MODIFIER_SCRIPT.new()
	inactive_modifier.set("RequiredTag", &"inactive")
	inactive_modifier.set("AdditiveChance", 0.6)
	inactive_modifier.set("Multiplier", 10.0)
	settings.get("ProbabilityModifiers").append(active_modifier)
	settings.get("ProbabilityModifiers").append(multiplier_modifier)
	settings.get("ProbabilityModifiers").append(inactive_modifier)

	var tags := FakeTags.new()
	tags.add_tag(&"quiet_night")
	tags.add_tag(&"guard_discount")
	var provider: RefCounted = PASSAGE_GUARD_PROVIDER_SCRIPT.new()
	var final_chance := float(provider.call("Calculate", settings, tags))

	assert_true(
		is_equal_approx(final_chance, 0.2),
		"驻守概率应先合并有效加法，再乘以有效倍率并忽略未拥有标签；实际值：%s。" % final_chance
	)


## 验证天气 Autoload 的字段、信号和切换方法保持旧管理器语义。
func test_weather_manager_autoload_boundary() -> void:
	var configured_path := str(ProjectSettings.get_setting("autoload/WeatherManager", ""))
	assert_eq(
		configured_path,
		"*res://core/autoloads/weather_manager.gd",
		"WeatherManager Autoload 必须切换到 GDScript 脚本。"
	)

	var manager: Node = WEATHER_MANAGER_SCRIPT.new()
	var weather: Resource = WEATHER_DATA_SCRIPT.new()
	var emitted: Array[Resource] = []
	manager.connect(&"WeatherChanged", func(new_weather: Resource) -> void:
		emitted.append(new_weather)
	)
	manager.call("ChangeWeather", weather)
	assert_true(manager.get("CurrentWeather") == weather, "ChangeWeather 应保存新的天气资源。")
	assert_eq(emitted.size(), 1, "ChangeWeather 应只广播一次天气变更信号。")
	if not emitted.is_empty():
		assert_true(emitted[0] == weather, "天气变更信号应携带新的天气资源。")
	manager.free()


## 验证商店目录的默认值、真实资产脚本和商品顺序均已保留。
func test_shop_catalog_resource_migrated() -> void:
	var empty_catalog: Resource = SHOP_CATALOG_SCRIPT.new()
	assert_eq(empty_catalog.get("Goods").size(), 0, "新建商店目录的 Goods 默认应为空数组。")
	assert_false(bool(empty_catalog.get("AlsoIncludeEveryPricedItem")), "目录默认不应自动上架全部定价物品。")
	assert_eq(empty_catalog.get("DefaultBuyPrice"), 100, "目录兜底买价默认应保持为 100。")
	var explicit_item := Resource.new()
	empty_catalog.get("Goods").append(explicit_item)
	assert_true(bool(empty_catalog.call("ContainsExplicitly", explicit_item)), "目录应识别显式上架资源。")
	assert_false(bool(empty_catalog.call("ContainsExplicitly", Resource.new())), "目录不应误认未上架资源。")

	var catalog: Resource = load("res://resources/shop/shop_catalog.tres")
	assert_true(catalog != null, "默认商店目录必须能够加载。")
	if catalog == null:
		return

	assert_eq(
		catalog.get_script().resource_path,
		"res://resources/shop/shop_catalog.gd",
		"默认商店目录必须使用 GDScript Resource。"
	)
	var goods: Array = catalog.get("Goods")
	assert_eq(goods.size(), 89, "默认商品数量必须保持为 89。")
	if goods.is_empty():
		return
	assert_eq(goods[0].resource_path, "res://items/tool/Ax.tres", "商品首项顺序必须保持为 Ax。")
	assert_eq(
		goods[goods.size() - 1].resource_path,
		"res://resources/skill_cards/earth_magic_houtufenglingmai.tres",
		"商品末项顺序必须保持为土系技能卡。"
	)


## 验证装备 Resource 保留槽位、套装、属性加成和标签字段的序列化契约。
func test_equipment_data_preserves_serialized_fields() -> void:
	var equipment: Resource = EQUIPMENT_DATA_SCRIPT.new()
	equipment.set("CardId", &"test_equipment")
	equipment.set("CardName", "测试装备")
	var equipment_slots: Array[int] = [4, 12]
	equipment.set("ValidSlots", equipment_slots)
	equipment.set("SetType", 2)
	equipment.set("AttributeBonuses", {0: Vector2i(10, 20), 4: Vector2i(-2, -1)})
	var equipment_tags: Array[StringName] = [&"test_tag"]
	equipment.set("GrantedTags", equipment_tags)

	assert_eq(equipment.get("MaxStackSize"), 1, "装备默认最大堆叠必须保持为 1。")
	var valid_slots: Array = equipment.get("ValidSlots")
	assert_eq(valid_slots.size(), 2, "装备槽位数量必须保留。")
	if valid_slots.size() == 2:
		assert_eq(int(valid_slots[0]), 4, "装备第一个槽位必须保留旧枚举整数值。")
		assert_eq(int(valid_slots[1]), 12, "装备第二个槽位必须保留旧枚举整数值。")
	assert_eq(equipment.get("SetType"), 2, "套装枚举值必须保持 Stone=2。")
	assert_eq(equipment.get("AttributeBonuses")[0], Vector2i(10, 20), "属性加成范围不得丢失。")
	var granted_tags: Array = equipment.get("GrantedTags")
	assert_eq(granted_tags.size(), 1, "装备标签数量必须保留。")
	if granted_tags.size() == 1:
		assert_eq(StringName(granted_tags[0]), &"test_tag", "装备标签值必须保留。")
	assert_true(bool(ITEM_DATA_COMPAT_SCRIPT.call("is_item_resource", equipment)), "装备 Resource 必须通过 ItemData 兼容字段检查。")


## 验证工具 Resource 保留采集标签、产量增量和时间减免字段。
func test_tool_data_preserves_gathering_fields() -> void:
	var tool: Resource = TOOL_DATA_SCRIPT.new()
	tool.set("CardId", &"test_tool")
	tool.set("CardName", "测试工具")
	var tool_slots: Array[int] = [5]
	tool.set("ValidSlots", tool_slots)
	tool.set("TargetGatheringTag", &"wood")
	tool.set("YieldGrowth", 2)
	tool.set("GatheringTimeReduction", 10)

	assert_eq(tool.get("MaxStackSize"), 1, "工具必须沿用装备的不可堆叠规则。")
	assert_eq(tool.get("TargetGatheringTag"), &"wood", "工具采集标签必须保留。")
	assert_eq(tool.get("YieldGrowth"), 2, "工具产量增量必须保留。")
	assert_eq(tool.get("GatheringTimeReduction"), 10, "工具时间减免必须保留。")
	assert_true(bool(ITEM_DATA_COMPAT_SCRIPT.call("is_item_resource", tool)), "工具 Resource 必须通过 ItemData 兼容字段检查。")


## 验证两张生产工具资产切换到 GDScript，并保持脚本、槽位和采集字段。
func test_production_tool_assets_use_gdscript() -> void:
	var expected: Dictionary = {
		"Ax.tres": {"slot": 5, "tag": &"wood", "id": &"Ax", "name": "斧头"},
		"Pickaxe.tres": {"slot": 6, "tag": &"earth", "id": &"Pickaxe", "name": "镐子"},
	}
	for path: String in PRODUCTION_TOOL_ASSET_PATHS:
		var source: String = FileAccess.get_file_as_string(path)
		assert_true(source.contains('uid="uid://d3ajy7b7py2kl" path="res://resources/item/tool/tool_data.gd"'), "%s 必须引用生产 GDScript ToolData。" % path)
		assert_false(source.contains("ToolData.cs"), "%s 不得保留旧 ToolData.cs 路径。" % path)
		assert_false(source.contains('script_class="ToolData"'), "%s 不得保留旧 C# 全局类型标头。" % path)
		assert_false(source.contains("metadata/_custom_type_script"), "%s 不得保留旧 C# 自定义脚本元数据。" % path)

		var tool := ResourceLoader.load(path, "Resource", ResourceLoader.CACHE_MODE_REPLACE) as Resource
		assert_true(tool != null, "%s 必须能够加载。" % path)
		if tool == null:
			continue
		var values: Dictionary = expected[path.get_file()]
		assert_eq(tool.get_script().resource_path, "res://resources/item/tool/tool_data.gd", "%s 必须使用生产 ToolData GDScript。" % path)
		assert_eq(tool.get("ValidSlots"), [values.slot], "%s 必须保留原装备槽位。" % path)
		assert_eq(tool.get("TargetGatheringTag"), values.tag, "%s 必须保留原采集标签。" % path)
		assert_eq(int(tool.get("YieldGrowth")), 0, "%s 必须保持默认额外产量 0。" % path)
		assert_eq(int(tool.get("GatheringTimeReduction")), 10, "%s 必须保留 10 点时间减免。" % path)
		assert_eq(tool.get("CardId"), values.id, "%s 必须保留 CardId。" % path)
		assert_eq(tool.get("CardName"), values.name, "%s 必须保留显示名称。" % path)
		assert_true(bool(ITEM_DATA_COMPAT_SCRIPT.call("is_item_resource", tool)), "%s 必须通过 ItemData 兼容字段检查。" % path)


## 验证套装配置保留阶级、属性、标签和套装枚举的序列化契约。
func test_equipment_set_resources_preserve_contract() -> void:
	var tier: Resource = SET_BONUS_TIER_SCRIPT.new()
	assert_eq(tier.get("RequiredPieces"), 0, "套装阶级的默认需求件数必须保持为 0。")
	assert_true(tier.get("AttributeBonuses").is_empty(), "套装阶级的默认属性加成必须为空。")
	assert_true(tier.get("GrantedTags").is_empty(), "套装阶级的默认标签必须为空。")

	tier.set("RequiredPieces", 2)
	tier.set("AttributeBonuses", {0: 5.5, 4: -1.25})
	var tier_tags: Array[StringName] = [&"set_bonus", &"wooden_set"]
	tier.set("GrantedTags", tier_tags)

	var set_data: Resource = EQUIPMENT_SET_DATA_SCRIPT.new()
	assert_eq(set_data.get("SetType"), 0, "套装数据默认类型必须保持 None=0。")
	assert_true(set_data.get("Tiers").is_empty(), "套装数据默认阶级列表必须为空。")
	set_data.set("SetType", 3)
	var tiers: Array[Resource] = [tier]
	set_data.set("Tiers", tiers)

	assert_eq(tier.get("RequiredPieces"), 2, "套装阶级需求件数必须保留。")
	assert_eq(tier.get("AttributeBonuses")[0], 5.5, "套装正向属性加成必须保留浮点值。")
	assert_eq(tier.get("AttributeBonuses")[4], -1.25, "套装负向属性加成必须保留浮点值。")
	assert_eq(tier.get("GrantedTags"), tier_tags, "套装阶级标签顺序和值必须保留。")
	assert_eq(set_data.get("SetType"), 3, "套装枚举值必须保持 Iron=3。")
	assert_eq(set_data.get("Tiers").size(), 1, "套装阶级数量必须保留。")
	assert_true(set_data.get("Tiers")[0] == tier, "套装数据必须保留原阶级 Resource 引用。")


## 验证装备兼容桥可无损读取 GDScript 与旧 C# ToolData。
func test_equipment_data_compat_reads_both_language_resources() -> void:
	var gd_tool: Resource = TOOL_DATA_SCRIPT.new()
	gd_tool.set("CardId", &"compat_tool")
	gd_tool.set("CardName", "兼容工具")
	var gd_slots: Array[int] = [5, 4]
	gd_tool.set("ValidSlots", gd_slots)
	gd_tool.set("SetType", 2)
	gd_tool.set("AttributeBonuses", {0: Vector2i(3, 7)})
	var gd_tags: Array[StringName] = [&"weapon", &"axe"]
	gd_tool.set("GrantedTags", gd_tags)
	gd_tool.set("TargetGatheringTag", &"wood")
	gd_tool.set("YieldGrowth", 3)
	gd_tool.set("GatheringTimeReduction", 12)

	assert_true(bool(EQUIPMENT_DATA_COMPAT_SCRIPT.call("is_equipment_resource", gd_tool)), "GDScript 工具必须被识别为装备。")
	assert_true(bool(EQUIPMENT_DATA_COMPAT_SCRIPT.call("is_tool_resource", gd_tool)), "GDScript 工具必须被识别为工具。")
	assert_eq(EQUIPMENT_DATA_COMPAT_SCRIPT.call("get_valid_slots", gd_tool), gd_slots, "GDScript 工具槽位必须保留顺序。")
	assert_eq(EQUIPMENT_DATA_COMPAT_SCRIPT.call("get_set_type", gd_tool), 2, "GDScript 工具套装值必须保留。")
	assert_eq(EQUIPMENT_DATA_COMPAT_SCRIPT.call("get_attribute_bonuses", gd_tool)[0], Vector2i(3, 7), "GDScript 工具属性范围必须保留。")
	assert_eq(EQUIPMENT_DATA_COMPAT_SCRIPT.call("get_granted_tags", gd_tool), gd_tags, "GDScript 工具标签必须保留。")
	assert_eq(EQUIPMENT_DATA_COMPAT_SCRIPT.call("get_target_gathering_tag", gd_tool), &"wood", "GDScript 工具采集标签必须保留。")
	assert_eq(EQUIPMENT_DATA_COMPAT_SCRIPT.call("get_yield_growth", gd_tool), 3, "GDScript 工具额外产量必须保留。")
	assert_eq(EQUIPMENT_DATA_COMPAT_SCRIPT.call("get_gathering_time_reduction", gd_tool), 12, "GDScript 工具时间减免必须保留。")

	## 旧 C# ToolData 的兼容读取能力：C# 退役后不再有旧实现可测，整块按条件收起
	## （本用例其余 GDScript 断言仍在执行，因此不会退化成 0 断言）。
	if CS_OPTIONAL.present(LEGACY_TOOL_DATA_CS_PATH):
		var legacy_tool := CS_OPTIONAL.script(LEGACY_TOOL_DATA_CS_PATH).new() as Resource
		assert_true(legacy_tool != null, "旧 C# ToolData 必须可供装备兼容桥读取。")
		var legacy_slots: Array = legacy_tool.get("ValidSlots")
		legacy_slots.append(5)
		legacy_tool.set("TargetGatheringTag", &"wood")
		legacy_tool.set("GatheringTimeReduction", 10)
		assert_true(bool(EQUIPMENT_DATA_COMPAT_SCRIPT.call("is_equipment_resource", legacy_tool)), "旧 C# ToolData 必须被识别为装备。")
		assert_true(bool(EQUIPMENT_DATA_COMPAT_SCRIPT.call("is_tool_resource", legacy_tool)), "旧 C# ToolData 必须被识别为工具。")
		assert_eq(EQUIPMENT_DATA_COMPAT_SCRIPT.call("get_valid_slots", legacy_tool), [5], "旧 C# 斧头槽位必须读取为 Axe=5。")
		assert_eq(EQUIPMENT_DATA_COMPAT_SCRIPT.call("get_target_gathering_tag", legacy_tool), &"wood", "旧 C# 斧头采集标签必须保留。")
		assert_eq(EQUIPMENT_DATA_COMPAT_SCRIPT.call("get_yield_growth", legacy_tool), 0, "旧 C# 斧头默认额外产量必须保持 0。")
		assert_eq(EQUIPMENT_DATA_COMPAT_SCRIPT.call("get_gathering_time_reduction", legacy_tool), 10, "旧 C# 斧头时间减免必须保持 10。")

	var plain_item: Resource = load(PRODUCTION_PLAIN_ITEM_ASSET_PATH)
	assert_false(bool(EQUIPMENT_DATA_COMPAT_SCRIPT.call("is_equipment_resource", plain_item)), "普通 ItemData 不能被误判为装备。")
	assert_false(bool(EQUIPMENT_DATA_COMPAT_SCRIPT.call("is_tool_resource", plain_item)), "普通 ItemData 不能被误判为工具。")


## 验证装备槽位与套装枚举值完整保持 C# 的序列化顺序。
func test_equipment_type_enum_values_preserved() -> void:
	var slots: Dictionary = EQUIPMENT_TYPES_SCRIPT.EquipmentSlot
	assert_eq(slots.size(), 16, "装备槽位枚举必须保持 16 个成员。")
	assert_eq(slots.Helmet, 0, "Helmet 必须保持为 0。")
	assert_eq(slots.Weapon, 4, "Weapon 必须保持为 4。")
	assert_eq(slots.Axe, 5, "Axe 必须保持为 5。")
	assert_eq(slots.Pickaxe, 6, "Pickaxe 必须保持为 6。")
	assert_eq(slots.Torch, 10, "Torch 必须保持为 10。")
	assert_eq(slots.Ring1, 12, "Ring1 必须保持为 12。")
	assert_eq(slots.Ring2, 13, "Ring2 必须保持为 13。")
	assert_eq(slots.MagicItem, 15, "MagicItem 必须保持为 15。")

	var sets: Dictionary = EQUIPMENT_TYPES_SCRIPT.EquipmentSet
	assert_eq(sets.size(), 4, "装备套装枚举必须保持 4 个成员。")
	assert_eq(sets.None, 0, "None 必须保持为 0。")
	assert_eq(sets.Wooden, 1, "Wooden 必须保持为 1。")
	assert_eq(sets.Stone, 2, "Stone 必须保持为 2。")
	assert_eq(sets.Iron, 3, "Iron 必须保持为 3。")


## 通过已注册的迁移套件入口验证默认 DebugLoadout 资源与 Main 生产引用。
## 返回值：无。
func test_debug_loadout_default_resource_and_main_references() -> void:
	_run_debug_loadout_case(&"test_default_resource_and_main_references_use_gdscript")


## 通过已注册的迁移套件入口验证固定堆叠兼容类型。
## 返回值：无。
func test_debug_loadout_item_stack_entry_contract() -> void:
	_run_debug_loadout_case(&"test_item_stack_entry_preserves_item_amount_and_compatibility_type")


## 通过已注册的迁移套件入口验证动态装备与工具数据。
## 返回值：无。
func test_debug_loadout_generated_equipment_contract() -> void:
	_run_debug_loadout_case(&"test_generated_equipment_preserves_regular_and_tool_contract")


## 通过已注册的迁移套件入口验证 Seeder 清空、填充和 ApplyOnce 时序。
## 返回值：无。
func test_debug_loadout_seeder_contract() -> void:
	_run_debug_loadout_case(&"test_seeder_preserves_apply_order_and_apply_once_contract")


## 强制从磁盘加载独立迁移套件并把其断言结果映射到当前已注册套件。
## 参数 method_name：独立套件中需要执行的测试方法名。
## 返回值：无。
func _run_debug_loadout_case(method_name: StringName) -> void:
	## 强制替换缓存的独立套件脚本，确保迁移迭代始终验证磁盘最新内容。
	var suite_script := ResourceLoader.load(
		"res://tests/godot/test_debug_loadout_migration.gd",
		"Script",
		ResourceLoader.CACHE_MODE_REPLACE
	) as Script
	assert_true(suite_script != null, "DebugLoadout 独立迁移套件必须能够加载。")
	if suite_script == null:
		return
	## 独立套件实例承载该聚焦用例的详细断言状态。
	var migration_suite := suite_script.new() as McpTestSuite
	migration_suite._reset()
	migration_suite.call(method_name)
	assert_gt(migration_suite._assertion_count, 0, "DebugLoadout 聚焦用例必须执行至少一个断言。")
	assert_false(migration_suite._failed, migration_suite._message)


## 验证 Crafting 三个 GDScript Resource 的字段、默认值和嵌套资源身份。
func test_crafting_resource_gdscript_contract() -> void:
	var ingredient: Resource = CRAFTING_INGREDIENT_SCRIPT.new()
	var required_item := Resource.new()
	assert_eq(ingredient.get("RequiredItem"), null, "材料默认物品必须为空。")
	assert_eq(ingredient.get("Amount"), 1, "材料默认数量必须保持为 1。")
	ingredient.set("RequiredItem", required_item)
	ingredient.set("Amount", 3)
	assert_true(ingredient.get("RequiredItem") == required_item, "材料必须保留物品 Resource 身份。")
	assert_eq(ingredient.get("Amount"), 3, "材料数量必须可序列化为正整数。")

	var recipe: Resource = CRAFTING_RECIPE_SCRIPT.new()
	var output_item := Resource.new()
	assert_eq(recipe.get("RecipeName"), "", "配方名称默认必须为空字符串。")
	assert_eq(recipe.get("Inputs").size(), 0, "配方材料默认必须为空数组。")
	assert_eq(recipe.get("OutputItem"), null, "配方输出物品默认必须为空。")
	assert_eq(recipe.get("OutputAmount"), 1, "配方默认产出数量必须保持为 1。")
	recipe.set("RecipeName", "测试配方")
	var inputs: Array[Resource] = [ingredient]
	recipe.set("Inputs", inputs)
	recipe.set("OutputItem", output_item)
	recipe.set("OutputAmount", 2)
	assert_eq(recipe.get("RecipeName"), "测试配方", "配方名称必须保留。")
	assert_eq(recipe.get("Inputs").size(), 1, "配方必须保留材料条目数量。")
	assert_true(recipe.get("Inputs")[0] == ingredient, "配方必须保留材料 Resource 身份。")
	assert_true(recipe.get("OutputItem") == output_item, "配方必须保留输出物品 Resource 身份。")
	assert_eq(recipe.get("OutputAmount"), 2, "配方产出数量必须保留。")

	var book: Resource = RECIPE_BOOK_SCRIPT.new()
	assert_eq(book.get("Recipes").size(), 0, "配方书默认必须为空数组。")
	var recipes: Array[Resource] = [recipe]
	book.set("Recipes", recipes)
	assert_eq(book.get("Recipes").size(), 1, "配方书必须保留配方数量。")
	assert_true(book.get("Recipes")[0] == recipe, "配方书必须保留配方 Resource 身份。")
	assert_eq(ingredient.get_script().resource_path, "res://resources/recipe/crafting_ingredient.gd")
	assert_eq(recipe.get_script().resource_path, "res://resources/recipe/crafting_recipe.gd")
	assert_eq(book.get_script().resource_path, "res://resources/recipe/recipe_book_data.gd")


## 验证旧路径配方资产仍可加载，且已切换到 GDScript 脚本（不再被 C# 强类型字段拒收）。
func test_crafting_legacy_assets_remain_loadable() -> void:
	var torch: Resource = load("res://resources/recipe/res/torch_recipe.tres")
	var axe: Resource = load("res://resources/recipe/res/stone_axe_recipe.tres")
	assert_true(torch != null, "火把配方资产必须仍可加载。")
	assert_true(axe != null, "石斧配方资产必须仍可加载。")
	if torch != null:
		assert_eq(torch.get("RecipeName"), "火把合成表", "火把配方名称不得丢失。")
		assert_eq(torch.get("Inputs").size(), 2, "火把配方材料数量不得丢失。")
		assert_eq(torch.get("OutputAmount"), 1, "火把配方产出数量不得改变。")
		assert_eq(
			(torch.get_script() as Script).resource_path,
			"res://resources/recipe/crafting_recipe.gd",
			"火把配方资产必须使用 GDScript 配方脚本。"
		)
		assert_true(torch.get("OutputItem") != null, "火把配方产出物品不得丢失。")
	if axe != null:
		assert_eq(axe.get("RecipeName"), "stone_axe", "石斧配方名称不得丢失。")
		assert_eq(axe.get("Inputs").size(), 2, "石斧配方材料数量不得丢失。")
		assert_eq(axe.get("OutputAmount"), 1, "石斧配方产出数量不得改变。")
		assert_eq(
			(axe.get_script() as Script).resource_path,
			"res://resources/recipe/crafting_recipe.gd",
			"石斧配方资产必须使用 GDScript 配方脚本。"
		)
		assert_true(axe.get("OutputItem") != null, "石斧配方产出物品不得丢失。")


## 验证玩家生产配方书已经切换到 GDScript Resource，旧路径资产同样已切到 GDScript。
func test_crafting_production_assets_use_gdscript() -> void:
	var production_paths := [
		"res://resources/recipe/res/torch_recipe_gd.tres",
		"res://resources/recipe/res/stone_axe_recipe_gd.tres",
	]
	for asset_path: String in production_paths:
		var recipe := load(asset_path) as Resource
		assert_true(recipe != null, "%s 必须可加载。" % asset_path)
		if recipe == null:
			continue
		assert_eq(recipe.get_script().resource_path, "res://resources/recipe/crafting_recipe.gd", "%s 必须使用 GDScript 配方。" % asset_path)
		assert_eq(recipe.get("Inputs").size(), 2, "%s 的材料数量不得改变。" % asset_path)

	var player_text := FileAccess.get_file_as_string("res://scenes/player_scenes/player.tscn")
	assert_true(player_text.contains("res://resources/recipe/recipe_book_data.gd"), "玩家配方书必须使用 GDScript Resource。")
	assert_true(player_text.contains("torch_recipe_gd.tres"), "玩家必须引用 GDScript 火把配方。")
	assert_true(player_text.contains("stone_axe_recipe_gd.tres"), "玩家必须引用 GDScript 石斧配方。")
	assert_true(not player_text.contains("RecipeBookData.cs"), "玩家生产配方书不应继续引用 C# 类型。")


## 验证 CraftingService 的需求汇总、虚拟库存预检和失败原因码。
func test_crafting_service_parallel_contract() -> void:
	var item_script: GDScript = load(ITEM_DATA_SCRIPT_PATH)
	var inventory_script: GDScript = load("res://entities/components/inventory_component.gd")
	var material: Resource = item_script.new()
	material.set("CardId", &"craft_material")
	material.set("CardName", "合成材料")
	material.set("MaxStackSize", 99)
	var filler: Resource = item_script.new()
	filler.set("CardId", &"craft_filler")
	filler.set("CardName", "占位物品")
	filler.set("MaxStackSize", 99)
	var output: Resource = item_script.new()
	output.set("CardId", &"craft_output")
	output.set("CardName", "合成产物")
	output.set("MaxStackSize", 2)

	var ingredient: Resource = CRAFTING_INGREDIENT_SCRIPT.new()
	ingredient.set("RequiredItem", material)
	ingredient.set("Amount", 5)
	var inputs: Array[Resource] = [ingredient]
	var recipe: Resource = CRAFTING_RECIPE_SCRIPT.new()
	recipe.set("RecipeName", "测试合成")
	recipe.set("Inputs", inputs)
	recipe.set("OutputItem", output)
	recipe.set("OutputAmount", 2)

	var inventory: Node = inventory_script.new()
	inventory.set("Capacity", 2)
	inventory.call("_ready")
	inventory.call("AddItem", material, 5)
	inventory.call("AddItem", filler, 1)
	var service: RefCounted = CRAFTING_SERVICE_SCRIPT.new()
	var requirements: Dictionary = service.call("TryBuildRequirements", recipe, 2)
	assert_eq(requirements.get(material), 10, "需求汇总必须按数量乘以合成次数。")
	assert_true(bool(service.call("IsRecipeValid", recipe)), "完整配方必须通过有效性检查。")
	assert_true(bool(service.call("CanCraft", inventory, recipe, 1)), "消耗材料释放槽位后应允许放入产物。")
	assert_eq(service.call("MaxCraftableQuantity", inventory, recipe), 1, "材料数量与空间共同决定最大合成数。")

	var invalid_output: Resource = item_script.new()
	invalid_output.set("CardId", &"craft_large_output")
	invalid_output.set("CardName", "超额产物")
	invalid_output.set("MaxStackSize", 2)
	var invalid_recipe: Resource = CRAFTING_RECIPE_SCRIPT.new()
	invalid_recipe.set("Inputs", inputs)
	invalid_recipe.set("OutputItem", invalid_output)
	invalid_recipe.set("OutputAmount", 3)
	assert_false(bool(service.call("CanCraft", inventory, invalid_recipe, 1)), "消耗后仍无法容纳产物时不得允许合成。")
	assert_eq(service.call("MaxCraftableQuantity", inventory, invalid_recipe), 0, "产物空间不足时最大合成数必须为 0。")
	var failure_reason: int = int(service.call("TryCraftWithReason", inventory, invalid_recipe, 1))
	assert_eq(failure_reason, 4, "产物空间不足必须返回 NotEnoughSpace=4。")
	assert_eq(inventory.call("ItemCnt", material), 5, "空间预检失败不得扣除材料。")
	assert_eq(inventory.call("ItemCnt", filler), 1, "空间预检失败不得改变其它物品。")

	var success_reason: int = int(service.call("TryCraftWithReason", inventory, recipe, 1))
	assert_eq(success_reason, 0, "满足条件时合成必须返回 None=0。")
	assert_eq(inventory.call("ItemCnt", material), 0, "成功合成后必须扣除材料。")
	assert_eq(inventory.call("ItemCnt", output), 2, "成功合成后必须加入完整产物数量。")

	var invalid_quantity_reason: int = int(service.call("TryCraftWithReason", inventory, recipe, 0))
	assert_eq(invalid_quantity_reason, 2, "非正数量必须返回 InvalidQuantity=2。")


## 验证 CraftingComponent 的库存绑定、配方读取、信号和失败码协议。
func test_crafting_component_parallel_contract() -> void:
	var item_script: GDScript = load(ITEM_DATA_SCRIPT_PATH)
	var inventory_script: GDScript = load("res://entities/components/inventory_component.gd")
	var material: Resource = item_script.new()
	material.set("CardId", &"component_material")
	material.set("CardName", "组件材料")
	material.set("MaxStackSize", 99)
	var output: Resource = item_script.new()
	output.set("CardId", &"component_output")
	output.set("CardName", "组件产物")
	output.set("MaxStackSize", 2)

	var ingredient: Resource = CRAFTING_INGREDIENT_SCRIPT.new()
	ingredient.set("RequiredItem", material)
	ingredient.set("Amount", 2)
	var inputs: Array[Resource] = [ingredient]
	var recipe: Resource = CRAFTING_RECIPE_SCRIPT.new()
	recipe.set("RecipeName", "组件测试配方")
	recipe.set("Inputs", inputs)
	recipe.set("OutputItem", output)
	recipe.set("OutputAmount", 2)
	var recipes: Array[Resource] = [recipe]
	var book: Resource = RECIPE_BOOK_SCRIPT.new()
	book.set("Recipes", recipes)

	var owner := Node.new()
	var inventory: Node = inventory_script.new()
	inventory.name = "InventoryComponent"
	inventory.set("Capacity", 2)
	owner.add_child(inventory)
	var component: Node = CRAFTING_COMPONENT_SCRIPT.new()
	component.name = "CraftingComponent"
	component.set("RecipeBook", book)
	owner.add_child(component)
	inventory.call("_ready")
	component.call("_ready")
	inventory.call("AddItem", material, 2)

	var completed: Array = []
	component.connect("CraftingCompleted", func(done_recipe: Variant, quantity: int, amount: int) -> void:
		completed.append({"recipe": done_recipe, "quantity": quantity, "amount": amount})
	)
	var failed: Array = []
	component.connect("CraftingFailed", func(failed_recipe: Variant, quantity: int, reason: int) -> void:
		failed.append({"recipe": failed_recipe, "quantity": quantity, "reason": reason})
	)

	assert_true(component.get("Inventory") == inventory, "组件必须绑定同级 InventoryComponent。")
	assert_eq(component.get("Recipes").size(), 1, "组件必须过滤空配方并保留配方顺序。")
	assert_true(component.get("Recipes")[0] == recipe, "组件必须保留配方 Resource 身份。")
	assert_true(bool(component.call("CanCraft", recipe, 1)), "组件必须转发服务的可合成判断。")
	assert_eq(int(component.call("MaxCraftableQuantity", recipe)), 1, "组件必须返回服务计算的最大合成数。")
	assert_eq(int(component.call("TryCraftWithReason", recipe, 1)), 0, "有效配方必须合成成功。")
	assert_eq(inventory.call("ItemCnt", material), 0, "组件成功合成后必须扣除材料。")
	assert_eq(inventory.call("ItemCnt", output), 2, "组件成功合成后必须加入产物。")
	assert_eq(completed.size(), 1, "成功合成必须只发出一次 CraftingCompleted。")
	assert_true(completed[0]["recipe"] == recipe, "完成信号必须携带原配方对象。")
	assert_eq(completed[0]["amount"], 2, "完成信号必须携带完整产出数量。")
	assert_eq(int(component.call("TryCraftWithReason", recipe, 1)), 3, "材料不足必须返回 MissingMaterials=3。")
	assert_eq(int(component.get("LastFailureReason")), 3, "组件必须保存最近一次失败原因。")
	assert_eq(failed.size(), 1, "失败合成必须只发出一次 CraftingFailed。")
	assert_eq(failed[0]["reason"], 3, "失败信号必须携带稳定失败码。")
	owner.free()


## 验证 ShopService 的价格回退、买卖原子性和固定失败码协议。
func test_shop_service_parallel_contract() -> void:
	var item_script: GDScript = load(ITEM_DATA_SCRIPT_PATH)
	var inventory_script: GDScript = load("res://entities/components/inventory_component.gd")
	var item: Resource = item_script.new()
	item.set("CardId", &"shop_service_item")
	item.set("CardName", "商店测试物品")
	item.set("MaxStackSize", 99)
	item.set("BuyPrice", 50)
	item.set("SellPrice", 0)
	var filler: Resource = item_script.new()
	filler.set("CardId", &"shop_service_filler")
	filler.set("CardName", "商店占位物品")
	filler.set("MaxStackSize", 1)

	var inventory: Node = inventory_script.new()
	inventory.set("Capacity", 2)
	inventory.call("_ready")
	var wallet := FakeShopWallet.new()
	wallet.Gold = 100
	var service: RefCounted = SHOP_SERVICE_SCRIPT.new()

	assert_true(bool(service.call("IsPurchasable", item)), "正数买价物品必须可购买。")
	assert_eq(int(service.call("ResolveSellPrice", item)), 25, "缺省卖价必须按买价折半。")
	assert_true(bool(service.call("CanBuy", wallet, inventory, item, 2)), "余额和容量足够时必须允许购买。")
	assert_eq(int(service.call("TryBuyWithReason", wallet, inventory, item, 2)), 0, "购买成功必须返回 None=0。")
	assert_eq(wallet.Gold, 0, "购买成功必须扣除总价而不是单价。")
	assert_eq(inventory.call("ItemCnt", item), 2, "购买成功必须完整加入商品。")

	inventory.call("TryRemoveItem", item, 2)
	wallet.Gold = 0
	assert_eq(int(service.call("TryBuyWithReason", wallet, inventory, item, 1)), 3, "余额不足必须返回 NotEnoughGold=3。")
	assert_eq(inventory.call("ItemCnt", item), 0, "余额不足不得写入商品。")

	wallet.Gold = 100
	inventory.call("AddItem", filler, 2)
	assert_false(bool(service.call("CanBuy", wallet, inventory, item, 1)), "库存已满时不得允许购买。")
	assert_eq(int(service.call("TryBuyWithReason", wallet, inventory, item, 1)), 4, "库存空间不足必须返回 NotEnoughSpace=4。")
	assert_eq(wallet.Gold, 100, "空间不足不得扣除金币。")
	inventory.call("TryRemoveItem", filler, 2)

	assert_eq(int(service.call("TryBuyWithReason", wallet, inventory, item, 0)), 2, "非正购买数量必须返回 InvalidQuantity=2。")
	inventory.call("AddItem", item, 2)
	wallet.Gold = 0
	assert_true(bool(service.call("CanSell", wallet, inventory, item, 1)), "持有物品且有回退卖价时必须允许出售。")
	assert_eq(int(service.call("TrySellWithReason", wallet, inventory, item, 1)), 0, "出售成功必须返回 None=0。")
	assert_eq(wallet.Gold, 25, "出售成功必须按折半卖价进账。")
	assert_eq(inventory.call("ItemCnt", item), 1, "出售成功必须只移除指定数量。")
	assert_eq(int(service.call("TrySellWithReason", wallet, inventory, item, 2)), 5, "持有量不足必须返回 MissingItem=5。")
	assert_eq(wallet.Gold, 25, "出售失败不得增加金币。")
	assert_eq(int(service.get("LastFailureReason")), 5, "服务必须保存最近一次失败原因。")
	item.set("SellPrice", 40)
	assert_eq(int(service.call("ResolveSellPrice", item)), 40, "显式卖价必须优先于买价折半。")


## 验证 ShopTradeBridge 的目录顺序、价格回退和动态交易协议。
func test_shop_trade_bridge_parallel_contract() -> void:
	var shop_scene: PackedScene = load("res://scenes/Shop/Shop.tscn")
	assert_true(shop_scene != null, "商店生产场景必须能够加载。")
	if shop_scene != null:
		var shop_root: Node = shop_scene.instantiate()
		var production_bridge: Node = shop_root.get_node("ShopTradeBridge")
		assert_eq(
			production_bridge.get_script().resource_path,
			"res://core/shop/shop_trade_bridge.gd",
			"商店生产节点必须切换到 GDScript Bridge。"
		)
		var production_catalog := production_bridge.get("Catalog") as Resource
		assert_true(production_catalog != null, "商店生产 Bridge 必须继续引用商品目录。")
		if production_catalog != null:
			var production_goods: Array = production_catalog.get("Goods")
			assert_eq(production_goods.size(), 89, "商品目录的 89 个显式条目不得丢失。")
			var gdscript_plain_item_count: int = 0
			for production_good: Variant in production_goods:
				if production_good is Resource and (production_good as Resource).get_script() != null:
					if (production_good as Resource).get_script().resource_path == ITEM_DATA_SCRIPT_PATH:
						gdscript_plain_item_count += 1
			assert_eq(gdscript_plain_item_count, 86, "商品目录中的 86 个普通 ItemData 商品必须使用 GDScript。")
		shop_root.free()

	var item_script: GDScript = load(ITEM_DATA_SCRIPT_PATH)
	var inventory_script: GDScript = load("res://entities/components/inventory_component.gd")
	var explicit_item: Resource = item_script.new()
	explicit_item.set("CardId", &"explicit_item")
	explicit_item.set("CardName", "显式商品")
	explicit_item.set("BuyPrice", 0)
	var priced_z: Resource = item_script.new()
	priced_z.set("CardId", &"z_item")
	priced_z.set("BuyPrice", 30)
	var priced_a: Resource = item_script.new()
	priced_a.set("CardId", &"a_item")
	priced_a.set("BuyPrice", 20)

	var catalog: Resource = load("res://resources/shop/shop_catalog.gd").new()
	var catalog_goods: Array[Resource] = []
	catalog_goods.append(explicit_item)
	catalog_goods.append(priced_z)
	catalog.set("Goods", catalog_goods)
	catalog.set("AlsoIncludeEveryPricedItem", true)
	catalog.set("DefaultBuyPrice", 100)
	var bridge: Node = SHOP_TRADE_BRIDGE_SCRIPT.new()
	bridge.set("Catalog", catalog)

	assert_true(bool(bridge.call("IsPurchasable", explicit_item)), "显式上架且无自身买价的商品必须可购买。")
	assert_eq(int(bridge.call("GetBuyPrice", explicit_item)), 100, "显式商品必须使用目录兜底买价。")
	assert_eq(int(bridge.call("GetSellPrice", explicit_item)), 50, "目录兜底买价的卖价必须按折半规则计算。")
	var stock: Array = bridge.call("BuildStockList", [priced_z, explicit_item, priced_a, priced_z])
	assert_eq(stock.size(), 3, "显式商品与自动商品必须去重。")
	if stock.size() == 3:
		assert_true(stock[0] == explicit_item, "显式目录商品必须保持原有顺序。")
		assert_true(stock[1] == priced_z, "显式目录中的第二项必须保持在自动商品之前。")
		assert_true(stock[2] == priced_a, "自动补入商品必须按 CardId 升序追加。")

	var inventory: Node = inventory_script.new()
	inventory.set("Capacity", 2)
	inventory.call("_ready")
	var wallet := FakeShopWallet.new()
	wallet.Gold = 100
	assert_true(bool(bridge.call("CanBuy", wallet, inventory, priced_a, 1)), "动态钱包与库存满足条件时应允许购买。")
	assert_eq(int(bridge.call("TryBuyWithReason", wallet, inventory, priced_a, 1)), 0, "Bridge 购买成功必须返回 None=0。")
	assert_eq(wallet.Gold, 80, "Bridge 购买必须按商品买价扣除金币。")
	assert_eq(int(bridge.call("GetItemCount", inventory, priced_a)), 1, "Bridge 必须读取库存中的商品数量。")
	assert_true(bool(bridge.call("CanSell", inventory, priced_a, 1)), "持有商品时 Bridge 应允许出售。")
	assert_eq(int(bridge.call("TrySellWithReason", wallet, inventory, priced_a, 1)), 0, "Bridge 出售成功必须返回 None=0。")
	assert_eq(wallet.Gold, 90, "Bridge 出售必须按买价折半入账。")
	assert_eq(int(bridge.call("GetItemCount", inventory, priced_a)), 0, "Bridge 出售必须移除指定商品。")
	inventory.free()
	bridge.free()


## 验证 PlayerWallet 并行实现的余额、信号、边界和 int 上限契约。
func test_player_wallet_parallel_contract() -> void:
	var wallet: Node = PLAYER_WALLET_SCRIPT.new()
	assert_eq(int(wallet.get("Gold")), 1200, "新建钱包必须使用默认金币 1200。")
	var emitted: Array[int] = []
	wallet.connect("GoldChanged", func(gold: int) -> void:
		emitted.append(gold)
	)
	assert_true(bool(wallet.call("TrySpend", 200)), "余额足够时扣款必须成功。")
	assert_eq(int(wallet.get("Gold")), 1000, "扣款后余额必须减少指定金额。")
	assert_eq(emitted.size(), 1, "成功扣款必须只发出一次 GoldChanged。")
	assert_eq(emitted[0], 1000, "GoldChanged 必须携带变化后的余额。")
	assert_false(bool(wallet.call("TrySpend", 0)), "零金额扣款必须失败。")
	assert_false(bool(wallet.call("TrySpend", -5)), "负金额扣款必须失败。")
	assert_false(bool(wallet.call("TrySpend", 1001)), "超过余额的扣款必须失败且不改余额。")
	wallet.call("Add", 50)
	assert_eq(int(wallet.get("Gold")), 1050, "正数 Add 必须增加余额。")
	wallet.call("Add", 0)
	wallet.call("Add", -10)
	assert_eq(int(wallet.get("Gold")), 1050, "非正数 Add 必须忽略。")
	wallet.set("Gold", 2147483640)
	wallet.call("Add", 20)
	assert_eq(int(wallet.get("Gold")), 2147483647, "大额进账必须钳制在 C# int 上限。")
	wallet.free()


## 验证 PlayerProgression 并行实现的规则表、扣款顺序、容量同步和升级信号。
func test_player_progression_parallel_contract() -> void:
	var progression: Node = PLAYER_PROGRESSION_SCRIPT.new()
	var wallet := FakeShopWallet.new()
	wallet.Gold = 1200
	var warehouse := FakeProgressionWarehouse.new()
	progression.set("_wallet", wallet)
	progression.set("_warehouse", warehouse)
	assert_eq(int(progression.call("GetWarehouseLevel")), 0, "仓库默认等级必须为 0。")
	assert_eq(int(progression.call("GetWarehouseCapacity")), 27, "仓库默认容量必须为 27。")
	assert_eq(int(progression.call("GetWarehouseNextCost")), 300, "仓库首级费用必须为 300。")
	assert_false(bool(progression.call("IsWarehouseMaxLevel")), "仓库初始等级不应被视为满级。")
	assert_eq(int(progression.call("GetCarrySlotCount")), 5, "带入栏默认数量必须为 5。")
	assert_eq(int(progression.call("GetCarryNextCost")), 200, "带入栏首级费用必须为 200。")

	var emitted: Array = []
	progression.connect("UpgradeChanged", func(kind: String, value: int) -> void:
		emitted.append({"kind": kind, "value": value})
	)
	assert_true(bool(progression.call("TryUpgradeWarehouse")), "余额足够时仓库升级必须成功。")
	assert_eq(int(wallet.Gold), 900, "仓库升级必须先扣除 300 金币。")
	assert_eq(int(progression.call("GetWarehouseLevel")), 1, "仓库升级成功后等级必须为 1。")
	assert_eq(int(progression.call("GetWarehouseCapacity")), 36, "仓库升级后容量必须为 36。")
	assert_eq(int(warehouse.Capacity), 36, "仓库升级必须同步 FakeWarehouse 容量。")
	assert_eq(emitted.size(), 1, "成功升级必须只发出一次 UpgradeChanged。")
	if emitted.size() == 1:
		assert_eq(emitted[0]["kind"], "warehouse_capacity", "升级信号必须携带稳定项目名称。")
		assert_eq(int(emitted[0]["value"]), 36, "升级信号必须携带升级后的实际容量。")
	assert_true(bool(progression.call("TryUpgradeCarrySlots")), "余额足够时带入栏升级必须成功。")
	assert_eq(int(wallet.Gold), 700, "带入栏升级必须扣除 200 金币。")
	assert_eq(int(progression.call("GetCarryLevel")), 1, "带入栏升级后等级必须为 1。")
	assert_eq(int(progression.call("GetCarrySlotCount")), 6, "带入栏升级后数量必须为 6。")
	wallet.Gold = 0
	assert_false(bool(progression.call("TryUpgradeCarrySlots")), "余额不足时升级必须失败。")
	assert_eq(int(progression.call("GetCarryLevel")), 1, "余额不足时等级不得变化。")
	progression.free()


## 验证 TimeSystem 生产实现、Autoload 路径以及时间、昼夜、天数和地图移动协议。
func test_time_system_production_contract() -> void:
	var project_text: String = FileAccess.get_file_as_string("res://project.godot")
	assert_true(project_text.contains('TimeSystem="*res://core/autoloads/time_system.gd"'), "生产 TimeSystem Autoload 必须使用 GDScript 路径。")
	assert_false(project_text.contains('TimeSystem="*uid://da5qjs7g2tqfs"'), "生产 Autoload 不得继续引用旧 C# TimeSystem UID。")
	var production_consumers: Array[String] = [
		"res://core/gameflow/WorldInteractionCoordinator.cs",
		"res://core/gameflow/world_interaction_coordinator.gd",
		"res://core/gameflow/TerrainInteractionExecutor.cs",
		"res://core/map/RoomBoardPresenter.cs",
		"res://core/map/UIRoomBoardPresenter.gd",
		"res://core/application/EncounterManager.cs",
		"res://core/application/encounter_manager.gd",
		"res://resources/interaction/ReusableGatheringInteraction.cs",
		"res://resources/interaction/operations/PassTimeOp.cs",
		"res://resources/interaction/operations/RecordReusableGatheringOp.cs",
	]
	for consumer_path: String in production_consumers:
		var consumer_source: String = FileAccess.get_file_as_string(consumer_path)
		assert_false(consumer_source.contains("TimeSystem.Instance"), "%s 不得继续依赖 C# 静态 TimeSystem.Instance。" % consumer_path)

	var time_system: Node = TIME_SYSTEM_SCRIPT.new()
	var phase_events: Array = []
	var day_events: Array = []
	var snapshots: Array = []
	time_system.connect("DayNightToggled", func(is_night: bool) -> void:
		phase_events.append(is_night)
	)
	time_system.connect("DayPassed", func(day: int) -> void:
		day_events.append(day)
	)
	time_system.connect("TimeChanged", func(total: int, day: int, is_night: bool, progress: int, length: int) -> void:
		snapshots.append([total, day, is_night, progress, length])
	)
	assert_eq(int(time_system.get("TotalTimePassed")), 0, "时间系统初始累计值必须为 0。")
	assert_eq(int(time_system.get("CurrentDay")), 1, "时间系统初始天数必须为 1。")
	assert_eq(int(time_system.get("PhaseProgress")), 0, "时间系统初始阶段进度必须为 0。")
	time_system.call("PassTime", 0)
	assert_eq(int(time_system.get("TotalTimePassed")), 0, "非正时间推进必须被忽略。")
	time_system.call("PassTime", 250)
	assert_eq(int(time_system.get("TotalTimePassed")), 250, "时间推进必须累加到总时间。")
	assert_eq(int(time_system.get("CurrentDay")), 2, "跨越两个阶段后天数必须增加一次。")
	assert_eq(int(time_system.get("PhaseProgress")), 50, "阶段进度必须按 100 取模。")
	assert_eq(phase_events, [true, false], "跨越阶段必须按顺序发出昼夜信号。")
	assert_eq(day_events, [2], "偶数阶段必须发出天数增加信号。")
	assert_eq(int(time_system.get("MapMoveTimeCost")), 10, "地图移动默认耗时必须为 10。")
	time_system.call("SetMapMoveTimeCost", 15)
	time_system.call("PassMapMoveTime")
	assert_eq(int(time_system.get("TotalTimePassed")), 265, "地图移动必须使用更新后的耗时。")
	assert_true(snapshots.size() >= 2, "初始化与推进都必须广播完整时间快照。")
	if snapshots.size() >= 2:
		assert_eq(snapshots[0], [250, 2, false, 50, 100], "推进快照必须保留完整时间字段。")
		time_system.free()
