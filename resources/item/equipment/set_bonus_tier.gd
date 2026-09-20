extends Resource

## 装备套装的单级激活配置。
##
## 该 Resource 只保存达到指定件数后应提供的属性与标签；套装计数、效果应用和清理由
## EquipmentComponent 负责。使用通用 Dictionary 保留 C# AttributeType 枚举键和浮点数值。

## 激活本级套装效果所需的装备件数；默认 0 与旧 C# 整数默认值一致。
@export var RequiredPieces: int = 0

## 激活后提供的属性加成；键保留 AttributeType 的整数值，值保留浮点增量。
@export var AttributeBonuses: Dictionary = {}

## 激活后提供的行为标签；移除套装效果时必须按同一列表撤销。
@export var GrantedTags: Array[StringName] = []
