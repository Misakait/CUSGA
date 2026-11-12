@tool
extends McpTestSuite

## 战斗中怪物详情面板的契约套件。
##
## 覆盖技能预览顺序/隐藏/描述回退、缺失数据降级、单实例切换、关闭与信号清理、
## 怪物释放后的自动关闭、Esc 消费，以及 battle.tscn 的宿主层级装配。

## 待验证的面板场景。
const PANEL_SCENE: PackedScene = preload("res://scenes/battle_scenes/monster_detail_panel.tscn")
## 待验证的战斗场景，只读取打包状态，不实例化。
const BATTLE_SCENE_PATH: String = "res://scenes/battle_scenes/battle.tscn"
## 怪物数据脚本。
const MONSTER_DATA_SCRIPT: GDScript = preload("res://resources/monster/monster_data.gd")
## 技能条目脚本。
const SKILL_ENTRY_SCRIPT: GDScript = preload("res://resources/monster/monster_skill_entry_data.gd")
## 怪物技能组件脚本。
const SKILL_COMPONENT_SCRIPT: GDScript = preload("res://entities/components/monster_skill_component.gd")

## 面板显示时由隐藏切换为显示的计数回调。
var _opened_count: Dictionary = {"value": 0}
## 面板关闭的计数回调。
var _closed_count: Dictionary = {"value": 0}


## 返回 GodotAI 使用的稳定套件名称。
## 返回值：怪物详情面板契约套件名。
func suite_name() -> String:
	return "battle_monster_detail_panel_contract"


## 提供 BaseData/Health/Attributes/SkillComponent 四个稳定属性的最小怪物。
class FakeMonster extends Node:
	## 怪物配置数据。
	var BaseData: Resource = null
	## 生命组件。
	var Health: Node = null
	## 属性组件。
	var Attributes: Node = null
	## 技能组件。
	var SkillComponent: Node = null

	## 复刻怪物公开的五行映射，验证面板确实走怪物侧接口而不是自建映射表。
	## 参数 element：五行枚举值。
	## 返回值：木/金/水/土/火/无。
	func GetElementDisplayName(element: int) -> String:
		match element:
			1:
				return "木"
			2:
				return "金"
			3:
				return "水"
			4:
				return "土"
			5:
				return "火"
			_:
				return "无"


## 带 ValueChanged/Depleted 的最小生命组件。
class FakeHealth extends Node:
	## 当前值或上限变化。
	signal ValueChanged(current_value, max_value)
	## 当前值归零。
	signal Depleted

	## 当前生命值。
	var CurrentValue: int = 0
	## 最大生命值。
	var MaxValue: int = 100

	## 写入快照并广播。
	## 参数 current_value：新的当前值。
	## 参数 max_value：新的上限。
	## 返回值：无。
	func set_values(current_value: int, max_value: int) -> void:
		CurrentValue = current_value
		MaxValue = max_value
		ValueChanged.emit(CurrentValue, MaxValue)

	## 广播归零。
	## 返回值：无。
	func emit_depleted() -> void:
		Depleted.emit()


## 按类型返回固定属性值的最小属性组件。
class FakeAttributes extends Node:
	## 属性变化广播，用于验证面板刷新。
	signal AttributeChanged(event)

	## 类型到数值的固定映射。
	var values: Dictionary = {0: 10.0, 1: 6.0, 2: 8.0, 3: 5.0, 4: 3.0}

	## 读取指定属性类型。
	## 参数 type：属性类型整数。
	## 返回值：固定映射中的数值。
	func GetEffectiveValue(type: int) -> float:
		return float(values.get(type, 0.0))

	## 修改一项数值并广播变化。
	## 参数 type：属性类型整数。
	## 参数 value：新的数值。
	## 返回值：无。
	func emit_changed(type: int, value: float) -> void:
		values[type] = value
		AttributeChanged.emit(null)


