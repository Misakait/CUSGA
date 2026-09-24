extends RefCounted

## 从地图系统解析当前房间背景，并复制给战斗场景使用。
##
## 该 Resource/RefCounted 只负责背景节点查找与复制；战斗场景创建、过场和
## 世界视图切换继续由 WorldCombatScenePresenter 负责，避免跨边界复制流程逻辑。

## 复制当前地图房间的背景节点。
##
## 参数：`map_system` 为包含 `MapInstantiator` 子节点的地图系统节点。
## 返回值：成功时返回复制出的 Sprite2D；没有可用背景时返回 null。
func DuplicateCurrentBackground(map_system: Node) -> Sprite2D:
	var background: Sprite2D = _find_current_background(map_system)
	if background == null:
		return null

	var duplicated: Node = background.duplicate()
	if not duplicated is Sprite2D:
		return null

	var result: Sprite2D = duplicated as Sprite2D
	result.name = "MapBackground"
	result.z_index = -1
	result.z_as_relative = false
	return result

func _find_current_background(map_system: Node) -> Sprite2D:
	if map_system == null:
		return null

	var map_instantiator: Node = map_system.get_node_or_null("MapInstantiator")
	if map_instantiator == null:
		return null

	# MapInstantiator 会缓存多个房间实例，子节点顺序不能代表当前房间。
	var current_background: Sprite2D = _try_get_background(_read_current_scene(map_instantiator))
	if current_background != null:
		return current_background

	for child: Node in map_instantiator.get_children():
		var child_background: Sprite2D = _try_get_background(child)
		if child_background != null:
			return child_background
	return null

func _read_current_scene(map_instantiator: Node) -> Node:
	var current_scene_value: Variant = map_instantiator.get("current_scene")
	if current_scene_value == null or not current_scene_value is Node:
		return null
	var current_scene: Node = current_scene_value as Node
	return current_scene if is_instance_valid(current_scene) else null

func _try_get_background(room_scene: Node) -> Sprite2D:
	if room_scene == null:
		return null
	return room_scene.get_node_or_null("Background") as Sprite2D
