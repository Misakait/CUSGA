@tool
extends RefCounted

## 协调标签目录变化和编辑器提示；不参与运行时玩法。
## 参数构造器可传入独立目录供测试；默认使用唯一生产目录。

signal options_changed

const CATALOG_PATH: String = "res://resources/tags/default_tag_catalog.tres"
const Scanner = preload("res://addons/tag_catalog/reference_scanner.gd")

var catalog: Resource
var removal_messages := PackedStringArray()
var _fingerprint: String = ""
var _previous_tags: Array[StringName] = []


func _init(source: Resource = null) -> void:
	catalog = source if source != null else load(CATALOG_PATH)
	if catalog != null:
		catalog.changed.connect(refresh)
	refresh()


## 停止监听标签源；插件退出时释放信号关系，避免旧监视器继续参与刷新。
## 参数：无。返回值：无；允许重复清理。
func dispose() -> void:
	if catalog != null and catalog.changed.is_connected(refresh):
		catalog.changed.disconnect(refresh)


## 获取当前目录有效选项。
## 返回值：去重英文标签数组；目录无效时返回空数组。
func get_options() -> Array[StringName]:
	if catalog == null:
		return []
	return catalog.get_available_tags()


## 检查目录变化，刷新所有活着的选择器并检查删除项实际引用。
## 返回值：无；仅在内容确实改变时发送 options_changed。
func refresh() -> void:
	if catalog == null:
		return
	var signature: String = var_to_str(catalog.get("Tags"))
	if signature == _fingerprint:
		return
	var available: Array[StringName] = get_options()
	var removed: Array[StringName] = []
	for tag: StringName in _previous_tags:
		if not available.has(tag):
			removed.append(tag)
	if not removed.is_empty():
		var references: Dictionary = Scanner.find_references(removed)
		for tag: StringName in removed:
			var locations: PackedStringArray = references.get(tag, PackedStringArray())
			if not locations.is_empty():
				removal_messages.append("已删除标签 %s 仍有 %d 处资源引用；原字段保留。\n%s" % [tag, locations.size(), "\n".join(locations)])
	# 撤销删除后对应提示也应消失，而不是残留过期警告。
	for index: int in range(removal_messages.size() - 1, -1, -1):
		for tag: StringName in available:
			if removal_messages[index].begins_with("已删除标签 %s " % tag):
				removal_messages.remove_at(index)
				break
	_fingerprint = signature
	_previous_tags = available.duplicate()
	options_changed.emit()


## 返回目录格式与实际删除引用的中文说明。
## 返回值：完整提示；没有问题时返回空字符串。
func get_warning_text() -> String:
	var messages: PackedStringArray = removal_messages.duplicate()
	if catalog == null:
		messages.append("无法加载英文标签源：%s" % CATALOG_PATH)
	else:
		messages.append_array(catalog.get_validation_messages())
	return "\n".join(messages)