## 只提供预览所需字段的最小技能资源。
class FakeSkill extends Resource:
	## 技能显示名。
	@export var CardName: String = ""
	## 技能说明。
	@export var Description: String = ""
	## 技能稳定标识。
	@export var CardId: StringName = &""
	## 技能五行枚举；预览对象构造时读取。
	@export var Element: int = 0
	## 技能目标类型枚举；预览对象构造时读取。
	@export var TargetingType: int = 0
	## 技能图标；预览对象构造时读取。
	@export var CardIcon: Texture2D = null


## 只提供 Skills 数组的最小技能集合资源。
class FakeSkillSet extends Resource:
	## 技能条目数组。
	@export var Skills: Array = []


## 验证快照严格跟随 GetSkillPreviews：顺序、隐藏排除、覆盖描述优先、原描述回退。
## 返回值：无。
func test_snapshot_follows_skill_preview_rules() -> void:
	var monster := _new_monster("火蜥蜴", 5, 37, 80)
	var skill_set: Resource = _new_skill_set()
	skill_set.set("Skills", [
		_new_entry("火焰吐息", "技能原描述A", "覆盖描述A", true),
		_new_entry("尾击", "技能原描述B", "", true),
		_new_entry("隐藏撕咬", "不应出现的描述", "", false),
	])
	monster.SkillComponent.call("Initialize", skill_set)

	var panel := _new_panel()
	var snapshot: Dictionary = panel.call("BuildSnapshot", monster)

	assert_eq(String(snapshot["name"]), "火蜥蜴", "名称必须读取 BaseData.MonsterName。")
	assert_eq(int(snapshot["element_id"]), 5, "五行必须读取 BaseData.ElementalProperty。")
	assert_eq(String(snapshot["element_text"]), "火", "五行文本必须复用怪物公开映射。")
	assert_true(bool(snapshot["has_health"]), "生命组件存在时必须标记可读。")
	assert_eq(int(snapshot["current_hp"]), 37, "当前生命必须读取 Health.CurrentValue。")
	assert_eq(int(snapshot["max_hp"]), 80, "生命上限必须读取 Health.MaxValue。")

	var attributes: Array = snapshot["attributes"]
	assert_eq(attributes.size(), 5, "五项战斗属性必须固定展示。")
	assert_eq(String(attributes[0]["label"]), "物攻", "首项必须与怪物卡面一致为物攻。")
	assert_eq(String(attributes[0]["value"]), "10", "物攻必须读取 type=0 的有效值。")
	assert_eq(String(attributes[2]["value"]), "6", "物抗必须读取 type=1 的有效值。")
	assert_eq(String(attributes[1]["value"]), "8", "法强必须读取 type=2 的有效值。")
	assert_eq(String(attributes[4]["value"]), "3", "速度必须读取 type=4 的有效值。")

	var skills: Array = snapshot["skills"]
	assert_eq(skills.size(), 2, "隐藏条目必须被 GetSkillPreviews 过滤，面板不得自行补回。")
	assert_eq(String(skills[0]["name"]), "火焰吐息", "首个技能必须保持配置顺序。")
	assert_eq(String(skills[0]["description"]), "覆盖描述A", "覆盖描述必须优先于技能原描述。")
	assert_eq(String(skills[1]["name"]), "尾击", "第二个技能必须保持配置顺序。")
	assert_eq(String(skills[1]["description"]), "技能原描述B", "无覆盖时必须回退技能 Description。")

	_free_panel(panel)
	_free_monster(monster)


