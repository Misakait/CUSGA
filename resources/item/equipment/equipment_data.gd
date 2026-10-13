extends "res://resources/item/item_data.gd"
class_name EquipmentData

## 装备配置资源；槽位、套装和属性条目在 Inspector 选择，运行时状态由组件与堆叠保存。

const EQUIPMENT_TYPES: GDScript = preload("res://core/constants/equipment_types.gd")

## 允许装备的枚举槽位数组；0～15 编号保持已有资产协议。
@export_enum(
	"Helmet:0", "Chest:1", "Legs:2", "Boots:3", "Weapon:4", "Axe:5",
	"Pickaxe:6", "FishingRod:7", "LeftHandguard:8", "RightHandguard:9",
	"Torch:10", "Pendant:11", "Ring1:12", "Ring2:13", "Belt:14", "MagicItem:15"
) var ValidSlots: Array[int] = []

## 装备所属的多个套装标识；空数组没有套装，重复标识只按一件计数。
@export var SetType: PackedStringArray = PackedStringArray()

## 每项选择属性与整数加成范围；同属性多条独立生成后叠加，空元素跳过。
@export var AttributeBonuses: Array[EquipmentAttributeBonus] = []

## 穿戴后赋予玩家的行为标签，卸下时按同一列表撤销。
@export var GrantedTags: Array[StringName] = []


## 装备不可堆叠，防止独立随机结果被合并；无参数，无返回值。
func _init() -> void:
	MaxStackSize = 1


## 实际上限固定为一件，避免旧资源或检查器修改通用字段后合并独立装备。
## 参数：无。返回值：装备与工具的实际堆叠上限 1。
func _resolve_actual_max_stack_size() -> int:
	return 1
