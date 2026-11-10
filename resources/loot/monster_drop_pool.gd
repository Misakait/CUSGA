@tool
extends Resource
class_name MonsterDropPool

## 怪物专用加权掉落池；每次抽取独立放回，空物品条目代表无掉落。
## 项目使用的物品堆叠脚本，保留装备实例属性生成协议。
const ITEM_STACK_SCRIPT: GDScript = preload("res://resources/item/item_stack.gd")

## 每只怪物死亡时独立抽取的次数；默认 5，0 表示不抽取。
@export_range(0, 1000, 1, "or_greater") var draw_count: int = 5
## 掉落候选列表；物品为空的有效权重代表“空”。
@export var entries: Array[MonsterDropEntry] = []

## 按正权重独立抽取，并为每次命中生成一个物品堆叠。
## 参数 _yield_growth：兼容怪物掉落组件的旧协议，不改变抽取次数或单次数量。
## 参数 rng：可注入随机数生成器；为空时使用游戏随机数。
## 返回值：非空结果组成的物品堆叠数组。
func RollLoot(_yield_growth: int = 0, rng: RandomNumberGenerator = null) -> Array[RefCounted]:
	var result: Array[RefCounted] = []
	var total_weight: int = 0
	for entry: MonsterDropEntry in entries:
		if entry != null and entry.drop_weight > 0:
			total_weight += entry.drop_weight
	if total_weight <= 0:
		return result
	for _draw_index in maxi(draw_count, 0):
		var roll: int = rng.randi_range(1, total_weight) if rng != null else randi_range(1, total_weight)
		for entry: MonsterDropEntry in entries:
			if entry == null or entry.drop_weight <= 0:
				continue
			roll -= entry.drop_weight
			if roll > 0:
				continue
			# 每次命中独立构造堆叠，以支持装备逐件生成不同实例属性。
			if entry.drop_item != null:
				var stack: RefCounted = ITEM_STACK_SCRIPT.new()
				stack.call("SetItem", entry.drop_item, 1)
				stack.call("RollRandomStats")
				result.append(stack)
			break
	return result
