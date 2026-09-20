extends Resource

## 描述采集指定资源标签时可能触发的怪物遭遇规则。
##
## 该资源只保存策划配置；遭遇概率的时间、装备和随机结算仍由
## EncounterManager 负责，便于 C# 与 GDScript 规则在迁移期间并存。

## 触发条件：当前采集资源的标签。
@export var TriggerTag: StringName = &""

## 触发后生成的怪物列表。
@export var MonsterToSpawn: Array[Resource] = []

## 触发时显示给玩家的提示语。
@export_multiline var SpawnMessage: String = "糟糕！采集物变成了怪物！"

## 应用于基础采集遭遇概率的附加倍率。
@export var ExtraChanceMultiplier: float = 1.0
