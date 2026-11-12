@tool
extends Control

## 战斗内的怪物详情面板（只读）。
##
## 面板只负责展示：左侧是较窄的怪物信息列（名称、五行、生命、五项战斗属性），
## 右侧按 `MonsterSkillComponent.GetSkillPreviews()` 的顺序展示技能名称与描述。
## 数据权威仍留在怪物组件上，面板不解析技能池、不执行技能、不修改任何战斗数值。
##
## 打开期间不暂停战斗，因此生命值等运行时信息必须持续刷新；关闭、切换目标、
## 怪物死亡或战斗结束时统一走 `_shutdown_binding` 断开信号并清空引用。
##
## 输入契约：面板显示时会消费 `Esc`（`pause_game`），避免同一次按键继续传到
## 全局暂停菜单；面板自身不调用 `grab_focus`，否则聚焦的按钮会先吞掉 `ui_cancel`。

## 面板由隐藏切换为显示时发出。
signal PanelOpened

## 面板由显示切换为隐藏时发出；隐藏状态下重复关闭不会重复发出。
signal PanelClosed

## 暂停动作名；与 `core/ui/hud/pause_menu.gd` 使用同一动作。
const PAUSE_ACTION: StringName = &"pause_game"
## 没有可展示技能时的占位文本。
const EMPTY_SKILL_TEXT: String = "暂无可展示的技能"
## 怪物数据缺失时的名称占位。
const UNKNOWN_MONSTER_TEXT: String = "未知怪物"
## 属性或生命无法读取时的数值占位。
const MISSING_VALUE_TEXT: String = "--"
## 技能名称缺失时的占位。
const UNNAMED_SKILL_TEXT: String = "未命名技能"
## 技能描述缺失时的占位。
const EMPTY_DESCRIPTION_TEXT: String = "暂无描述"
## 左侧属性列展示的属性类型；顺序与怪物卡面一致（物攻/法强、物抗/法抗、速度）。
const ATTRIBUTE_TYPES: Array = [0, 2, 1, 3, 4]
## 与 `ATTRIBUTE_TYPES` 一一对应的中文标签。
const ATTRIBUTE_LABELS: Array = ["物攻", "法强", "物抗", "法抗", "速度"]

## 遮罩层；点击空白处关闭面板，同时拦截穿透到战斗卡牌。
@onready var _dimmer: ColorRect = %Dimmer
## 怪物名称。
@onready var _name_label: Label = %NameLabel
## 五行属性文本。
@onready var _element_label: Label = %ElementLabel
## 生命进度条。
@onready var _hp_bar: ProgressBar = %HpBar
## 当前/最大生命文本。
@onready var _hp_value_label: Label = %HpValueLabel
## 五项战斗属性的动态行容器。
@onready var _attribute_list: VBoxContainer = %AttributeList
## 技能条目的动态容器。
@onready var _skill_list: VBoxContainer = %SkillList
## 技能区滚动容器。
@onready var _skill_scroll: ScrollContainer = %SkillScroll
## 关闭按钮。
@onready var _close_button: Button = %CloseButton
## 详情主面板，用于鼠标事件拦截。
@onready var _detail_panel: PanelContainer = %DetailPanel

## 当前绑定的怪物；关闭或切换目标后清空。
var _monster: Node = null
## 当前绑定的生命组件。
var _health: Node = null
## 当前绑定的属性组件。
var _attributes: Node = null
## 面板是否处于显示状态；与 `visible` 同步，作为信号幂等的判断依据。
var _is_open: bool = false
## 生命值变化回调，保持稳定 Callable 以便精确断开。
var _health_value_changed_callable: Callable = Callable()
## 生命归零回调。
var _health_depleted_callable: Callable = Callable()
## 属性变化回调。
var _attributes_changed_callable: Callable = Callable()


## 初始化面板：默认隐藏、关闭按钮与遮罩接线、停止逐帧校验。
##
## @return 无返回值。
func _ready() -> void:
	hide()
	set_process(false)
	_close_button.pressed.connect(ClosePanel)
	_dimmer.gui_input.connect(_on_dimmer_gui_input)


