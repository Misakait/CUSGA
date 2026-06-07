extends SceneTree

## 批量脚本：为 scenes/map_scenes/map_env/ 下所有 .tscn 场景附加 map_env_base.gd 脚本。
##
## 用法：
##   godot-mono --headless --path . --script res://scripts/generated/attach_map_env_scripts.gd

const MAP_ENV_DIR := "res://scenes/map_scenes/map_env"
const BASE_SCRIPT_PATH := "res://scripts/map_scripts/map_env_base.gd"

var _base_script: Script = null
var _count: int = 0


func _init() -> void:
	print("[AttachMapEnvScripts] 开始批量附加脚本...")

	_base_script = load(BASE_SCRIPT_PATH) as Script
	if _base_script == null:
		printerr("无法加载基础脚本: ", BASE_SCRIPT_PATH)
		quit()
		return

	var dir := DirAccess.open(MAP_ENV_DIR)
	if dir == null:
		printerr("无法打开目录: ", MAP_ENV_DIR)
		quit()
		return

	_count = 0
	_walk(dir, MAP_ENV_DIR)
	print("[AttachMapEnvScripts] 共处理 ", _count, " 个场景。")
	quit()


func _walk(dir: DirAccess, base_path: String) -> void:
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
				_walk(sub_dir, full_path)
		elif file_name.ends_with(".tscn"):
			_attach_to(full_path)
			_count += 1
		file_name = dir.get_next()
	dir.list_dir_end()


func _attach_to(scene_path: String) -> void:
	var scene: PackedScene = load(scene_path) as PackedScene
	if scene == null:
		printerr("  无法加载: ", scene_path)
		return

	# 实例化场景，检查根节点
	var instance: Node = scene.instantiate()
	if instance == null:
		printerr("  无法实例化: ", scene_path)
		return

	# 已有脚本则跳过
	if instance.get_script() != null:
		instance.queue_free()
		return

	# 附加脚本 → 重新打包
	instance.set_script(_base_script)

	var new_scene := PackedScene.new()
	var err := new_scene.pack(instance)
	if err != OK:
		printerr("  pack 失败: ", scene_path, " err=", err)
		instance.queue_free()
		return

	instance.queue_free()

	err = ResourceSaver.save(new_scene, scene_path)
	if err == OK:
		print("  OK: ", scene_path)
	else:
		printerr("  保存失败: ", scene_path, " err=", err)
