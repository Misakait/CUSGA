@tool
extends EditorProperty

## 标签 Inspector 控件；所有写入通过 emit_changed 交给原生撤销重做。
## 不直接修改被编辑的 Resource，也不自动清除缺失或重复旧值。

var _monitor: RefCounted
var _multi: bool
var _option: OptionButton
var _menu: MenuButton
var _clear: Button
var _warning: Label
var _options: Array[StringName] = []
var _selected: Array[StringName] = []
var _raw: Variant
var _read_only: bool = false


## 参数 monitor：共享目录；参数 multi：是否编辑标签数组；返回值：无。
func _init(monitor: RefCounted, multi: bool) -> void:
	_monitor = monitor
	_multi = multi
	var content := VBoxContainer.new()
	content.name = "TagCatalogControls"
	add_child(content)
	set_bottom_editor(content)
	if multi:
		var row := HBoxContainer.new()
		content.add_child(row)
		_menu = MenuButton.new()
		_menu.name = "TagMultiSelect"
		_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_menu.get_popup().hide_on_checkable_item_selection = false
		_menu.get_popup().id_pressed.connect(_on_menu_selected)
		row.add_child(_menu)
		add_focusable(_menu)
		_clear = Button.new()
		_clear.name = "ClearTags"
		_clear.text = "清空"
		_clear.pressed.connect(_on_clear)
		row.add_child(_clear)
		add_focusable(_clear)
	else:
		_option = OptionButton.new()
		_option.name = "TagSingleSelect"
		_option.item_selected.connect(_on_single_selected)
		content.add_child(_option)
		add_focusable(_option)
	_warning = Label.new()
	_warning.name = "MissingTagsWarning"
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.add_theme_color_override("font_color", Color(1.0, 0.72, 0.25))
	content.add_child(_warning)


func _enter_tree() -> void:
	_monitor.options_changed.connect(refresh_options)


func _exit_tree() -> void:
	if _monitor.options_changed.is_connected(refresh_options):
		_monitor.options_changed.disconnect(refresh_options)


func _update_property() -> void:
	refresh_options()


func _set_read_only(read_only: bool) -> void:
	_read_only = read_only
	if _option != null:
		_option.disabled = read_only
	if _menu != null:
		_menu.disabled = read_only
		_clear.disabled = read_only


## 目录新增或删除后重建选项；保留资源当前值。
## 返回值：无；更新显示不会发出属性变更。
func refresh_options() -> void:
	var object: Object = get_edited_object()
	if object == null:
		return
	_raw = object.get(get_edited_property())
	_selected.clear()
	if _multi:
		for tag: Variant in _raw:
			_selected.append(StringName(tag))
	else:
		_selected.append(StringName(_raw))
	_options = _monitor.get_options()
	var displayed: Array[StringName] = _options.duplicate()
	var missing := PackedStringArray()
	for tag: StringName in _selected:
		if not _options.has(tag) and (_multi or not tag.is_empty()):
			if not displayed.has(tag):
				displayed.append(tag)
			if not missing.has(String(tag)):
				missing.append(String(tag))
	if _multi:
		_rebuild_menu(displayed)
	else:
		_rebuild_single(displayed)
	_warning.text = "未登记标签：%s。原值保留，可重新登记或主动移除。" % ", ".join(missing)
	_warning.visible = not missing.is_empty()


func _rebuild_single(displayed: Array[StringName]) -> void:
	_option.clear()
	_option.add_item("（无标签）")
	_option.set_item_metadata(0, &"")
	_option.select(0)
	for tag: StringName in displayed:
		if tag.is_empty():
			continue
		var index: int = _option.item_count
		_option.add_item(String(tag) if _options.has(tag) else "%s（未登记）" % tag)
		_option.set_item_metadata(index, tag)
		if _selected.has(tag):
			_option.select(index)


func _rebuild_menu(displayed: Array[StringName]) -> void:
	var popup: PopupMenu = _menu.get_popup()
	popup.clear()
	for tag: StringName in displayed:
		var index: int = popup.item_count
		popup.add_check_item(String(tag) if _options.has(tag) else "%s（未登记）" % tag, index)
		popup.set_item_metadata(index, tag)
		popup.set_item_checked(index, _selected.has(tag))
	_menu.text = "选择标签（%d）" % _selected.size()
	var names := PackedStringArray()
	for tag: StringName in _selected:
		names.append(String(tag))
	_menu.tooltip_text = ", ".join(names)
	_clear.disabled = _read_only or _selected.is_empty()


func _on_single_selected(index: int) -> void:
	if _read_only:
		return
	var tag: StringName = _option.get_item_metadata(index)
	# 不同资源可能声明 String；保留字段类型，防止存档协议被编辑器改写。
	var value: Variant = String(tag) if _raw is String else tag
	emit_changed(get_edited_property(), value)
	refresh_options()


func _on_menu_selected(id: int) -> void:
	if _read_only:
		return
	var popup: PopupMenu = _menu.get_popup()
	var index: int = popup.get_item_index(id)
	var tag: StringName = popup.get_item_metadata(index)
	var values: Array[StringName] = _selected.duplicate()
	if values.has(tag):
		# 明确取消勾选时清除该标识全部重复项；显示与刷新阶段不改旧数据。
		while values.has(tag):
			values.erase(tag)
	else:
		values.append(tag)
	_emit_array(values)


func _on_clear() -> void:
	if not _read_only:
		_emit_array([])


func _emit_array(values: Array[StringName]) -> void:
	var result: Variant
	if _raw is PackedStringArray:
		var packed := PackedStringArray()
		for tag: StringName in values:
			packed.append(String(tag))
		result = packed
	else:
		var array: Array = _raw.duplicate()
		array.clear()
		for tag: StringName in values:
			array.append(String(tag) if array.get_typed_builtin() == TYPE_STRING else tag)
		result = array
	emit_changed(get_edited_property(), result)
	# 多选菜单保持展开；原生 Inspector 延后刷新前，下一次点击也必须读取刚写回的值。
	refresh_options()
