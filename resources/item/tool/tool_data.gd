extends "res://resources/item/equipment/equipment_data.gd"

## 采集工具数据的生产 GDScript Resource 实现。
##
## 工具仍然只是装备配置；采集标签匹配、时间扣减和产量结算由现有运行时系统处理。

## 工具生效的采集标签；空标签表示没有指定采集类型。
@export var TargetGatheringTag: StringName = &""

## 工具额外增加的掉落数量。
@export var YieldGrowth: int = 0

## 匹配采集标签时减少的游戏时间点数。
@export_range(0, 999, 1, "or_greater") var GatheringTimeReduction: int = 0
