@tool
extends EditorInspectorPlugin

## 根据稳定字段名提供标签单选或多选；运行时仍读取原有字符串。

const PropertyEditor = preload("res://addons/tag_catalog/tag_property.gd")
const SINGLE_FIELDS: Array[StringName] = [&"TargetGatheringTag", &"GatheringTag", &"TriggerTag"]
const MULTI_FIELDS: Array[StringName] = [&"ItemTags", &"GrantedTags"]
var _monitor: RefCounted


## 参数 monitor：共享目录监视器；返回值：无。
func _init(monitor: RefCounted) -> void:
	_monitor = monitor


func _can_handle(object: Object) -> bool:
	return object is Resource


func _parse_begin(object: Object) -> void:
	# 源数组必须保留原生编辑；提示独立刷新，不能递归套用消费者选择器。
	if object == _monitor.catalog:
		var warning := CatalogWarning.new(_monitor)
		add_custom_control(warning)


func _parse_property(_object: Object, type: Variant.Type, name: String, _hint_type: PropertyHint, _hint_string: String, _usage_flags: int, _wide: bool) -> bool:
	var field := StringName(name)
	var multi: bool = MULTI_FIELDS.has(field)
	if not multi and not SINGLE_FIELDS.has(field):
		return false
	if multi and type not in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
		return false
	if not multi and type not in [TYPE_STRING_NAME, TYPE_STRING]:
		return false
	var editor := PropertyEditor.new(_monitor, multi)
	add_property_editor(name, editor)
	return true


## 标签源的格式与引用提示；绑定时读取当前状态，目录改变时更新。
class CatalogWarning extends Label:
	var _monitor: RefCounted

	## 参数 monitor：目录监视器；返回值：无。
	func _init(monitor: RefCounted) -> void:
		_monitor = monitor
		autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_theme_color_override("font_color", Color(1.0, 0.72, 0.25))


	func _enter_tree() -> void:
		_monitor.options_changed.connect(_refresh)
		_refresh()


	func _exit_tree() -> void:
		if _monitor.options_changed.is_connected(_refresh):
			_monitor.options_changed.disconnect(_refresh)


	func _refresh() -> void:
		text = _monitor.get_warning_text()
		visible = not text.is_empty()
