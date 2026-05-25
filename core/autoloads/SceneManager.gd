## 场景管理器，支持场景缓存。
## 场景实例化一次后缓存在内存中，切换时只做 remove/add，不销毁。
## Autoload — 注册后删掉旧的 Warehouse Autoload。
extends Node

## 场景 ID → 资源路径，集中管理。
const SCENE_MAP: Dictionary = {
	"main_menu": "res://scenes/main_menu_scenes/main_menu.tscn",
	"warehouse": "res://scenes/Warehouse/Warehouse.tscn",
}

## 缓存池：scene_id → 场景实例。实例化一次，永不销毁。
var _cache: Dictionary = {}
var _current_id: String = ""

func _ready() -> void:
	# 抓住游戏启动时加载的首个场景（Project Settings → Main Scene），缓存它
	var initial_scene: Node = get_tree().current_scene
	if initial_scene:
		_cache["main_menu"] = initial_scene
		_current_id = "main_menu"
	
	GlobalEventBus.scene_requested.connect(_on_scene_requested)
	
	if initial_scene and initial_scene.has_method("init"):
		initial_scene.init()

func _on_scene_requested(scene_id: String) -> void:
	if scene_id == _current_id:
		return
	
	var path: String = SCENE_MAP.get(scene_id, "")
	if path.is_empty():
		push_error("SceneManager: unknown scene_id '%s'" % scene_id)
		return
	
	_switch_to(scene_id, path)

func _switch_to(target_id: String, target_path: String) -> void:
	# 1. 把当前场景从树中移除（但不销毁！引用还在 _cache 里）
	var current: Node = _cache.get(_current_id) as Node
	if current and current.get_parent():
		
		ScreenTransitions.fade_out()
		await ScreenTransitions.fade_complete
		
		if current.has_method("exit"):
			current.exit()
		current.get_parent().remove_child(current)
	
	# 2. 获取或创建目标场景
	var target: Node = _cache.get(target_id) as Node
	if target == null:
		var packed: PackedScene = load(target_path) as PackedScene
		if not packed:
			push_error("SceneManager: failed to load '%s'" % target_path)
			return
		target = packed.instantiate()
		_cache[target_id] = target
	
	# 3. 挂入场景树，设为 current_scene
	ScreenTransitions.fade_in()
	get_tree().root.add_child(target)
	get_tree().current_scene = target
	_current_id = target_id
	if target.has_method("init"):
		target.init()