## 打开面板并绑定怪物；已在显示时直接替换为新怪物的数据。
##
## 全屏遮罩会挡住其它怪物，因此正常交互是“先关闭再查看”；同一实例仍然支持
## 直接切换目标，用于测试与将来其它入口，不会叠加出第二个面板。
##
## @param monster 要查看的怪物实例。
## @return 无返回值。
func ShowMonster(monster: Node) -> void:
	if monster == null or not is_instance_valid(monster) or monster.is_queued_for_deletion():
		ClosePanel()
		return

	var was_open := _is_open
	# 先彻底清理旧绑定，确保同一帧内不会残留上一只怪物的行与信号。
	_shutdown_binding()

	_monster = monster
	_bind_monster()
	_apply_snapshot(BuildSnapshot(monster))

	show()
	set_process(true)
	_is_open = true
	if _skill_scroll != null:
		_skill_scroll.scroll_vertical = 0
	if not was_open:
		PanelOpened.emit()


## 关闭面板并清理引用、信号与动态行；隐藏状态下调用不产生副作用。
##
## @return 无返回值。
func ClosePanel() -> void:
	var was_open := _is_open
	_is_open = false
	_shutdown_binding()
	hide()
	set_process(false)
	if was_open:
		PanelClosed.emit()


## 查询面板当前是否显示。
##
## @return 显示时返回 true。
func IsPanelOpen() -> bool:
	return _is_open


## 构造只读展示快照；UI 与测试共用同一份数据口径。
##
## @param monster 目标怪物实例。
## @return 含 name/element_id/element_text/has_health/current_hp/max_hp/attributes/skills 的字典。
func BuildSnapshot(monster: Node) -> Dictionary:
	var snapshot: Dictionary = {
		"name": UNKNOWN_MONSTER_TEXT,
		"element_id": 0,
		"element_text": "无",
		"has_health": false,
		"current_hp": 0,
		"max_hp": 0,
		"attributes": _build_attribute_snapshot(monster),
		"skills": [],
	}
	if monster == null or not is_instance_valid(monster):
		return snapshot

	snapshot["name"] = _read_monster_name(monster)
	snapshot["element_id"] = _read_element_id(monster)
	snapshot["element_text"] = _resolve_element_text(monster, int(snapshot["element_id"]))

	var health: Node = _resolve_component(monster, "Health")
	if health != null:
		var current_value: Variant = _read_int_field(health, "CurrentValue")
		var max_value: Variant = _read_int_field(health, "MaxValue")
		if current_value != null and max_value != null:
			snapshot["has_health"] = true
			snapshot["current_hp"] = int(current_value)
			snapshot["max_hp"] = int(max_value)

	snapshot["skills"] = _build_skill_snapshot(monster)
	return snapshot


## 只在面板显示时处理 Esc；消费事件以阻止同一次按键打开暂停菜单。
##
## @param event 当前分发的输入事件。
## @return 无返回值。
func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if not _is_pause_intent(event):
		return

	ClosePanel()
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


## 面板显示期间检查绑定怪物是否已失效；死亡、释放或场景拆除都由此统一兜底。
##
## @param _delta 距上一帧的时间，本流程不需要。
## @return 无返回值。
func _process(_delta: float) -> void:
	if not _is_open:
		return
	# 先判有效性，再访问成员；已释放的对象直接访问会触发失效引用错误。
	if not is_instance_valid(_monster):
		ClosePanel()
		return
	if _monster.is_queued_for_deletion():
		ClosePanel()


## 退出场景树时只清理引用与信号，不再广播关闭事件，避免宿主已在拆除中。
##
## @return 无返回值。
func _exit_tree() -> void:
	_is_open = false
	_shutdown_binding()


## 遮罩空白处的左键点击只关闭面板，不继续传递给战斗。
##
## @param event 遮罩收到的 GUI 事件。
## @return 无返回值。
func _on_dimmer_gui_input(event: InputEvent) -> void:
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	ClosePanel()
	accept_event()