## 验证缺失数据与空技能池的占位降级，不产生报错。
## 返回值：无。
func test_snapshot_degrades_on_missing_data() -> void:
	var bare := FakeMonster.new()
	var panel := _new_panel()
	var snapshot: Dictionary = panel.call("BuildSnapshot", bare)

	assert_eq(String(snapshot["name"]), "未知怪物", "缺少 BaseData 时必须使用名称占位。")
	assert_eq(String(snapshot["element_text"]), "无", "缺少五行时必须回退为无。")
	assert_false(bool(snapshot["has_health"]), "缺少生命组件时不得标记可读。")
	assert_eq(String(snapshot["attributes"][0]["value"]), "--", "缺少属性组件时必须使用数值占位。")
	assert_eq((snapshot["skills"] as Array).size(), 0, "缺少技能组件时必须是空技能池。")

	panel.call("ShowMonster", bare)
	assert_true(panel.call("IsPanelOpen"), "缺失数据也必须能打开面板。")
	assert_eq(panel.get_node("%HpValueLabel").text, "-- / --", "缺少生命时必须显示占位生命文本。")
	assert_eq(panel.get_node("%SkillList").get_child_count(), 1, "空技能池只能显示一条占位文本。")
	assert_eq(panel.get_node("%SkillList").get_child(0).text, "暂无可展示的技能", "占位文本必须明确。")
	assert_eq(panel.get_node("%AttributeList").get_child_count(), 5, "属性占位仍需保持五行行。")

	var empty_entry := _new_entry("", "", "", true)
	var named_monster := _new_monster("空数据怪", 0, 1, 1)
	var skill_set: Resource = _new_skill_set()
	skill_set.set("Skills", [empty_entry, null])
	named_monster.SkillComponent.call("Initialize", skill_set)
	var empty_snapshot: Dictionary = panel.call("BuildSnapshot", named_monster)
	assert_eq((empty_snapshot["skills"] as Array).size(), 1, "空条目必须被预览规则跳过。")
	assert_eq(String(empty_snapshot["skills"][0]["name"]), "未命名技能", "空名称必须降级为占位名。")
	assert_eq(String(empty_snapshot["skills"][0]["description"]), "暂无描述", "空描述必须降级为占位描述。")

	_free_panel(panel)
	_free_monster(named_monster)
	if bare.get_parent() == null:
		bare.free()


## 验证单实例切换目标、信号只连接一次、关闭幂等与重新打开。
## 返回值：无。
func test_panel_switches_target_without_duplicate_binding() -> void:
	var first := _new_monster("甲壳虫", 1, 12, 30)
	var second := _new_monster("水元素", 3, 44, 60)
	var panel := _new_panel()
	_reset_counters(panel)

	panel.call("ShowMonster", first)
	assert_true(panel.call("IsPanelOpen"), "首次查看后必须显示面板。")
	assert_eq(_opened_count["value"], 1, "首次打开只能发出一次 PanelOpened。")
	assert_eq(panel.get_node("%NameLabel").text, "甲壳虫", "必须显示第一只怪物的名称。")
	assert_eq(panel.get_node("%HpValueLabel").text, "12 / 30", "必须显示第一只怪物的生命。")
	var health_callback: Callable = Callable(panel, "_on_health_value_changed")
	assert_true(first.Health.ValueChanged.is_connected(health_callback), "打开时必须连接生命信号。")
	assert_eq(first.Health.ValueChanged.get_connections().size(), 1, "同一怪物不得重复连接生命信号。")

	panel.call("ShowMonster", first)
	assert_eq(_opened_count["value"], 1, "重复查看同一怪物不得再次发出 PanelOpened。")
	assert_eq(first.Health.ValueChanged.get_connections().size(), 1, "重复查看同一怪物不得叠加连接。")

	panel.call("ShowMonster", second)
	assert_eq(panel.get_node("%NameLabel").text, "水元素", "切换目标后必须显示新怪物名称。")
	assert_eq(panel.get_node("%HpValueLabel").text, "44 / 60", "切换目标后必须显示新怪物生命。")
	assert_false(first.Health.ValueChanged.is_connected(health_callback), "切换目标必须断开旧生命信号。")
	assert_true(second.Health.ValueChanged.is_connected(health_callback), "切换目标必须连接新生命信号。")

	first.Health.call("set_values", 3, 30)
	assert_eq(panel.get_node("%HpValueLabel").text, "44 / 60", "旧怪物仍存活时不得再影响当前面板。")
	second.Health.call("set_values", 20, 60)
	assert_eq(panel.get_node("%HpValueLabel").text, "20 / 60", "新怪物生命变化必须实时刷新。")

	panel.call("ClosePanel")
	assert_false(panel.call("IsPanelOpen"), "关闭后必须隐藏面板。")
	assert_eq(_closed_count["value"], 1, "关闭只能发出一次 PanelClosed。")
	assert_false(second.Health.ValueChanged.is_connected(health_callback), "关闭必须断开生命信号。")

	panel.call("ClosePanel")
	assert_eq(_closed_count["value"], 1, "隐藏状态下重复关闭不得再次发出 PanelClosed。")

	panel.call("ShowMonster", second)
	assert_eq(_opened_count["value"], 2, "重新打开必须再次发出 PanelOpened。")

	_free_panel(panel)
	_free_monster(first)
	_free_monster(second)


