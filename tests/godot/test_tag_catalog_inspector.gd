@tool
extends McpTestSuite

## 在真实 EditorInspector 中验证目录刷新、写回与撤销重做。

const Catalog = preload("res://resources/tags/tag_catalog.gd")
const Monitor = preload("res://addons/tag_catalog/catalog_monitor.gd")
const InspectorPlugin = preload("res://addons/tag_catalog/tag_inspector.gd")
const PropertyEditor = preload("res://addons/tag_catalog/tag_property.gd")

var _catalog: Resource
var _monitor: RefCounted
var _plugin: EditorPlugin
var _inspector_plugin: EditorInspectorPlugin
var _fixture: Resource
var _previous_object: Object


## 参数与生产消费者一致的测试配置，避免写入真实物品资源。
class TagFixture extends Resource:
	@export var ItemTags: Array[StringName] = []
	@export var GrantedTags: Array[StringName] = []
	@export var TargetGatheringTag: StringName = &""
	@export var GatheringTag: StringName = &""
	@export var TriggerTag: StringName = &""


## 返回供编辑器筛选的套件名。
## 返回值：真实标签 Inspector 测试套件名。
func suite_name() -> String:
	return "tag_catalog_inspector"


## 建立临时目录与真实检查器扩展；不保存生产资产。
## 返回值：无。
func setup() -> void:
	_previous_object = EditorInterface.get_inspector().get_edited_object()
	_catalog = Catalog.new()
	_catalog.set("Tags", [&"wood", &"MagicItem"] as Array[StringName])
	_monitor = Monitor.new(_catalog)
	_inspector_plugin = InspectorPlugin.new(_monitor)
	_plugin = EditorPlugin.new()
	EditorInterface.get_base_control().add_child(_plugin)
	_plugin.add_inspector_plugin(_inspector_plugin)
	_fixture = TagFixture.new()
	# 直接使用 Inspector，避免编辑内嵌测试类时编辑器尝试打开不存在的脚本路径。
	EditorInterface.get_inspector().edit(_fixture)


## 移除临时插件并恢复用户正在查看的对象。
## 返回值：无。
func teardown() -> void:
	_plugin.remove_inspector_plugin(_inspector_plugin)
	if is_instance_valid(_previous_object):
		EditorInterface.get_inspector().edit(_previous_object)
	else:
		EditorInterface.get_inspector().edit(null)
	_plugin.free()
	_inspector_plugin = null
	_fixture = null
	_monitor.dispose()
	_monitor = null
	_catalog = null


## 验证一个活着的选择器在目录新增后出现选项，单选写回后可撤销重做。
## 返回值：无。
func test_live_single_refresh_writeback_and_undo() -> void:
	_refresh_inspector()
	var editor: EditorProperty = _find_editor(&"GatheringTag")
	assert_true(editor != null, "GatheringTag 必须使用真正的标签 Inspector。")
	if editor == null:
		return
	var control: OptionButton = editor.find_child("TagSingleSelect", true, false) as OptionButton
	assert_true(control != null, "单标签必须提供下拉选择控件。")
	_catalog.Tags.append(&"new_resource_tag")
	_monitor.refresh()
	var index: int = _find_option(control, &"new_resource_tag")
	assert_true(index >= 0, "目录新增后活着的下拉框必须自动出现新标签。")
	if index < 0:
		return
	control.item_selected.emit(index)
	assert_eq(_fixture.get("GatheringTag"), &"new_resource_tag", "选择必须经 Inspector 写回原字段。")
	var history_id: int = _plugin.get_undo_redo().get_object_history_id(_fixture)
	var history: UndoRedo = _plugin.get_undo_redo().get_history_undo_redo(history_id)
	assert_true(history.has_undo(), "emit_changed 必须形成原生撤销记录。")
	history.undo()
	assert_eq(_fixture.get("GatheringTag"), &"", "撤销必须恢复旧值。")
	history.redo()
	assert_eq(_fixture.get("GatheringTag"), &"new_resource_tag", "重做必须恢复所选英文标签。")


## 验证多标签增加、移除和清空，以及旧未登记值不被刷新清除。
## 返回值：无。
func test_multi_select_and_missing_value_retention() -> void:
	_fixture.set("ItemTags", [&"old_missing_tag"] as Array[StringName])
	_refresh_inspector()
	var editor: EditorProperty = _find_editor(&"ItemTags")
	assert_true(editor != null, "物品标签数组必须使用多选控件。")
	if editor == null:
		return
	editor.call("refresh_options")
	var menu: MenuButton = editor.find_child("TagMultiSelect", true, false) as MenuButton
	var warning: Label = editor.find_child("MissingTagsWarning", true, false) as Label
	assert_true(warning.visible and warning.text.contains("old_missing_tag"), "未登记标签必须明确提示。")
	assert_eq(_fixture.get("ItemTags"), [&"old_missing_tag"], "仅显示和刷新不得清空旧值。")
	var popup: PopupMenu = menu.get_popup()
	popup.id_pressed.emit(_find_menu_id(popup, &"wood"))
	assert_eq(_fixture.get("ItemTags"), [&"old_missing_tag", &"wood"], "增加新标签必须保留已有未登记标签和数组顺序。")
	assert_true((_fixture.get("ItemTags") as Array).get_typed_builtin() == TYPE_STRING_NAME, "数组必须保持 StringName 元素类型。")
	_refresh_inspector()
	editor = _find_editor(&"ItemTags")
	editor.call("refresh_options")
	menu = editor.find_child("TagMultiSelect", true, false) as MenuButton
	popup = menu.get_popup()
	popup.id_pressed.emit(_find_menu_id(popup, &"wood"))
	assert_eq(_fixture.get("ItemTags"), [&"old_missing_tag"], "取消勾选必须只移除对应标签。")
	_refresh_inspector()
	editor = _find_editor(&"ItemTags")
	var clear: Button = editor.find_child("ClearTags", true, false) as Button
	clear.pressed.emit()
	assert_true((_fixture.get("ItemTags") as Array).is_empty(), "明确清空操作必须写入空数组。")


