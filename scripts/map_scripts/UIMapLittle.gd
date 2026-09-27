extends Node2D

## 旧小地图调用入口的兼容适配器。
##
## 房间与桥已经统一交给两个 WorldMapCanvas 实例绘制。本节点保留旧门和地图按钮依赖的
## 方法名，但不会再建立第二套地图节点，也不会在房间真正进入前提前修改探索状态。

var map_scene: Dictionary = {}
var current_position: Vector2i = Vector2i.ZERO
var _map_model: Node = null


## 绑定统一地图 Model。
##
## @param model 地图世界 Model。
## @return Model 非空时返回 true。
func bind_model(model: Node) -> bool:
	_map_model = model
	if _map_model != null:
		var current_value: Variant = _map_model.get(&"current_position")
		if current_value is Vector2i:
			current_position = current_value
	return _map_model != null


## 兼容旧门和按钮脚本的房间创建入口。
##
## 真实揭示由 MapWorldModel.try_enter_room 成功后完成；本方法故意不提前创建图元。
##
## @param x 地图行坐标。
## @param y 地图列坐标。
## @return 无返回值。
func build_little_map(_x: int, _y: int) -> void:
	pass


## 兼容旧门和按钮脚本的当前格入口。
##
## @param x 地图行坐标。
## @param y 地图列坐标。
## @return 无返回值。
func change_this_cell_color(x: int, y: int) -> void:
	current_position = Vector2i(x, y)


## 兼容旧门和按钮脚本的旧格恢复入口。
##
## 新画布根据 Model.current_position 切换纹理，因此这里无需直接改 View。
##
## @param x 地图行坐标。
## @param y 地图列坐标。
## @return 无返回值。
func return_this_cell_color(_x: int, _y: int) -> void:
	pass


## 同步已经由 Model 确认的当前房间坐标。
##
## @param room_position 当前地图坐标。
## @return 无返回值。
func update_current_position(room_position: Vector2i) -> void:
	current_position = room_position
