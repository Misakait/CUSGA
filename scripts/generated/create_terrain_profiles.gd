extends SceneTree

## 一次性脚本：创建 6 个群系默认 RoomTerrainProfile .tres 并分配到所有 map_env 场景。
##
## 用法：
##   godot-mono --headless --path . --script res://scripts/generated/create_terrain_profiles.gd

const PROFILE_DIR := "res://resources/map/terrain"
const MAP_ENV_DIR := "res://scenes/map_scenes/map_env"

# 每个群系使用的资源卡 UID（可在 Inspector 中后续替换）
const BIOME_CARDS := {
	"normal": { "uid": "uid://bnhd0g54vqry3", "tag": &"wood", "name": "树枝地形", "icon": "res://res/environment/tree.png" },
	"earth":  { "uid": "uid://sokcwukqcau4",  "tag": &"earth", "name": "石材地形", "icon": "res://res/environment/tree.png" },
	"fire":   { "uid": "uid://vlltwh1x74yg", "tag": &"fire", "name": "火把地形", "icon": "res://res/environment/tree.png" },
	"gold":   { "uid": "uid://mslyvpd6f5xi", "tag": &"gold", "name": "斧头地形", "icon": "res://res/environment/tree.png" },
	"water":  { "uid": "uid://bnhd0g54vqry3", "tag": &"water", "name": "水流地形", "icon": "res://res/environment/tree.png" },
	"wood":   { "uid": "uid://bnhd0g54vqry3", "tag": &"wood", "name": "树木地形", "icon": "res://res/environment/tree.png" },
}


func _init() -> void:
	print("[CreateTerrainProfiles] 开始...")

	# 确保输出目录存在
	var da := DirAccess.open("res://")
	if da != null and not da.dir_exists(PROFILE_DIR):
		da.make_dir_recursive(PROFILE_DIR)

	for bname in BIOME_CARDS.keys():
		_create_profile(bname)

	_assign_to_scenes()
	print("[CreateTerrainProfiles] 完成。")
	quit()


func _create_profile(bname: String) -> void:
	var card_info: Dictionary = BIOME_CARDS[bname]

	# 加载资源卡
	var res_card: Resource = load(card_info["uid"]) if not str(card_info["uid"]).is_empty() else null

	# --- 构建子资源链 ---

	# LootDrop
	var loot_drop := _new_rs("res://resources/loot/LootDrop.cs")
	loot_drop.set("Item", res_card)
	loot_drop.set("MinAmount", 1)
	loot_drop.set("MaxAmount", 3)

	# LootTable
	var loot_table := _new_rs("res://resources/loot/LootTable.cs")
	var drops: Array = [loot_drop]
	loot_table.set("Drops", drops)

	# GatheringInteraction
	var gather := _new_rs("res://resources/interaction/GatheringInteraction.cs")
	gather.set("GatheringTag", card_info["tag"])
	gather.set("DropTable", loot_table)

	# TerrainCardData
	var terrain_card := _new_rs("res://resources/interaction/TerrainCardData.cs")
	terrain_card.set("InteractionBehavior", gather)
	terrain_card.set("CardId", card_info["tag"])
	terrain_card.set("CardName", card_info["name"])
	var icon_tex: Resource = load(card_info["icon"])
	if icon_tex != null:
		terrain_card.set("CardIcon", icon_tex)

	# RoomTerrainPoolEntry
	var pool_entry := _new_rs("res://core/map/RoomTerrainPoolEntry.cs")
	pool_entry.set("TerrainData", terrain_card)

	# MonsterStatMultiplierRange (default 0.9~1.2)
	var variance := _new_rs("res://resources/encounters/MonsterStatMultiplierRange.cs")
	for stat in ["MinMaxHealth", "MinPhysAtk", "MinPhysDef", "MinMagPower", "MinMagResist", "MinSpeed"]:
		variance.set(stat, 0.9)
	for stat in ["MaxMaxHealth", "MaxPhysAtk", "MaxPhysDef", "MaxMagPower", "MaxMagResist", "MaxSpeed"]:
		variance.set(stat, 1.2)

	# RoomTerrainProfile
	var profile := _new_rs("res://core/map/RoomTerrainProfile.cs")
	profile.set("TerrainPool", [pool_entry])
	profile.set("MinCount", 1)
	profile.set("MaxCount", 3)
	profile.set("GridColumns", 6)
	profile.set("GridRows", 4)
	profile.set("PlacementMin", Vector2(360, 220))
	profile.set("PlacementMax", Vector2(920, 560))
	profile.set("EncounterVarianceRange", variance)

	# 保存
	var path := PROFILE_DIR + "/" + bname + "_terrain.tres"
	var err := ResourceSaver.save(profile, path)
	if err == OK:
		print("  OK: ", path)
	else:
		printerr("  FAIL: ", path, " err=", err)


func _assign_to_scenes() -> void:
	var dir := DirAccess.open(MAP_ENV_DIR)
	if dir == null:
		printerr("无法打开 ", MAP_ENV_DIR)
		return

	_assign_walk(dir, MAP_ENV_DIR)


func _assign_walk(dir: DirAccess, base_path: String) -> void:
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue

		var full_path: String = base_path + "/" + file_name
		if dir.current_is_dir():
			var sub_dir := DirAccess.open(full_path)
			if sub_dir != null:
				_assign_walk(sub_dir, full_path)
		elif file_name.ends_with(".tscn"):
			# 从路径中提取群系名: .../map_env/{biome}/...
			var biome := _extract_biome(full_path)
			if not biome.is_empty():
				_assign_profile(full_path, biome)
		file_name = dir.get_next()
	dir.list_dir_end()


func _extract_biome(scene_path: String) -> String:
	var parts := scene_path.replace("res://scenes/map_scenes/map_env/", "").split("/")
	if parts.size() >= 1:
		var bname := parts[0]
		if bname in BIOME_CARDS:
			return bname
	return ""


func _assign_profile(scene_path: String, biome: String) -> void:
	var profile_path := PROFILE_DIR + "/" + biome + "_terrain.tres"
	var profile: Resource = load(profile_path)
	if profile == null:
		printerr("  无法加载地形配置: ", profile_path)
		return

	var scene: PackedScene = load(scene_path) as PackedScene
	if scene == null:
		return

	var instance: Node = scene.instantiate()
	if instance == null:
		return

	# 设置 terrain_profile
	instance.set("terrain_profile", profile)

	var new_scene := PackedScene.new()
	var err := new_scene.pack(instance)
	instance.queue_free()

	if err != OK:
		printerr("  pack 失败: ", scene_path)
		return

	err = ResourceSaver.save(new_scene, scene_path)
	if err == OK:
		print("  assigned: ", scene_path)
	else:
		printerr("  保存失败: ", scene_path)


func _new_rs(script_path: String) -> Resource:
	var rs := Resource.new()
	var sc: Script = load(script_path) as Script
	rs.set_script(sc)
	return rs
