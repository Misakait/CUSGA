@tool
extends McpTestSuite

## 验证地形物资配置的编辑器类型、已有资产和实际布局生成兼容性。

## 资源点允许创建的五种现有交互，不包含无关 Resource。
const INTERACTION_TYPES: String = "GatheringInteraction,ReusableGatheringInteraction,FarmingInteraction,VaultInteraction,BossInteraction"


## 返回供编辑器筛选的套件名称。
## 返回值：地形资源编辑契约套件名。
func suite_name() -> String:
	return "terrain_resource_authoring"


## 验证专属类型已注册，并检查实际资源选择器的类型过滤。
## 返回值：无。
func test_registered_classes_and_picker_filters() -> void:
	var registered: Dictionary = {}
	for info: Dictionary in ProjectSettings.get_global_class_list():
		registered[String(info.get("class", ""))] = info.get("path", "")
	var expected: Dictionary = {
		"terrain_pool_entry": "res://core/map/room_terrain_pool_entry.gd",
		"RoomTerrainProfile": "res://core/map/room_terrain_profile.gd",
		"TerrainCardData": "res://resources/interaction/terrain_card_data.gd",
		"GatheringInteraction": "res://resources/interaction/gathering_interaction.gd",
		"ReusableGatheringInteraction": "res://resources/interaction/reusable_gathering_interaction.gd",
		"FarmingInteraction": "res://resources/interaction/farming_interaction.gd",
		"VaultInteraction": "res://resources/interaction/vault_interaction.gd",
		"BossInteraction": "res://resources/interaction/boss_interaction.gd",
		"LootTableData": "res://resources/loot/loot_table.gd",
		"LootDrop": "res://resources/loot/loot_drop.gd",
		"ItemData": "res://resources/item/item_data.gd",
		"MonsterStatMultiplierRange": "res://resources/encounters/monster_stat_multiplier_range.gd",
	}
	for type_name: String in expected:
		assert_eq(registered.get(type_name), expected[type_name], "%s 必须注册到正确脚本。" % type_name)
	for filter: String in ["terrain_pool_entry", "TerrainCardData", "LootTableData", "LootDrop", "ItemData", INTERACTION_TYPES]:
		var picker := EditorResourcePicker.new()
		picker.base_type = filter
		var allowed: PackedStringArray = picker.get_allowed_types()
		for type_name: String in filter.split(","):
			assert_true(allowed.has(type_name), "资源选择器必须包含 %s。" % type_name)
		assert_false(allowed.has("Resource"), "%s 选择器不能提供普通 Resource。" % filter)
		picker.free()


## 验证导出字段传递专属类型提示，并保留安全的空默认值。
## 返回值：无。
func test_exported_resource_types_and_defaults() -> void:
	_refresh_resource_scripts()
	var profile := RoomTerrainProfile.new()
	assert_eq(profile.TerrainPool.size(), 0, "新房间配置的物资池必须为空。")
	var pool_property: Dictionary = _find_property(profile, "TerrainPool")
	assert_eq(pool_property.get("type"), TYPE_ARRAY, "物资池必须是数组字段。")
	assert_true(int(pool_property.get("hint", PROPERTY_HINT_NONE)) != PROPERTY_HINT_NONE, "物资池必须提供类型数组提示，实际属性：%s。" % pool_property)
	assert_true(String(pool_property.get("hint_string", "")).contains("terrain_pool_entry"), "物资池元素必须限定为专属条目，实际属性：%s。" % pool_property)
	assert_eq(profile.MinCount, 1, "最少生成数默认值必须保持 1。")
	assert_eq(profile.MaxCount, 3, "最多生成数默认值必须保持 3。")
	var entry := terrain_pool_entry.new()
	_assert_resource_hint(entry, "TerrainData", "TerrainCardData")
	_assert_resource_hint(profile, "EncounterVarianceRange", "MonsterStatMultiplierRange")
	_assert_resource_hint(TerrainCardData.new(), "InteractionBehavior", INTERACTION_TYPES)
	_assert_resource_hint(GatheringInteraction.new(), "DropTable", "LootTableData")
	_assert_resource_hint(ReusableGatheringInteraction.new(), "DropTable", "LootTableData")
	_assert_resource_hint(LootDrop.new(), "Item", "ItemData")
	assert_eq(entry.TerrainData, null, "新条目不能借用其他地形数据。")
	assert_eq(entry.Weight, 1.0, "默认抽取权重必须保持 1。")
	var drops_property: Dictionary = _find_property(LootTableData.new(), "Drops")
	assert_true(int(drops_property.get("hint", PROPERTY_HINT_NONE)) != PROPERTY_HINT_NONE, "掉落表必须提供类型数组提示，实际属性：%s。" % drops_property)
	assert_true(String(drops_property.get("hint_string", "")).contains("LootDrop"), "掉落数组必须限定为 LootDrop。")


