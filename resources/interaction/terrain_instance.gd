extends RefCounted

## 房间内地形卡实例的 GDScript 生产实现，等价迁移自 TerrainInstance.cs。
##
## 只保存单个地形的运行时状态与遭遇浮动倍率，不复制房间缓存、棋盘卡集合或玩法规则。
## 字段名与旧 C# 属性逐字一致，因此 C# 消费者可以继续用同一套字段协议读写，
## 无需为两种实现维护两套语义。

## 地形在当前房间局部网格中的位置。
var LocalGridPos: Vector2i = Vector2i.ZERO

## 地形卡在棋盘上的显示位置。
var BoardPosition: Vector2 = Vector2.ZERO

## 该实例使用的地形配置资源。
var TerrainData: Resource = null

## 该地形是否被其它玩法占用。
var IsOccupied: bool = false

## 旧一次性采集点是否已经被采集。
var IsHarvested: bool = false

## 农场等成长型地形的成长阶段。
var GrowthStage: int = 0

## 可重复采集资源当前剩余采集次数；-1 表示尚未按资源配置初始化。
var RemainingGatheringCount: int = -1

## 可重复采集资源下一次恢复可采集的游戏总时间；0 表示当前没有冷却。
var RefreshReadyTotalTime: int = 0

## 遭遇浮动倍率。
##
## 旧实现的 EncounterVarianceMultiplier 是普通 C# 类 MonsterStatMultiplier，不是
## Godot Object，无法跨语言保存；这里沿用既有的字典协议，字段名与顺序和旧类完全一致，
## 保证 GDScript 与 C# 读取到同一份数值。
var EncounterVarianceMultiplier: Dictionary = {
	"MaxHealth": 1.0,
	"PhysAtk": 1.0,
	"PhysDef": 1.0,
	"MagPower": 1.0,
	"MagResist": 1.0,
	"Speed": 1.0,
}

## 浮动倍率字段名，顺序与旧 C# MonsterStatMultiplier 的构造顺序一致。
const VARIANCE_FIELDS: Array[StringName] = [
	&"MaxHealth",
	&"PhysAtk",
	&"PhysDef",
	&"MagPower",
	&"MagResist",
	&"Speed",
]


## 提供地形浮动倍率的稳定只读快照。
##
## @return 含六个倍率字段的字典；倍率缺失或类型不符时按中性值 1 输出。
func GetEncounterVarianceSnapshot() -> Dictionary:
	return _normalize_multiplier(EncounterVarianceMultiplier)


## 接收浮动倍率字典并写回运行时状态。
##
## 与 GetEncounterVarianceSnapshot 对称，供房间布局生成器写入同一份数值；
## 非字典输入会被忽略，字段缺失或类型不符时按中性值 1 处理。
##
## @param snapshot 含六个倍率字段的字典。
## @return 无。
func ApplyEncounterVarianceSnapshot(snapshot: Variant) -> void:
	if not (snapshot is Dictionary):
		return
	EncounterVarianceMultiplier = _normalize_multiplier(snapshot)


## 把任意输入整理为完整的六字段倍率字典。
##
## @param source 倍率来源，允许为字典或其它类型。
## @return 六个字段齐全的倍率字典，缺失与非法字段一律取中性值 1。
func _normalize_multiplier(source: Variant) -> Dictionary:
	var normalized: Dictionary = {}
	var values: Dictionary = source if source is Dictionary else {}
	for field: StringName in VARIANCE_FIELDS:
		var value: Variant = values.get(field, 1.0)
		if value is int or value is float:
			normalized[field] = float(value)
		else:
			normalized[field] = 1.0
	return normalized
