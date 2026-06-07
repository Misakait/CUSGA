extends Resource
class_name map_attribute

## 场景在地图上的显示名称
@export var scene_name: String

## 该场景在群系中的类别（主场景 / 过渡 / 传送 / 集市）
@export var category: SceneCategory.Category = SceneCategory.Category.TRANSITION

## 生成时最少连接数（与相邻房间的通道数下限）
@export var min_connections: int = 1

## 生成时最多连接数（与相邻房间的通道数上限，不超过4）
@export var max_connections: int = 4

## 场景的 .tscn 文件路径
@export_dir var scene_dir: String

## 预加载的场景 PackedScene（用于 MapInstantiator 实例化）
@export var scene_pkg: PackedScene

## 该场景类型在群系中出现的次数（群系模型中通常为 1）
@export var scene_count: int = 1

## 该场景的通道驻守怪物池（为空时回退到全局默认池）
@export var guard_encounter_pool: Array[PassageGuardEncounterData] = []

## 勾选后该场景的通道永不生成驻守怪物（忽略自身池和全局默认池）
@export var disable_guards: bool = false
