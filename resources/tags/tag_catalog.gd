@tool
extends Resource
class_name TagCatalog

## 集中维护英文标签选项；只保存配置，不改变物品或玩家状态。
## 参数 Tags：允许字母开头、后续为英文字母、数字或下划线的标识。
## 返回值：通过 get_available_tags 返回去重选项，原始编辑值保留以便纠错。

## 使用原生数组编辑，编辑中的空项或非法项不会被自动删除。
@export var Tags: Array[StringName] = []:
	set(value):
		Tags = value
		emit_changed()


## 检查一个标识是否符合英文格式；大小写不作转换。
## 参数 tag：待检查标识。返回值：格式是否合法。
static func is_valid_tag(tag: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z][A-Za-z0-9_]*$")
	return pattern.search(tag) != null


## 取得有效且去重的选项，顺序沿用源数组。
## 返回值：英文标签数组；不修改原始 Tags。
func get_available_tags() -> Array[StringName]:
	var result: Array[StringName] = []
	for tag: StringName in Tags:
		if is_valid_tag(String(tag)) and not result.has(tag):
			result.append(tag)
	return result


## 列出空项、英文格式错误与重复项，供编辑器提示。
## 返回值：中文问题说明数组；空数组表示目录合法。
func get_validation_messages() -> PackedStringArray:
	var result := PackedStringArray()
	var seen: Array[StringName] = []
	for index: int in Tags.size():
		var tag: StringName = Tags[index]
		if not is_valid_tag(String(tag)):
			result.append("第 %d 项标签“%s”无效：请使用字母开头的英文、数字或下划线。" % [index, tag])
		elif seen.has(tag):
			result.append("第 %d 项标签“%s”重复，选择列表只显示一次。" % [index, tag])
		seen.append(tag)
	return result
