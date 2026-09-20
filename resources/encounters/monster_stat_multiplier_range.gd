extends Resource

## 怪物遭遇属性倍率的最小值与最大值配置。
##
## 该资源只保存策划配置；随机抽样仍由 RoomTerrainLayoutGenerator 负责，
## 这样资源不会依赖随机数生成器，也不会把场景运行时状态写回资产。

## 生命上限倍率下界。
@export_group("Min")
@export var MinMaxHealth: float = 1.0
## 物理攻击倍率下界。
@export var MinPhysAtk: float = 1.0
## 物理防御倍率下界。
@export var MinPhysDef: float = 1.0
## 法术强度倍率下界。
@export var MinMagPower: float = 1.0
## 法术抗性倍率下界。
@export var MinMagResist: float = 1.0
## 速度倍率下界。
@export var MinSpeed: float = 1.0

## 生命上限倍率上界。
@export_group("Max")
@export var MaxMaxHealth: float = 1.0
## 物理攻击倍率上界。
@export var MaxPhysAtk: float = 1.0
## 物理防御倍率上界。
@export var MaxPhysDef: float = 1.0
## 法术强度倍率上界。
@export var MaxMagPower: float = 1.0
## 法术抗性倍率上界。
@export var MaxMagResist: float = 1.0
## 速度倍率上界。
@export var MaxSpeed: float = 1.0


## 返回下界倍率快照，供 GDScript 调试工具和跨语言桥接读取。
##
## 返回值：包含六个倍率字段的字典。
func get_min() -> Dictionary:
	return {
		"MaxHealth": MinMaxHealth,
		"PhysAtk": MinPhysAtk,
		"PhysDef": MinPhysDef,
		"MagPower": MinMagPower,
		"MagResist": MinMagResist,
		"Speed": MinSpeed,
	}


## 返回上界倍率快照，供 GDScript 调试工具和跨语言桥接读取。
##
## 返回值：包含六个倍率字段的字典。
func get_max() -> Dictionary:
	return {
		"MaxHealth": MaxMaxHealth,
		"PhysAtk": MaxPhysAtk,
		"PhysDef": MaxPhysDef,
		"MagPower": MaxMagPower,
		"MagResist": MaxMagResist,
		"Speed": MaxSpeed,
	}
