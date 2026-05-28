@tool
extends HBoxContainer
class_name StatusEffectBar

## Buff/状态横向展示栏。
## 该组件只负责读取实体 StatusComponent 并生成图标 UI，不参与状态结算，适合挂在玩家属性区、怪物卡牌或其它战斗实体旁边。

const DEFAULT_FALLBACK_ICON: Texture2D = preload("res://res/buff_icon/none.png")
const DEFAULT_STACK_FONT: Font = preload("res://res/font/Uranus_Pixel_11Px.ttf")

@export_category("目标绑定")
@export var target_entity_path: NodePath ## 可选：直接指定持有 StatusComponent 的战斗实体节点；留空时会自动向父级或战斗场景查找。
@export var auto_find_player_entity: bool = false ## 玩家 UI 位于独立 HUD 下时开启，用 PlayerManager 定位真实玩家实体。
@export var status_component_node_path: NodePath = NodePath("Components/StatusComponent") ## 状态组件相对战斗实体的路径。

@export_category("图标布局")
@export var icon_size: Vector2 = Vector2(18, 18):
	set(value):
		icon_size = value
		_queue_editor_refresh()
## 单个 Buff 图标的显示尺寸。
@export var fallback_icon: Texture2D = DEFAULT_FALLBACK_ICON:
	set(value):
		fallback_icon = value
		_queue_editor_refresh()
## Buff 未配置图标时使用的默认图标。
@export var empty_bar_visible: bool = false ## 没有 Buff 时是否保留空栏位区域，通常玩家栏可按布局需求开启。
@export var fallback_icon_color: Color = Color(0.35, 0.35, 0.35, 0.9) ## Buff 未配置图标时的兜底底色，避免状态完全不可见。
@export var fallback_text: String = "?" ## Buff 未配置图标时显示的兜底字符。

@export_category("层数数字样式")
@export var stack_font: Font = DEFAULT_STACK_FONT:
	set(value):
		stack_font = value
		_queue_editor_refresh()
## 层数数字使用的字体；这里主动覆盖父级 Theme，保证玩家栏和怪物栏显示一致。
@export_range(1, 64, 1) var stack_font_size: int = 11:
	set(value):
		stack_font_size = value
		_queue_editor_refresh()
## 层数数字字号。
@export var stack_offset_left: float = -14.0:
	set(value):
		stack_offset_left = value
		_queue_editor_refresh()
## 层数 Label 相对图标右下角向左扩展的距离，越负显示区域越宽。
@export var stack_offset_top: float = -14.0:
	set(value):
		stack_offset_top = value
		_queue_editor_refresh()
## 层数 Label 相对图标右下角向上扩展的距离，越负显示区域越高。
@export var stack_font_color: Color = Color.WHITE:
	set(value):
		stack_font_color = value
		_queue_editor_refresh()
## 层数数字颜色。
@export var stack_outline_color: Color = Color.BLACK:
	set(value):
		stack_outline_color = value
		_queue_editor_refresh()
## 层数数字描边颜色。
@export_range(0, 12, 1) var stack_outline_size: int = 3:
	set(value):
		stack_outline_size = value
		_queue_editor_refresh()
## 层数数字描边粗细。

@export_category("编辑器预览")
@export var editor_preview_enabled: bool = true:
	set(value):
		editor_preview_enabled = value
		_queue_editor_refresh()
## 在 Godot 编辑器中显示示例 Buff，不需要启动游戏即可调整 UI 布局。
@export_range(0, 12, 1) var editor_preview_count: int = 3:
	set(value):
		editor_preview_count = value
		_queue_editor_refresh()
## 编辑器中显示的示例 Buff 数量。
@export_range(1, 99, 1) var editor_preview_stacks: int = 2:
	set(value):
		editor_preview_stacks = value
		_queue_editor_refresh()
## 编辑器示例 Buff 右下角显示的层数。
@export var editor_preview_icon: Texture2D = DEFAULT_FALLBACK_ICON:
	set(value):
		editor_preview_icon = value
		_queue_editor_refresh()
## 编辑器示例 Buff 使用的图标；为空时使用默认 none 图标。
@export var editor_preview_name: String = "示例 Buff" ## 编辑器预览 tooltip 的名称。
@export_multiline var editor_preview_description: String = "用于在编辑器中预览 Buff 栏布局。" ## 编辑器预览 tooltip 的描述。

var _target_entity: Node = null
var _status_component: Node = null
var _tooltip_panel: Node = null
var _is_pointer_inside_status_icon: bool = false

func _ready() -> void:
	# 状态栏依赖战斗实体和全局 TooltipPanel，延迟绑定可以避开场景中兄弟节点 ready 顺序差异。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 3)
	call_deferred("refresh")

## 在编辑器中修改预览参数后延迟刷新，避免检查器连续赋值时重复重建子节点。
func _queue_editor_refresh() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		call_deferred("refresh")

## 重新绑定目标实体并刷新所有 Buff 图标。
## 使用场景：战斗实体初始化完成、玩家实体替换、外部系统需要手动同步状态 UI。
func refresh() -> void:
	_resolve_target_entity()
	_resolve_status_component()
	_connect_status_changed_signal()
	_resolve_tooltip_panel()
	_rebuild_icons()