## 验证技能条目的结构与分割线：名称、描述、仅在条目之间插入分割线。
## 返回值：无。
func test_skill_rows_render_name_description_and_separator() -> void:
	var monster := _new_monster("三技能怪", 2, 50, 50)
	var skill_set: Resource = _new_skill_set()
	skill_set.set("Skills", [
		_new_entry("技能一", "描述一", "", true),
		_new_entry("技能二", "描述二", "", true),
		_new_entry("技能三", "描述三", "", true),
	])
	monster.SkillComponent.call("Initialize", skill_set)
	var panel := _new_panel()
	panel.call("ShowMonster", monster)

	var skill_list: Node = panel.get_node("%SkillList")
	assert_eq(skill_list.get_child_count(), 8, "三个技能必须生成 名称+描述+两个分割线 共八个子节点。")
	assert_eq(skill_list.get_child(0).text, "技能一", "首行必须是技能名称。")
	assert_eq(skill_list.get_child(1).text, "描述一", "次行必须是技能描述。")
	assert_true(skill_list.get_child(1) is Label, "描述必须是 Label 以支持自动换行。")
	assert_eq((skill_list.get_child(1) as Label).autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "描述必须自动换行。")
	assert_true(skill_list.get_child(2) is HSeparator, "条目之间必须是分割线。")
	assert_true(skill_list.get_child(5) is HSeparator, "第二条分割线必须位于第二与第三个技能之间。")
	assert_true(skill_list.get_child(7) is Label, "最后一项必须是 Label。")
	assert_eq((skill_list.get_child(7) as Label).text, "描述三", "最后一项必须是第三个技能描述。")
	var skill_scroll: ScrollContainer = panel.get_node("%SkillScroll")
	assert_ne(int(skill_scroll.vertical_scroll_mode), 0, "技能较多时右列必须允许纵向滚动。")
	assert_eq(int(skill_scroll.horizontal_scroll_mode), 0, "右列必须关闭横向滚动。")

	_free_panel(panel)
	_free_monster(monster)


## 验证怪物被释放后，面板在下一帧自动关闭并清理引用。
## 返回值：无。
func test_panel_closes_when_monster_is_freed() -> void:
	var monster := _new_monster("短命怪", 4, 9, 9)
	var panel := _new_panel()
	_reset_counters(panel)
	panel.call("ShowMonster", monster)
	assert_true(panel.call("IsPanelOpen"), "夹具必须先打开面板。")

	var target: Node = monster
	monster.get_parent().remove_child(monster)
	monster.free()

	panel.call("_process", 0.0)
	assert_false(panel.call("IsPanelOpen"), "绑定怪物释放后必须自动关闭面板。")
	assert_eq(_closed_count["value"], 1, "自动关闭必须发出一次 PanelClosed。")
	assert_eq(panel.get_node("%SkillList").get_child_count(), 0, "关闭必须清空动态技能行。")
	assert_false(is_instance_valid(target), "夹具怪物必须已释放。")

	_free_panel(panel)