## 绑定怪物的生命与属性组件，重复调用会先断开旧连接。
##
## @return 无返回值。
func _bind_monster() -> void:
	_health = _resolve_component(_monster, "Health")
	if _health != null:
		_health_value_changed_callable = Callable(self, "_on_health_value_changed")
		_health_depleted_callable = Callable(self, "_on_health_depleted")
		if _health.has_signal("ValueChanged") and not _health.is_connected("ValueChanged", _health_value_changed_callable):
			_health.connect("ValueChanged", _health_value_changed_callable)
		if _health.has_signal("Depleted") and not _health.is_connected("Depleted", _health_depleted_callable):
			_health.connect("Depleted", _health_depleted_callable)

	_attributes = _resolve_component(_monster, "Attributes")
	if _attributes != null:
		_attributes_changed_callable = Callable(self, "_on_attributes_changed")
		if _attributes.has_signal("AttributeChanged") and not _attributes.is_connected("AttributeChanged", _attributes_changed_callable):
			_attributes.connect("AttributeChanged", _attributes_changed_callable)


## 断开生命与属性信号并把缓存引用、动态行全部清空。
##
## @return 无返回值。
func _shutdown_binding() -> void:
	if _health != null and is_instance_valid(_health):
		if _health_value_changed_callable.is_valid() and _health.is_connected("ValueChanged", _health_value_changed_callable):
			_health.disconnect("ValueChanged", _health_value_changed_callable)
		if _health_depleted_callable.is_valid() and _health.is_connected("Depleted", _health_depleted_callable):
			_health.disconnect("Depleted", _health_depleted_callable)

	if _attributes != null and is_instance_valid(_attributes):
		if _attributes_changed_callable.is_valid() and _attributes.is_connected("AttributeChanged", _attributes_changed_callable):
			_attributes.disconnect("AttributeChanged", _attributes_changed_callable)

	_health = null
	_attributes = null
	_health_value_changed_callable = Callable()
	_health_depleted_callable = Callable()
	_attributes_changed_callable = Callable()
	_monster = null
	_clear_children(_attribute_list)
	_clear_children(_skill_list)


## 把快照写入界面。
##
## @param snapshot `BuildSnapshot` 的返回值。
## @return 无返回值。
func _apply_snapshot(snapshot: Dictionary) -> void:
	_name_label.text = String(snapshot.get("name", UNKNOWN_MONSTER_TEXT))
	_element_label.text = "五行: %s" % String(snapshot.get("element_text", "无"))
	_update_health_display(
		bool(snapshot.get("has_health", false)),
		int(snapshot.get("current_hp", 0)),
		int(snapshot.get("max_hp", 0))
	)
	_rebuild_attribute_rows(snapshot.get("attributes", []))
	_rebuild_skill_entries(snapshot.get("skills", []))


## 刷新生命条与生命文本。
##
## @param has_health 是否能读取生命组件。
## @param current_hp 当前生命值。
## @param max_hp 最大生命值。
## @return 无返回值。
func _update_health_display(has_health: bool, current_hp: int, max_hp: int) -> void:
	if not has_health:
		_hp_bar.max_value = 1.0
		_hp_bar.value = 0.0
		_hp_value_label.text = "%s / %s" % [MISSING_VALUE_TEXT, MISSING_VALUE_TEXT]
		return

	_hp_bar.max_value = float(maxi(1, max_hp))
	_hp_bar.value = float(clampi(current_hp, 0, maxi(1, max_hp)))
	_hp_value_label.text = "%d / %d" % [current_hp, max_hp]


## 重建左侧五项属性行。
##
## @param rows `BuildSnapshot` 产出的属性行数组。
## @return 无返回值。
func _rebuild_attribute_rows(rows: Variant) -> void:
	_clear_children(_attribute_list)
	if typeof(rows) != TYPE_ARRAY:
		return

	for row: Variant in (rows as Array):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var dictionary: Dictionary = row
		var line: HBoxContainer = HBoxContainer.new()
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_label: Label = Label.new()
		name_label.text = String(dictionary.get("label", ""))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 18)
		line.add_child(name_label)

		var value_label: Label = Label.new()
		value_label.text = String(dictionary.get("value", MISSING_VALUE_TEXT))
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.52, 1.0))
		line.add_child(value_label)

		_attribute_list.add_child(line)


