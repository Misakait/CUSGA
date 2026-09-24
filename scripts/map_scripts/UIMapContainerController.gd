extends Node2D

## 房间模块协调器；只校验和分发数据，不读取瓦片或操作玩家。
const MODULE_NAMES: Array[StringName] = [
	&"Ground", &"Obstack", &"BridgeContainer", &"BridgeWithBoundary", &"BridgeBoundary", &"Boundary",
]
var _room_context: RoomContext

## 为六个直接子模块注入同一份上下文；重复调用不增加节点或碰撞资源。
## @param context Model 提供的只读房间数据。
## @return 所有模块存在且成功配置时返回 true。
func configure_room_context(context: RoomContext) -> bool:
	if context == null:
		push_error("MapContainer 收到空的房间上下文。")
		return false
	var modules: Array[Node] = []
	# 先检查全部入口，再应用状态，避免缺少模块时只打开半个桥口。
	for module_name in MODULE_NAMES:
		var module := get_node_or_null(NodePath(module_name))
		if (
			module == null
			or not module.has_method(&"configure_room_context")
			or not module.has_method(&"validate_room_context")
		):
			push_error("MapContainer 缺少模块配置入口：%s" % module_name)
			return false
		modules.append(module)
	# 全部模块预检通过后才切换状态，防止后面的桥侧模块失败而先打开桥口。
	for module in modules:
		if not bool(module.call(&"validate_room_context", context)):
			push_error("MapContainer 模块预检失败：%s" % module.name)
			return false
	for module in modules:
		if not bool(module.call(&"configure_room_context", context)):
			return false
	_room_context = context
	return true

## 读取已成功配置的数据，供诊断和模块契约检查使用。
## @return 尚未配置时为 null，否则为 Model 提供的同一份上下文。
func get_room_context() -> RoomContext:
	return _room_context