## 验证 Esc 在面板显示时关闭面板并消费事件，隐藏时不拦截。
## 返回值：无。
func test_escape_closes_panel_and_consumes_event() -> void:
	var monster := _new_monster("Esc怪", 1, 20, 20)
	var panel := _new_panel()
	var viewport: Viewport = panel.get_viewport()

	var escape_event := InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	escape_event.pressed = true

	# 隐藏状态下先确认不会被面板处理，避免“任何 Esc 都被吞掉”。
	panel.call("_input", escape_event)
	assert_false(panel.call("IsPanelOpen"), "隐藏状态下 Esc 不得打开面板。")

	_reset_counters(panel)
	panel.call("ShowMonster", monster)
	panel.call("_input", escape_event)
	assert_false(panel.call("IsPanelOpen"), "显示状态下 Esc 必须关闭面板。")
	assert_eq(_closed_count["value"], 1, "Esc 关闭必须发出 PanelClosed。")
	if viewport != null:
		assert_true(viewport.is_input_handled(), "面板必须消费 Esc，避免同一次按键打开暂停菜单。")

	_free_panel(panel)
	_free_monster(monster)


## 验证 battle.tscn 只挂一个详情面板，且宿主层为 layer=1 的 CanvasLayer。
## 返回值：无。
func test_battle_scene_hosts_single_detail_layer() -> void:
	# 编辑器长会话会缓存旧 PackedScene；直接读磁盘版本，避免把缓存当成场景未改。
	var packed: PackedScene = ResourceLoader.load(
		BATTLE_SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	assert_true(packed != null, "必须能加载战斗场景。")
	if packed == null:
		return

	var state: SceneState = packed.get_state()
	var detail_layer_index: int = -1
	var panel_index: int = -1
	var panel_count: int = 0
	for index: int in range(state.get_node_count()):
		# SceneState 的路径带 "./" 前缀（与 test_map_world_contract 一致），先归一化再比较。
		var node_path: String = String(state.get_node_path(index)).trim_prefix("./")
		if node_path == "MonsterDetailLayer":
			detail_layer_index = index
		elif node_path == "MonsterDetailLayer/MonsterDetailPanel":
			panel_index = index
			panel_count += 1

	assert_true(detail_layer_index >= 0, "battle.tscn 必须存在 MonsterDetailLayer 宿主层。")
	assert_eq(panel_count, 1, "battle.tscn 只能挂载一个详情面板实例。")
	assert_true(panel_index >= 0, "MonsterDetailPanel 必须挂在 MonsterDetailLayer 下。")
	if detail_layer_index >= 0:
		assert_eq(String(state.get_node_type(detail_layer_index)), "CanvasLayer", "宿主层必须是 CanvasLayer。")
		var layer_value: Variant = _read_state_property(state, detail_layer_index, "layer")
		# CanvasLayer.layer 默认就是 1；编辑器序列化会省略与默认值相同的属性。
		var effective_layer: int = 1
		if typeof(layer_value) == TYPE_INT:
			effective_layer = int(layer_value)
		assert_eq(effective_layer, 1, "宿主层必须是 layer=1：高于战斗 UI，低于 HUD 暂停菜单。")


## 验证面板根节点是全屏模态：整屏锚点、STOP 鼠标过滤、默认隐藏。
## 返回值：无。
func test_panel_root_is_full_screen_modal() -> void:
	var panel := _new_panel()
	assert_eq(panel.anchor_right, 1.0, "面板根节点必须铺满视口宽度。")
	assert_eq(panel.anchor_bottom, 1.0, "面板根节点必须铺满视口高度。")
	assert_eq(panel.offset_right, 0.0, "面板根节点不得留下右侧偏移。")
	assert_eq(panel.offset_bottom, 0.0, "面板根节点不得留下底部偏移。")
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_STOP, "面板根节点必须拦截鼠标，避免点击穿透。")
	assert_false(panel.visible, "面板默认必须隐藏。")

	var dimmer: ColorRect = panel.get_node("%Dimmer")
	assert_eq(dimmer.mouse_filter, Control.MOUSE_FILTER_STOP, "遮罩必须拦截鼠标。")
	assert_true(dimmer.color.a > 0.0, "遮罩必须可见地压暗战斗画面。")

	var detail_panel: PanelContainer = panel.get_node("%DetailPanel")
	assert_eq(detail_panel.mouse_filter, Control.MOUSE_FILTER_STOP, "详情面板本体必须拦截鼠标，避免点击落到遮罩。")

	_free_panel(panel)


