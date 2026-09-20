extends Node

## 实体标签叠层组件的并行 GDScript 实现。
##
## 标签由天赋、装备和状态系统增减；组件只维护层数，不解释标签的玩法含义。

## 当前生效标签及其正整数层数，键为 StringName。
var _active_tags: Dictionary = {}


## 为指定标签增加一层。
## 参数 tag：需要增加的标签；空标签会被忽略。
## 返回值：无。
func AddTag(tag: StringName) -> void:
	if tag.is_empty():
		return
	## 增加后的标签层数。
	var next_stack: int = int(_active_tags.get(tag, 0)) + 1
	_active_tags[tag] = next_stack
	print("[标签系统] 获得标签 %s，当前层数：%d" % [tag, next_stack])


## 为指定标签移除一层，归零时删除标签。
## 参数 tag：需要移除的标签；空标签或不存在的标签会被忽略。
## 返回值：无。
func RemoveTag(tag: StringName) -> void:
	if tag.is_empty() or not _active_tags.has(tag):
		return
	## 移除一层后的标签层数。
	var next_stack: int = int(_active_tags[tag]) - 1
	_active_tags[tag] = next_stack
	print("[标签系统] 移除标签 %s，当前层数：%d" % [tag, next_stack])
	if next_stack <= 0:
		_active_tags.erase(tag)
		print("[标签系统] 标签 %s 已彻底失效！" % tag)


## 查询标签当前是否至少有一层。
## 参数 tag：需要查询的标签。
## 返回值：标签存在时返回 true，否则返回 false。
func HasTag(tag: StringName) -> bool:
	return _active_tags.has(tag)


## 查询标签当前层数。
## 参数 tag：需要查询的标签。
## 返回值：当前层数；标签不存在时返回 0。
func GetTagStack(tag: StringName) -> int:
	return int(_active_tags.get(tag, 0))