## 根据导出路径、玩家管理器或父级链路定位要展示 Buff 的实体。
func _resolve_target_entity() -> void:
	_target_entity = null

	if not target_entity_path.is_empty():
		_target_entity = get_node_or_null(target_entity_path)
		if _target_entity:
			return

	if auto_find_player_entity:
		_target_entity = _find_player_entity()
		if _target_entity:
			return

	_target_entity = _find_entity_from_ancestors()

## 读取目标实体上的 StatusComponent。
func _resolve_status_component() -> void:
	_status_component = null
	if not _target_entity:
		return

	_status_component = _target_entity.get_node_or_null(status_component_node_path)

## 监听状态变化事件，使 Buff 施加、刷新、叠层、过期或移除后图标自动更新。
func _connect_status_changed_signal() -> void:
	if not _status_component or not _status_component.has_signal("StatusChanged"):
		return

	var callable := Callable(self, "_on_status_changed")
	if not _status_component.is_connected("StatusChanged", callable):
		_status_component.connect("StatusChanged", callable)

## 定位战斗场景里唯一的 TooltipPanel，复用卡牌和怪物已有的悬停提示框样式。
func _resolve_tooltip_panel() -> void:
	var panels := get_tree().get_nodes_in_group("tooltip_panel")
	if panels.size() > 0:
		_tooltip_panel = panels[0]
		return

	if get_tree().current_scene:
		var ui_node := get_tree().current_scene.get_node_or_null("UI")
		if ui_node:
			_tooltip_panel = ui_node.get_node_or_null("TooltipPanel")

## 玩家 Buff 栏处于 UI 层，不能通过父级链路找到实体，因此优先读取 PlayerManager 暴露的战斗实体。
## 返回值：玩家实体节点；无法定位时返回 null。
func _find_player_entity() -> Node:
	var current_scene := get_tree().current_scene
	var player_manager := current_scene.get_node_or_null("PlayerManager") if current_scene else null
	if player_manager:
		if player_manager.has_method("get_combat_entity"):
			var combat_entity = player_manager.call("get_combat_entity")
			if combat_entity:
				return combat_entity

		var local_player := player_manager.get_node_or_null("Player")
		if local_player:
			return local_player

	var grouped_players := get_tree().get_nodes_in_group("Player")
	if grouped_players.size() > 0:
		return grouped_players[0]

	return null

## 从当前节点逐级向上寻找带 StatusComponent 的战斗实体，主要服务于怪物卡牌内的 Buff 栏。
## 返回值：实体节点；无法定位时返回 null。
func _find_entity_from_ancestors() -> Node:
	var current := get_parent()
	while current:
		if current.has_method("get_node_or_null") and current.get_node_or_null(status_component_node_path):
			return current
		current = current.get_parent()

	return null

## StatusComponent.StatusChanged 的回调。
## 参数 change_event 由 C# 状态系统提供；UI 不关心具体原因，统一重建可避免漏处理刷新、叠层和移除分支。
func _on_status_changed(_change_event: RefCounted) -> void:
	_rebuild_icons()

## 清空旧图标并按当前 ActiveStatuses 重新生成横向图标队列。
func _rebuild_icons() -> void:
	if _is_pointer_inside_status_icon and _tooltip_panel and is_instance_valid(_tooltip_panel):
		# Buff 刷新会销毁旧图标；主动隐藏旧提示框，避免鼠标还停在原位置时显示已经失效的状态说明。
		_tooltip_panel.call("hide_tooltip")
	_is_pointer_inside_status_icon = false

	_clear_icons()

	if Engine.is_editor_hint() and editor_preview_enabled:
		_rebuild_editor_preview_icons()
		return

	if not _status_component:
		visible = empty_bar_visible
		return

	var statuses = []
	if _status_component.has_method("GetActiveStatusesSnapshot"):
		statuses = _status_component.call("GetActiveStatusesSnapshot")
	else:
		statuses = _status_component.get("ActiveStatuses")
	if statuses == null:
		visible = empty_bar_visible
		return

	var status_count := 0
	for status in statuses:
		status_count += 1
		add_child(_create_status_icon(status))

	visible = empty_bar_visible or status_count > 0

## 移除当前所有图标子节点。
func _clear_icons() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

## 在编辑器中生成示例 Buff 图标，方便不运行游戏时直接调整 UI 布局。
func _rebuild_editor_preview_icons() -> void:
	var preview_icon := editor_preview_icon if editor_preview_icon else fallback_icon
	for index in range(editor_preview_count):
		add_child(_create_icon_control(
			preview_icon,
			editor_preview_stacks,
			"%s %d" % [editor_preview_name, index + 1],
			editor_preview_description
		))

	visible = empty_bar_visible or editor_preview_count > 0

## 为单个状态创建可悬停的图标节点。
## 参数 status：C# StatusEffectInstance 实例。
## 返回值：已配置好图标、层数和提示框信号的 Control 节点。
func _create_status_icon(status: Variant) -> Control:
	return _create_icon_control(
		_get_status_icon(status),
		_get_status_stacks(status),
		_get_status_display_name(status),
		_get_status_description(status)
	)