## 重建右侧技能条目：名称、自动换行描述、条目之间的分割线。
##
## @param skills `BuildSnapshot` 产出的技能数组。
## @return 无返回值。
func _rebuild_skill_entries(skills: Variant) -> void:
	_clear_children(_skill_list)
	var entries: Array = skills as Array if typeof(skills) == TYPE_ARRAY else []

	if entries.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = EMPTY_SKILL_TEXT
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty_label.add_theme_color_override("font_color", Color(0.70, 0.72, 0.78, 1.0))
		_skill_list.add_child(empty_label)
		return

	for index: int in range(entries.size()):
		var entry: Dictionary = entries[index]
		var name_label: Label = Label.new()
		name_label.text = String(entry.get("name", UNNAMED_SKILL_TEXT))
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 22)
		name_label.add_theme_color_override("font_color", Color(0.98, 0.86, 0.55, 1.0))
		_skill_list.add_child(name_label)

		var description_label: Label = Label.new()
		description_label.text = String(entry.get("description", EMPTY_DESCRIPTION_TEXT))
		# 描述必须自动换行：右列宽度由容器决定，长描述不能撑出面板。
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_skill_list.add_child(description_label)

		# 只在技能之间插入分割线，最后一项之后不再追加。
		if index < entries.size() - 1:
			var separator: HSeparator = HSeparator.new()
			separator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_skill_list.add_child(separator)


## 读取怪物名称，字段缺失或为空时回退占位文本。
##
## @param monster 目标怪物实例。
## @return 用于展示的名称。
func _read_monster_name(monster: Node) -> String:
	var base_data: Resource = monster.get("BaseData") as Resource
	if base_data == null:
		return UNKNOWN_MONSTER_TEXT

	var raw_name: Variant = base_data.get("MonsterName")
	if typeof(raw_name) != TYPE_STRING:
		return UNKNOWN_MONSTER_TEXT

	var display_name: String = String(raw_name).strip_edges()
	return display_name if not display_name.is_empty() else UNKNOWN_MONSTER_TEXT


## 读取五行枚举值。
##
## @param monster 目标怪物实例。
## @return 与 ElementType 一致的整数；读取失败时返回 0。
func _read_element_id(monster: Node) -> int:
	var base_data: Resource = monster.get("BaseData") as Resource
	if base_data == null:
		return 0

	var raw_element: Variant = base_data.get("ElementalProperty")
	if typeof(raw_element) != TYPE_INT:
		return 0

	return int(raw_element)


## 通过怪物的公开映射把五行枚举翻成文本，避免面板复制一份映射表。
##
## @param monster 目标怪物实例。
## @param element_id 五行枚举值。
## @return 木/金/水/土/火/无。
func _resolve_element_text(monster: Node, element_id: int) -> String:
	if monster != null and is_instance_valid(monster) and monster.has_method("GetElementDisplayName"):
		return String(monster.call("GetElementDisplayName", element_id))

	return "无"


## 构造五项战斗属性行；属性组件缺失或读取失败时用占位文本。
##
## @param monster 目标怪物实例，允许为 null。
## @return 每项含 type/label/value 的数组。
func _build_attribute_snapshot(monster: Node) -> Array:
	var rows: Array = []
	var attributes: Node = _resolve_component(monster, "Attributes")

	for index: int in range(ATTRIBUTE_TYPES.size()):
		var row: Dictionary = {
			"type": int(ATTRIBUTE_TYPES[index]),
			"label": String(ATTRIBUTE_LABELS[index]),
			"value": MISSING_VALUE_TEXT,
		}
		if attributes != null and attributes.has_method("GetEffectiveValue"):
			var raw_value: Variant = attributes.call("GetEffectiveValue", int(ATTRIBUTE_TYPES[index]))
			if raw_value != null and typeof(raw_value) in [TYPE_INT, TYPE_FLOAT]:
				# 与怪物卡面保持同样的整数显示口径，避免面板与卡面出现不同的小数。
				row["value"] = str(roundi(float(raw_value)))
		rows.append(row)

	return rows


