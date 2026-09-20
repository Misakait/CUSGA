extends Resource

## 在 Debug 开局配置中动态生成测试装备的数据条目。
##
## 装备数据和 ItemStack 使用已经投产的 GDScript 实现；本 Resource 只负责保存并转换
## 检查器配置，不承担装备槽位、属性结算或采集规则。

## 生产普通装备 Resource 脚本。
const EQUIPMENT_DATA_SCRIPT: GDScript = preload("res://resources/item/equipment/equipment_data.gd")

## 生产工具装备 Resource 脚本。
const TOOL_DATA_SCRIPT: GDScript = preload("res://resources/item/tool/tool_data.gd")

## 生产库存和装备组件使用的 GDScript 堆叠脚本。
const ITEM_STACK_SCRIPT: GDScript = preload("res://resources/item/item_stack.gd")

## 装备槽整数值对应旧 EquipmentSlot 的 0..15 固定序列。
const EQUIPMENT_SLOT_NAMES: Array[String] = [
	"Helmet",
	"Chest",
	"Legs",
	"Boots",
	"Weapon",
	"Axe",
	"Pickaxe",
	"FishingRod",
	"LeftHandguard",
	"RightHandguard",
	"Torch",
	"Pendant",
	"Ring1",
	"Ring2",
	"Belt",
	"MagicItem",
]

## Debug 装备允许放入的装备槽位。
@export_enum(
	"Helmet:0",
	"Chest:1",
	"Legs:2",
	"Boots:3",
	"Weapon:4",
	"Axe:5",
	"Pickaxe:6",
	"FishingRod:7",
	"LeftHandguard:8",
	"RightHandguard:9",
	"Torch:10",
	"Pendant:11",
	"Ring1:12",
	"Ring2:13",
	"Belt:14",
	"MagicItem:15"
) var Slot: int = 4

## Debug 装备的显示名称。
@export var CardName: String = "测试装备"

## Debug 装备的描述文本。
@export_multiline var Description: String = "Debug generated equipment."

## Debug 装备的显示图标。
@export var CardIcon: Texture2D

## 装备提供的属性类型，整数值对应旧 AttributeType 的 0..14 固定序列。
@export_enum(
	"PhysAtk:0",
	"PhysDef:1",
	"MagPower:2",
	"MagResist:3",
	"Speed:4",
	"MaxHealth:5",
	"MaxEnergy:6",
	"FixedPhysPenetration:7",
	"PhysPenetrationRate:8",
	"FixedMagicPenetration:9",
	"MagicPenetrationRate:10",
	"CritRate:11",
	"CritDamage:12",
	"EvasionRate:13",
	"LifestealRate:14"
) var BonusAttribute: int = 0

## 装备随机属性的最小值和最大值。
@export var BonusRange: Vector2i = Vector2i(10, 10)

## 创建堆叠时是否立即生成装备随机属性。
@export var RollRandomStats: bool = true

## 工具匹配的采集标签；空标签生成普通装备。
@export var TargetGatheringTag: StringName = &""

## 工具提供的额外采集产量。
@export_range(0, 999, 1, "or_greater") var YieldGrowth: int = 0

## 工具减少的采集游戏时间点数。
@export_range(0, 999, 1, "or_greater") var GatheringTimeReduction: int = 0


## 创建包含当前 Debug 装备配置的生产物品堆叠。
## 返回值：已写入普通装备或工具数据的 GDScript ItemStack。
func CreateStack() -> RefCounted:
	## 根据采集字段决定普通装备与工具数据类型。
	var equipment := _create_equipment_data()
	## 生产装备资源持有的槽位整数数组。
	var valid_slots: Array = equipment.get("ValidSlots")
	valid_slots.append(Slot)
	## 生产装备资源持有的属性范围字典。
	var attribute_bonuses: Dictionary = equipment.get("AttributeBonuses")
	attribute_bonuses[BonusAttribute] = BonusRange

	## 生产组件通过稳定堆叠协议接收同一装备 Resource 身份。
	var stack := ITEM_STACK_SCRIPT.new() as RefCounted
	stack.call("SetItem", equipment, 1)
	if RollRandomStats:
		stack.call("RollRandomStats")
	return stack


## 按采集字段创建普通装备或工具数据，并复制全部显示配置。
## 返回值：生产 ItemStack 持有的 GDScript EquipmentData 或 ToolData。
func _create_equipment_data() -> Resource:
	## 当前配置对应的生产装备资源。
	var equipment: Resource
	if _should_create_tool_data():
		equipment = TOOL_DATA_SCRIPT.new() as Resource
		equipment.set("TargetGatheringTag", TargetGatheringTag)
		equipment.set("YieldGrowth", YieldGrowth)
		equipment.set("GatheringTimeReduction", GatheringTimeReduction)
	else:
		equipment = EQUIPMENT_DATA_SCRIPT.new() as Resource

	equipment.set("CardId", StringName("debug_%s_%s" % [_slot_name(Slot), CardName]))
	equipment.set("CardName", CardName)
	equipment.set("Description", Description)
	equipment.set("CardIcon", CardIcon)
	return equipment


## 判断当前配置是否需要工具专属采集字段。
## 返回值：任一采集字段生效时返回 true。
func _should_create_tool_data() -> bool:
	return not TargetGatheringTag.is_empty() or YieldGrowth > 0 or GatheringTimeReduction > 0


## 把稳定槽位整数还原为旧 C# 枚举用于 CardId 的名称。
## 参数 slot：EquipmentSlot 的稳定整数值。
## 返回值：有效值返回枚举名称，越界值返回原整数文本。
func _slot_name(slot: int) -> String:
	if slot >= 0 and slot < EQUIPMENT_SLOT_NAMES.size():
		return EQUIPMENT_SLOT_NAMES[slot]
	return str(slot)