## 验证地图配置、内嵌地形和派生物品资产加载后仍能生成原有布局。
## 返回值：无。
func test_existing_profiles_and_derived_item_assets() -> void:
	for file_name: String in ["normal", "wood", "reusable_wood", "gold", "water", "fire", "earth"]:
		var path: String = "res://resources/map/terrain/%s_terrain.tres" % file_name
		var profile: RoomTerrainProfile = load(path) as RoomTerrainProfile
		assert_true(profile != null, "%s 必须按房间配置类型加载。" % path)
		if profile == null:
			continue
		var generator: RefCounted = load("res://core/map/room_terrain_layout_generator.gd").new(20261011)
		var placements: Array = generator.call("Generate", profile)
		assert_true(placements.size() >= profile.MinCount and placements.size() <= profile.MaxCount, "%s 必须保持原生成数量范围。" % path)
		for placement: Dictionary in placements:
			assert_true(placement.get("TerrainData") is TerrainCardData, "布局必须使用原地形数据类型。")
		for entry: terrain_pool_entry in profile.TerrainPool:
			# 用户编辑中的空槽必须保留；生成器已有跳过空候选的行为。
			if entry == null:
				continue
			assert_true(entry.TerrainData != null, "%s 的已配置条目不能丢失地形。" % path)
			if entry.TerrainData == null:
				continue
			var behavior: Resource = entry.TerrainData.InteractionBehavior
			assert_true(behavior != null and behavior.has_method("build_ops"), "原有地形交互必须保持可执行。")
	for path: String in ["res://items/items/berry.tres", "res://resources/item/card/res_cards/branch.tres", "res://items/tool/Ax.tres"]:
		var item: Resource = load(path)
		assert_true(item is ItemData, "%s 必须兼容物品基础类型。" % path)
		var drop := LootDrop.new()
		drop.Item = item
		assert_eq(drop.Item, item, "掉落配置必须保留原派生物品对象身份。")


## 核对实际对象导出到 Inspector 的资源类型提示。
## 参数 resource：待检查的配置资源。
## 参数 field：序列化字段名。
## 参数 expected：创建菜单使用的资源类型名称或逗号分隔名称。
## 返回值：无。
func _assert_resource_hint(resource: Resource, field: String, expected: String) -> void:
	for info: Dictionary in resource.get_property_list():
		if String(info.get("name", "")) != field:
			continue
		assert_eq(info.get("hint"), PROPERTY_HINT_RESOURCE_TYPE, "%s 必须提供资源类型提示。" % field)
		assert_eq(info.get("hint_string"), expected, "%s 必须显示对应专属资源。" % field)
		return
	assert_true(false, "必须保留导出字段 %s。" % field)


## 从资源属性列表读取字段元数据，避免依赖 Inspector 当前选中对象。
## 参数 resource：待检查的配置资源。
## 参数 field：序列化字段名。
## 返回值：匹配字段的属性字典；不存在时返回空字典。
func _find_property(resource: Resource, field: String) -> Dictionary:
	for info: Dictionary in resource.get_property_list():
		if String(info.get("name", "")) == field:
			return info
	return {}


## 按依赖顺序刷新编辑器已缓存的脚本，验证当前导出属性而非修改前的内存版本。
## 返回值：无；脚本刷新失败会产生明确断言。
func _refresh_resource_scripts() -> void:
	# 测试运行器长期缓存脚本；叶子类型先刷新，避免父资源仍引用旧字段类型。
	for path: String in [
		"res://resources/item/item_data.gd",
		"res://resources/loot/loot_drop.gd",
		"res://resources/loot/loot_table.gd",
		"res://resources/interaction/gathering_interaction.gd",
		"res://resources/interaction/reusable_gathering_interaction.gd",
		"res://resources/interaction/farming_interaction.gd",
		"res://resources/interaction/vault_interaction.gd",
		"res://resources/interaction/boss_interaction.gd",
		"res://resources/interaction/terrain_card_data.gd",
		"res://core/map/room_terrain_pool_entry.gd",
		"res://resources/encounters/monster_stat_multiplier_range.gd",
		"res://core/map/room_terrain_profile.gd",
		"res://scripts/map_scripts/map_son_scripts/map_base.gd",
	]:
		var script: GDScript = load(path) as GDScript
		assert_true(script != null, "%s 必须能加载为脚本。" % path)
		if script != null:
			assert_eq(script.reload(true), OK, "%s 必须能刷新编辑器缓存。" % path)