## 按技能组件返回的预览顺序构造技能条目。
##
## 可见性、描述覆盖与排序全部由 `GetSkillPreviews()` 负责，面板只负责读取与降级。
##
## @param monster 目标怪物实例。
## @return 每项含 name/description 的数组；没有可展示技能时为空数组。
func _build_skill_snapshot(monster: Node) -> Array:
	var rows: Array = []
	var skill_component: Node = _resolve_component(monster, "SkillComponent")
	if skill_component == null or not skill_component.has_method("GetSkillPreviews"):
		return rows

	var raw_previews: Variant = skill_component.call("GetSkillPreviews")
	if typeof(raw_previews) != TYPE_ARRAY:
		return rows

	for value: Variant in (raw_previews as Array):
		if value == null:
			continue

		var display_name: String = ""
		var description: String = ""
		if value is Object:
			var raw_name: Variant = (value as Object).get("DisplayName")
			if typeof(raw_name) == TYPE_STRING:
				display_name = String(raw_name).strip_edges()
			var raw_description: Variant = (value as Object).get("Description")
			if typeof(raw_description) == TYPE_STRING:
				description = String(raw_description).strip_edges()

		rows.append({
			"name": display_name if not display_name.is_empty() else UNNAMED_SKILL_TEXT,
			"description": description if not description.is_empty() else EMPTY_DESCRIPTION_TEXT,
		})

	return rows


## 读取怪物身上的组件引用。
##
## @param monster 目标怪物实例，允许为 null。
## @param property_name 组件属性名（Health / Attributes / SkillComponent）。
## @return 组件节点；缺失或不可用时返回 null。
func _resolve_component(monster: Node, property_name: String) -> Node:
	if monster == null or not is_instance_valid(monster):
		return null

	var value: Variant = monster.get(property_name)
	if value is Node and is_instance_valid(value):
		return value as Node

	return null


## 读取组件上的整数字段。
##
## @param node 组件节点。
## @param field_name 字段名。
## @return 字段值；类型不符或缺失时返回 null。
func _read_int_field(node: Node, field_name: String) -> Variant:
	var value: Variant = node.get(field_name)
	if typeof(value) == TYPE_INT:
		return int(value)

	return null


## 生命值变化时只刷新生命区，不重建技能列表。
##
## @param current_value 当前生命值。
## @param max_value 最大生命值。
## @return 无返回值。
func _on_health_value_changed(current_value: int, max_value: int) -> void:
	_update_health_display(true, current_value, max_value)


## 生命归零时立即关闭面板；逐帧校验仍作为释放路径的兜底。
##
## @return 无返回值。
func _on_health_depleted() -> void:
	if _is_open:
		ClosePanel()


## 属性变化时按最新有效值重刷五行行。
##
## @param _event 属性系统提供的变化事件，本流程不需要。
## @return 无返回值。
func _on_attributes_changed(_event: Variant) -> void:
	if not _is_open or _monster == null or not is_instance_valid(_monster):
		return

	_rebuild_attribute_rows(_build_attribute_snapshot(_monster))


## 判断事件是否为一次“关闭意图”的暂停输入。
##
## @param event 待检查的输入事件。
## @return 首次按下的 `pause_game` 或 Esc 返回 true。
func _is_pause_intent(event: InputEvent) -> bool:
	if InputMap.has_action(PAUSE_ACTION) and event.is_action_pressed(PAUSE_ACTION):
		return true

	var key_event: InputEventKey = event as InputEventKey
	if key_event == null:
		return false
	if not key_event.pressed or key_event.echo:
		return false

	return key_event.keycode == KEY_ESCAPE


## 移除容器下的全部动态节点：先脱离树再释放，保证同一帧内不残留旧行。
##
## @param container 目标容器，允许为 null。
## @return 无返回值。
func _clear_children(container: Node) -> void:
	if container == null:
		return

	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