## 创建一个 Buff 图标控件，并绑定层数与提示框内容。
## 参数 icon_texture：优先显示的 Buff 图标；为空时使用 fallback_icon。
## 参数 stacks：当前层数，超过 1 时显示在右下角。
## 参数 tooltip_title：悬停提示框标题。
## 参数 tooltip_description：悬停提示框描述。
## 返回值：可加入 Buff 栏的 Control 节点。
func _create_icon_control(icon_texture: Texture2D, stacks: int, tooltip_title: String, tooltip_description: String) -> Control:
	var icon_root := Control.new()
	icon_root.custom_minimum_size = icon_size
	icon_root.mouse_filter = Control.MOUSE_FILTER_STOP
	icon_root.tooltip_text = ""

	if not icon_texture:
		icon_texture = fallback_icon

	if icon_texture:
		var texture_rect := TextureRect.new()
		texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		texture_rect.texture = icon_texture
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_root.add_child(texture_rect)
	else:
		icon_root.add_child(_create_fallback_icon())

	if stacks > 1:
		icon_root.add_child(_create_stack_label(stacks))

	icon_root.mouse_entered.connect(_on_status_icon_mouse_entered.bind(tooltip_title, tooltip_description))
	icon_root.mouse_exited.connect(_on_status_icon_mouse_exited)
	return icon_root

## 创建未配置图标时的兜底视觉，提醒配置者补齐资源，同时保证玩家仍能看到 Buff 存在。
func _create_fallback_icon() -> Control:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = fallback_icon_color
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.text = fallback_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(label)

	return background

## 创建右下角层数文本。
## 参数 stacks：当前 Buff 层数。
## 返回值：用于叠放在图标上的 Label。
func _create_stack_label(stacks: int) -> Label:
	var stack_label := Label.new()
	stack_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	stack_label.offset_left = stack_offset_left
	stack_label.offset_top = stack_offset_top
	stack_label.text = str(stacks)
	stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	stack_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if stack_font:
		stack_label.add_theme_font_override("font", stack_font)
	stack_label.add_theme_color_override("font_color", stack_font_color)
	stack_label.add_theme_color_override("font_outline_color", stack_outline_color)
	stack_label.add_theme_constant_override("outline_size", stack_outline_size)
	stack_label.add_theme_font_size_override("font_size", stack_font_size)
	return stack_label

## 鼠标进入 Buff 图标时显示详细说明。
func _on_status_icon_mouse_entered(tooltip_title: String, tooltip_description: String) -> void:
	_is_pointer_inside_status_icon = true
	if not _tooltip_panel or not is_instance_valid(_tooltip_panel):
		_resolve_tooltip_panel()

	if _tooltip_panel and is_instance_valid(_tooltip_panel):
		_tooltip_panel.call("show_tooltip", tooltip_title, tooltip_description)

## 鼠标离开 Buff 图标时隐藏提示框。
func _on_status_icon_mouse_exited() -> void:
	_is_pointer_inside_status_icon = false
	if _tooltip_panel and is_instance_valid(_tooltip_panel):
		_tooltip_panel.call("hide_tooltip")

## 读取状态名称。
## 参数 status：C# StatusEffectInstance 实例。
## 返回值：优先返回数据配置的 DisplayName，其次返回状态 Id，最后返回兜底文本。
func _get_status_display_name(status: Variant) -> String:
	var data = _get_status_data(status)
	if data:
		var display_name = data.get("DisplayName")
		if display_name != null and not str(display_name).is_empty():
			return str(display_name)

	var status_id = status.get("Id") if status != null else null
	if status_id != null and not str(status_id).is_empty():
		return str(status_id)

	return "未知状态"

## 读取状态说明。
## 参数 status：C# StatusEffectInstance 实例。
## 返回值：配置描述文本；为空时返回通用兜底说明。
func _get_status_description(status: Variant) -> String:
	var data = _get_status_data(status)
	if data:
		var description = data.get("Description")
		if description != null and not str(description).is_empty():
			return str(description)

	return "暂无状态描述。"

## 读取状态图标。
## 参数 status：C# StatusEffectInstance 实例。
## 返回值：配置的 Texture2D；未配置时返回 null。
func _get_status_icon(status: Variant) -> Texture2D:
	var data = _get_status_data(status)
	if not data:
		return null

	var icon = data.get("Icon")
	return icon as Texture2D

## 读取状态当前层数。
## 参数 status：C# StatusEffectInstance 实例。
## 返回值：层数；无法读取时按 1 层处理。
func _get_status_stacks(status: Variant) -> int:
	if status == null:
		return 1

	var stacks = status.get("CurrentStacks")
	return maxi(1, int(stacks)) if stacks != null else 1

## 读取状态的数据资源。
## 参数 status：C# StatusEffectInstance 实例。
## 返回值：StatusEffectData 资源；无法读取时返回 null。
func _get_status_data(status: Variant) -> Resource:
	if status == null:
		return null

	var data = status.get("Data")
	return data as Resource
