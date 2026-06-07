extends Resource
class_name BiomeDefinition

## 一个生态群系的完整定义，包含该群系下所有场景及连接约束。
## 在 map_control.tscn 中以 sub_resource 形式内嵌。

## 群系英文标识名（如 "normal"、"earth"、"fire" 等）
@export var biome_name: String

## 是否为玩家初始进入的群系（游戏中只会有一个设为 true）
@export var is_starting_biome: bool = false

## 主场景列表（5 个），每个主场景生成时拥有 2~4 个通道
@export var main_scenes: Array[map_attribute] = []

## 过渡场景列表（15 个），每个过渡场景生成时拥有 1~2 个通道
@export var transition_scenes: Array[map_attribute] = []

## 传送场景（1 个），生成时拥有 3~4 个通道，承担跨群系连接
@export var teleport_scene: map_attribute

## 集市场景（1 个），生成时拥有 3~4 个通道，作为群系内部交易枢纽
@export var market_scene: map_attribute


## 返回该群系包含的所有场景的 map_attribute 列表（合并四类场景）
func get_all_scenes() -> Array[map_attribute]:
	var all: Array[map_attribute] = []
	all.append_array(main_scenes)
	all.append_array(transition_scenes)
	if teleport_scene != null:
		all.append(teleport_scene)
	if market_scene != null:
		all.append(market_scene)
	return all


## 返回该群系场景总数
func get_total_scene_count() -> int:
	var count := main_scenes.size() + transition_scenes.size()
	if teleport_scene != null:
		count += 1
	if market_scene != null:
		count += 1
	return count