## 读取 SceneState 中的属性值；属性不存在时返回 null。
## 参数 state：打包场景状态。
## 参数 node_index：节点索引。
## 参数 property_name：属性名。
## 返回值：属性值或 null。
func _read_state_property(state: SceneState, node_index: int, property_name: String) -> Variant:
	for property_index: int in range(state.get_node_property_count(node_index)):
		if String(state.get_node_property_name(node_index, property_index)) == property_name:
			return state.get_node_property_value(node_index, property_index)
	return null


## 构造带数据、生命、属性与技能组件的夹具怪物。
## 参数 display_name：怪物名称。
## 参数 element：五行枚举。
## 参数 current_hp：当前生命。
## 参数 max_hp：生命上限。
## 返回值：已加入场景树的怪物。
func _new_monster(display_name: String, element: int, current_hp: int, max_hp: int) -> Node:
	var monster := FakeMonster.new()
	monster.name = "MonsterDetailProbe"
	var data: Resource = MONSTER_DATA_SCRIPT.new()
	data.set("MonsterName", display_name)
	data.set("ElementalProperty", element)
	monster.BaseData = data

	var health := FakeHealth.new()
	health.MaxValue = max_hp
	health.CurrentValue = current_hp
	monster.Health = health
	monster.add_child(health)

	var attributes := FakeAttributes.new()
	monster.Attributes = attributes
	monster.add_child(attributes)

	var skill_component: Node = SKILL_COMPONENT_SCRIPT.new()
	monster.SkillComponent = skill_component
	monster.add_child(skill_component)

	var scene_tree := Engine.get_main_loop() as SceneTree
	scene_tree.root.add_child(monster)
	return monster


## 构造技能集合资源。
## 返回值：空的技能集合。
func _new_skill_set() -> Resource:
	return FakeSkillSet.new()


## 构造技能条目。
## 参数 skill_name：技能 CardName。
## 参数 skill_description：技能原 Description。
## 参数 override_description：条目覆盖描述。
## 参数 visible：是否在预览中显示。
## 返回值：技能条目资源。
func _new_entry(skill_name: String, skill_description: String, override_description: String, visible: bool) -> Resource:
	var skill: Resource = FakeSkill.new()
	skill.set("CardName", skill_name)
	skill.set("Description", skill_description)
	var entry: Resource = SKILL_ENTRY_SCRIPT.new()
	entry.set("Skill", skill)
	entry.set("VisibleInPreview", visible)
	entry.set("PreviewDescriptionOverride", override_description)
	return entry


## 实例化面板并加入场景树。
## 返回值：已完成 _ready 的面板实例。
func _new_panel() -> Control:
	var panel: Control = PANEL_SCENE.instantiate() as Control
	var scene_tree := Engine.get_main_loop() as SceneTree
	scene_tree.root.add_child(panel)
	return panel


## 重置打开/关闭计数。
## 参数 panel：目标面板。
## 返回值：无。
func _reset_counters(panel: Control) -> void:
	_opened_count["value"] = 0
	_closed_count["value"] = 0
	panel.connect("PanelOpened", func() -> void: _opened_count["value"] += 1)
	panel.connect("PanelClosed", func() -> void: _closed_count["value"] += 1)


## 释放面板并从场景树移除。
## 参数 panel：目标面板。
## 返回值：无。
func _free_panel(panel: Control) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var parent: Node = panel.get_parent()
	if parent != null:
		parent.remove_child(panel)
	panel.free()


## 释放夹具怪物。
## 参数 monster：目标怪物。
## 返回值：无。
func _free_monster(monster: Node) -> void:
	if monster == null or not is_instance_valid(monster):
		return
	var parent: Node = monster.get_parent()
	if parent != null:
		parent.remove_child(monster)
	monster.free()