## 验证所有指定字段都有选择器，源目录 Tags 继续使用原生数组。
## 返回值：无。
func test_supported_fields_and_native_catalog_array() -> void:
	_refresh_inspector()
	for name: StringName in [&"ItemTags", &"GrantedTags", &"TargetGatheringTag", &"GatheringTag", &"TriggerTag"]:
		assert_true(_find_editor(name) != null, "%s 必须从同一标签源选择。" % name)
	EditorInterface.get_inspector().edit(_catalog)
	_refresh_inspector()
	assert_true(_find_editor(&"Tags") == null, "源目录必须使用原生数组编辑，不能套用消费者多选。")


## 验证删除生产标签能显示真实资产路径，且不会清空已选字段。
## 返回值：无。
func test_removal_warning_scans_real_asset_references() -> void:
	_fixture.set("GatheringTag", &"wood")
	_refresh_inspector()
	_catalog.Tags.erase(&"wood")
	_monitor.refresh()
	assert_true(_monitor.get_warning_text().contains("res://"), "删除已引用标签必须提供真实资源引用路径。")
	assert_eq(_fixture.get("GatheringTag"), &"wood", "删除源选项不得改写消费者。")
	var editor: EditorProperty = _find_editor(&"GatheringTag")
	var warning: Label = editor.find_child("MissingTagsWarning", true, false) as Label
	assert_true(warning.visible and warning.text.contains("wood"), "被删除旧值必须显示未登记提示。")


## 验证项目实际启用的插件提供选择器，避免只测临时注入的测试实例。
## 返回值：无；测试结束恢复临时插件。
func test_project_plugin_is_active() -> void:
	_plugin.remove_inspector_plugin(_inspector_plugin)
	# 正在运行的编辑器不会因外部文本改动自动加载新插件；使用原生启用入口即时生效。
	# 此操作只启用本任务插件，保留项目已有扩展，且无需用户重启编辑器。
	if not EditorInterface.is_plugin_enabled("tag_catalog"):
		EditorInterface.set_plugin_enabled("tag_catalog", true)
	assert_true(EditorInterface.is_plugin_enabled("tag_catalog"), "正式插件必须在当前编辑器真正启用。")
	var item := ItemData.new()
	EditorInterface.get_inspector().edit(item)
	_refresh_inspector()
	var editor: EditorProperty = _find_editor(&"ItemTags")
	assert_true(editor != null, "项目已启用的真实标签插件必须提供 ItemTags 选择器。")
	if editor != null:
		var live_catalog: Resource = load(Monitor.CATALOG_PATH)
		var original: Array[StringName] = live_catalog.get("Tags").duplicate()
		var modified: Array[StringName] = original.duplicate()
		modified.append(&"CatalogRuntimeProbeTag")
		# 只修改缓存 Resource 并立即恢复，不保存文件；验证正式目录刷新正式控件。
		live_catalog.set("Tags", modified)
		var menu: MenuButton = editor.find_child("TagMultiSelect", true, false) as MenuButton
		assert_true(_find_menu_id(menu.get_popup(), &"CatalogRuntimeProbeTag") >= 0, "唯一标签源新增英文值后，正式插件中活着的控件必须立即可选。")
		live_catalog.set("Tags", original)
	_plugin.add_inspector_plugin(_inspector_plugin)


func _refresh_inspector() -> void:
	# MCP 测试运行器同步调用 test_*；不能用 await 使测试正文提前结束。
	# 直接交给原生 Inspector 重新编辑，确保这里检查真实控件而不是伪造属性。
	var inspector: EditorInspector = EditorInterface.get_inspector()
	var object: Object = inspector.get_edited_object()
	inspector.edit(null)
	inspector.edit(object)


func _find_editor(field: StringName) -> EditorProperty:
	return _find_in_node(EditorInterface.get_inspector(), field)


func _find_in_node(node: Node, field: StringName) -> EditorProperty:
	if node is EditorProperty and node.get_script() == PropertyEditor and node.get_edited_property() == field:
		return node as EditorProperty
	for child: Node in node.get_children():
		var found: EditorProperty = _find_in_node(child, field)
		if found != null:
			return found
	return null


func _find_option(control: OptionButton, tag: StringName) -> int:
	for index: int in control.item_count:
		if control.get_item_metadata(index) == tag:
			return index
	return -1


func _find_menu_id(popup: PopupMenu, tag: StringName) -> int:
	for index: int in popup.item_count:
		if popup.get_item_metadata(index) == tag:
			return popup.get_item_id(index)
	return -1
