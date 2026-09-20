extends Node2D

## 怪物卡面的 GDScript 生产实现，等价迁移自 entities/Monster.cs。
##
## 根节点仍是“组件定位 + 信号转发 + 稳定协议”的壳：生命、属性、阵营、状态、技能与掉落组件
## 一律按节点名解析、按字段/方法协议调用，因此 C# 与 GDScript 实现可以在同一场景里共存。
## 旧 C# Monster.cs 继续作为兼容垫片保留，两侧公开成员名与参数表逐字一致。
## 不声明 class_name，避免与仍在使用的 C# 全局类型重名。

## 当怪物已经在玩法层死亡、但仍可播放一次视觉收尾时发出。
signal DeathPresentationRequested

## 获取或设置怪物的配置数据。
##
## 迁移期同时接受旧 C# MonsterData 与 GDScript monster_data.gd 资源，
## 因此类型降级为通用 Resource，字段读取统一走 _read_* 字段协议。
@export var BaseData: Resource = null

## 怪物的生命组件节点。
var Health: Node = null
## 怪物的属性组件节点。
var Attributes: Node = null
## 怪物的阵营组件节点；迁移期间通过稳定的 Faction 属性兼容 GDScript 实现。
var Faction: Node = null
## 状态组件节点；组件本身可来自 C# 或 GDScript。
var Status: Node = null
## 怪物技能组件节点；迁移期间通过稳定方法名兼容 C# 与 GDScript 实现。
var SkillComponent: Node = null
## 掉落组件节点；已迁移为 GDScript，通过稳定 TriggerDrop 方法保持死亡流程兼容。
var Loot: Node = null

## 生命/饱食组件共用的归零信号名，与旧 C# 字面量一致。
const DEPLETED_SIGNAL: StringName = &"Depleted"
## 生命值变化信号名，与旧 C# 字面量一致。
const VALUE_CHANGED_SIGNAL: StringName = &"ValueChanged"
## 死亡视觉收尾请求信号名，与旧 C# 字面量一致。
const DEATH_PRESENTATION_REQUESTED: StringName = &"DeathPresentationRequested"
## 提示面板分组名，与旧 C# 字面量一致。
const TOOLTIP_PANEL_GROUP: StringName = &"tooltip_panel"
## 属性组件节点路径。
const ATTRIBUTE_COMPONENT_PATH: NodePath = ^"Components/AttributeComponent"
## 阵营组件节点路径。
const FACTION_COMPONENT_PATH: NodePath = ^"Components/FactionComponent"
## 生命组件节点路径。
const HEALTH_COMPONENT_PATH: NodePath = ^"Components/HealthComponent"
## 状态组件唯一名路径，与旧 C# %StatusComponent 写法一致。
const STATUS_COMPONENT_UNIQUE_PATH: NodePath = ^"%StatusComponent"
## 掉落组件节点路径；旧 C# 使用 GetNodeOrNull，缺失时死亡流程安全降级。
const LOOT_COMPONENT_PATH: NodePath = ^"Components/LootComponent"
## 技能组件节点路径；旧 C# 使用 GetNodeOrNull。
const SKILL_COMPONENT_PATH: NodePath = ^"Components/SkillComponent"
## 血条节点路径。
const HEALTH_BAR_PATH: NodePath = ^"HealthBar"
## 卡名文本节点路径。
const CARD_NAME_PATH: NodePath = ^"CardName"
## 五行文本节点路径。
const ELEMENT_LABEL_PATH: NodePath = ^"Element"
## 目标选择描边节点路径。
const TARGET_SELECTION_OUTLINE_PATH: NodePath = ^"TargetSelectionOutline"
## 鼠标拾取区域节点路径。
const AREA_2D_PATH: NodePath = ^"Area2D"
## 卡面基准精灵节点路径。
const SPRITE_PATH: NodePath = ^"Sprite2D"
## 五行属性枚举取值，与旧 C# ElementType 逐字对应。
const ELEMENT_NONE: int = 0
const ELEMENT_WOOD: int = 1
const ELEMENT_METAL: int = 2
const ELEMENT_WATER: int = 3
const ELEMENT_EARTH: int = 4
const ELEMENT_FIRE: int = 5
## 战斗技能必须实现的两个方法；用能力协议而不是脚本路径或类型名判定，
## 使 GDScript 生产技能与旧 C# CombatSkillData 垫片都能通过，且新增同协议
## 技能资源时不必回到消费端改判定。
const COMBAT_SKILL_REQUIRED_METHODS: Array[StringName] = [&"Execute", &"RequiresTarget"]
## 怪物数据缺少初始属性时的兜底资源脚本，等价旧 C# new StartingStats()。
const STARTING_STATS_SCRIPT: GDScript = preload("res://resources/stats/starting_stats.gd")
## 参与卡面缩放的节点路径；故意不包含 HealthBar，避免目标/行动高亮时血条跟着放大。
const VISUAL_NODE_PATHS: Array[String] = [
	"Sprite2D",
	"CardName",
	"Element",
	"MonsterAttribute",
	"StatusEffectBar",
	"TargetSelectionOutline",
]

## 血条节点；旧 C# 用 GetNode 强取，缺失时在血条刷新入口报错。
var _health_bar: ProgressBar = null
## 鼠标拾取区域节点。
var _area_2d: Area2D = null
## 卡名文本节点。
var _card_name_label: Label = null
## 五行文本节点。
var _element_label: Label = null
## 提示面板节点，进入区域时懒查找。
var _tooltip_panel: Node = null
## 行动/目标静态缩放 Tween。
var _visual_scale_tween: Tween = null
## 防止生命归零、状态效果或重复信号同时触发多个死亡收尾入口。
var _is_combat_defeated: bool = false
## 只有战斗反馈导演成功认领后才延迟销毁，缺失导演时仍会在下一帧安全回收。
var _is_death_presentation_claimed: bool = false
## 目标选择呼吸动画独立保存，避免状态切换时遗留循环 Tween 持续写入卡面缩放。
var _target_selection_pulse_tween: Tween = null
## 绿色目标描边节点仅在选中状态显示，缺失时视觉接口会安全降级。
var _target_selection_outline: Line2D = null
## 每个卡面节点的初始缩放值用于统一应用比例缩放，血条不会写入该映射。
var _visual_scale_base_map: Dictionary = {}
## 每个卡面节点的初始调制颜色用于在取消不可选状态后精确恢复原有美术颜色。
var _visual_modulate_base_map: Dictionary = {}
## 每个卡面节点的初始位置用于让内部文本和属性与卡面缩放保持相对布局。
var _visual_position_base_map: Dictionary = {}
## 生命归零回调使用的稳定信号连接。
var _health_depleted_callable: Callable = Callable()
## 生命值变化回调使用的稳定信号连接。
var _health_value_changed_callable: Callable = Callable()


## 进入场景树后定位全部组件与卡面子节点，并按旧流程初始化卡面。
##
## @return 无返回值。
func _ready() -> void:
	Attributes = get_node(ATTRIBUTE_COMPONENT_PATH)
	Faction = get_node(FACTION_COMPONENT_PATH)
	Health = get_node(HEALTH_COMPONENT_PATH)
	Status = get_node(STATUS_COMPONENT_UNIQUE_PATH)
	Loot = get_node_or_null(LOOT_COMPONENT_PATH)
	SkillComponent = get_node_or_null(SKILL_COMPONENT_PATH)
	_health_depleted_callable = Callable(self, "_handle_death")
	_health_value_changed_callable = Callable(self, "_on_health_changed")
	Health.connect(DEPLETED_SIGNAL, _health_depleted_callable)
	Health.connect(VALUE_CHANGED_SIGNAL, _health_value_changed_callable)

	_health_bar = get_node(HEALTH_BAR_PATH) as ProgressBar
	_card_name_label = get_node_or_null(CARD_NAME_PATH) as Label
	_element_label = get_node_or_null(ELEMENT_LABEL_PATH) as Label
	_target_selection_outline = get_node_or_null(TARGET_SELECTION_OUTLINE_PATH) as Line2D

	_area_2d = get_node(AREA_2D_PATH) as Area2D
	_cache_visual_scale_targets()
	if _area_2d != null:
		_area_2d.mouse_entered.connect(_on_mouse_entered)
		_area_2d.mouse_exited.connect(_on_mouse_exited)

	_tooltip_panel = _find_tooltip_panel()

	if BaseData != null:
		Initialize(BaseData)
	else:
		_update_card_ui(null)


## 鼠标进入卡面区域时按旧文本显示提示面板。
##
## @return 无返回值。
func _on_mouse_entered() -> void:
	if _tooltip_panel == null or not is_instance_valid(_tooltip_panel):
		_tooltip_panel = _find_tooltip_panel()

	if _tooltip_panel == null or not is_instance_valid(_tooltip_panel):
		return

	var monster_name: String = "未知怪物"
	if BaseData != null:
		monster_name = _read_monster_name(BaseData)
	_tooltip_panel.call("show_tooltip", monster_name, "敌人")


## 鼠标离开卡面区域时隐藏提示面板。
##
## @return 无返回值。
func _on_mouse_exited() -> void:
	if _tooltip_panel == null or not is_instance_valid(_tooltip_panel):
		_tooltip_panel = _find_tooltip_panel()

	if _tooltip_panel != null and is_instance_valid(_tooltip_panel):
		_tooltip_panel.call("hide_tooltip")


## 在本节点所在分支里查找提示面板，保持旧 C# 的“就近祖先优先、否则取第一个”规则。
##
## @return 提示面板节点；分组为空时返回 null。
func _find_tooltip_panel() -> Node:
	var panels: Array[Node] = get_tree().get_nodes_in_group(TOOLTIP_PANEL_GROUP)
	if panels.is_empty():
		return null

	var current: Node = self
	while current != null:
		for panel: Node in panels:
			if current.is_ancestor_of(panel):
				return panel
		current = current.get_parent()

	return panels[0]


## 生命值变化时刷新血条，缺失血条节点时保持旧 C# 的硬失败语义。
##
## @param current_value 当前生命值。
## @param max_value 最大生命值。
## @return 无返回值。
func _on_health_changed(current_value: int, max_value: int) -> void:
	if _health_bar == null:
		push_error("HealthBar node is missing on Monster!")
		return

	_health_bar.call("update_stat", current_value, max_value, false)


## 逻辑死亡入口；同一怪物只会执行一次掉落、拾取关闭与视觉收尾广播。
##
## @return 无返回值。
func _handle_death() -> void:
	if _is_combat_defeated:
		return

	_is_combat_defeated = true
	if Loot != null:
		Loot.call("TriggerDrop", global_position, 0)
	if _area_2d != null:
		# 逻辑死亡后立刻关闭鼠标拾取，避免视觉尸体在渐隐期间仍能成为卡牌目标。
		_area_2d.input_pickable = false
		_area_2d.monitoring = false

	emit_signal(DEATH_PRESENTATION_REQUESTED)
	# 信号监听者会在同一帧认领视觉死亡；没有导演时必须保留原有的即时销毁安全语义。
	call_deferred("FinalizeUnclaimedDeath")


## 尝试认领当前怪物的视觉死亡收尾。
##
## @return 仅首个有效导演可认领时返回 true；否则返回 false。
func TryClaimDeathPresentation() -> bool:
	if not _is_combat_defeated or _is_death_presentation_claimed:
		return false

	_is_death_presentation_claimed = true
	return true


## 完成视觉死亡收尾并释放怪物节点。
##
## @return 无返回值。
func FinalizeCombatDeathPresentation() -> void:
	if not is_queued_for_deletion():
		queue_free()


## 在没有任何表现导演认领死亡时，延续旧流程立即释放怪物节点。
##
## @return 无返回值。
func FinalizeUnclaimedDeath() -> void:
	if not _is_death_presentation_claimed:
		FinalizeCombatDeathPresentation()


## 退出场景树时断开生命与鼠标信号，避免跨场景残留回调。
##
## @return 无返回值。
func _exit_tree() -> void:
	if Health != null and Health.is_connected(DEPLETED_SIGNAL, _health_depleted_callable):
		Health.disconnect(DEPLETED_SIGNAL, _health_depleted_callable)

	if Health != null and Health.is_connected(VALUE_CHANGED_SIGNAL, _health_value_changed_callable):
		Health.disconnect(VALUE_CHANGED_SIGNAL, _health_value_changed_callable)

	if _area_2d != null:
		if _area_2d.mouse_entered.is_connected(_on_mouse_entered):
			_area_2d.mouse_entered.disconnect(_on_mouse_entered)
		if _area_2d.mouse_exited.is_connected(_on_mouse_exited):
			_area_2d.mouse_exited.disconnect(_on_mouse_exited)


## 使用跨语言怪物数据初始化卡面、属性与技能组件。
##
## @param data 旧 C# MonsterData 或 GDScript monster_data.gd 资源。
## @return 无返回值。
func Initialize(data: Resource) -> void:
	BaseData = data
	var initial_attributes: Resource = _read_resource_field(data, "InitialAttributes")
	if initial_attributes == null:
		initial_attributes = STARTING_STATS_SCRIPT.new() as Resource
	Attributes.call("InitializeWithData", initial_attributes)
	Faction.set("Faction", _read_faction(data))
	var skill_set: Resource = _read_resource_field(data, "SkillSet")
	if skill_set != null and SkillComponent != null:
		SkillComponent.call("Initialize", skill_set)
	_update_card_ui(data)

	# 实例化图纸里配置的美术预制体
	# if (data.ModelScene != null)
	# {
	#     var visualModel = data.ModelScene.Instantiate();
	#     _modelContainer.AddChild(visualModel);
	# }

	# 初始化行为树
	# var behaviorTree = data.BehaviorTreeScene.Instantiate();
	# if (behaviorTree != null)
	# {
	#     BehaviorTree.AddChild(behaviorTree);
	# }


## 刷新卡名与五行文本，数据为空时清空显示。
##
## @param data 旧 C# MonsterData 或 GDScript monster_data.gd 资源，允许为空。
## @return 无返回值。
func _update_card_ui(data: Resource) -> void:
	if _card_name_label != null:
		_card_name_label.text = (
			_read_monster_name(data) if data != null else ""
		)

	if _element_label != null:
		_element_label.text = (
			_get_element_display_name(_read_elemental_property(data)) if data != null else ""
		)


## 把五行枚举值映射为卡面展示文本，映射关系与旧 C# 完全一致。
##
## @param element 与 ElementType 一致的整数值。
## @return 木/金/水/土/火；其余取值返回“无”。
func _get_element_display_name(element: int) -> String:
	match element:
		ELEMENT_WOOD:
			return "木"
		ELEMENT_METAL:
			return "金"
		ELEMENT_WATER:
			return "水"
		ELEMENT_EARTH:
			return "土"
		ELEMENT_FIRE:
			return "火"
		_:
			return "无"


## 缓存参与卡面缩放的节点初始缩放、位置与调制颜色。
##
## @return 无返回值。
func _cache_visual_scale_targets() -> void:
	_visual_scale_base_map.clear()
	_visual_modulate_base_map.clear()
	_visual_position_base_map.clear()

	for path: String in VISUAL_NODE_PATHS:
		var node: Node = get_node_or_null(path)
		if node == null:
			continue

		# 只缓存卡面和卡面内部内容的初始 scale，故意不包含 HealthBar，避免目标高亮/行动高亮时血条跟着放大。
		if node is Node2D:
			var node_2d: Node2D = node as Node2D
			_visual_scale_base_map[node] = node_2d.scale
			_visual_position_base_map[node] = node_2d.position
		elif node is Control:
			var control: Control = node as Control
			_visual_scale_base_map[node] = control.scale
			_visual_position_base_map[node] = control.position

		if node is CanvasItem:
			_visual_modulate_base_map[node] = (node as CanvasItem).modulate


## 将目标选择后的静态表现应用到怪物卡面，并在需要时显示绿色描边。
##
## @param target_sprite_scale 怪物卡面 Sprite2D 的目标缩放值。
## @param is_dimmed 是否将卡面变暗为不可选状态。
## @param dim_color 不可选状态叠乘到原始卡面颜色的颜色倍率。
## @param show_outline 是否显示目标选择描边。
## @param outline_color 目标选择描边使用的颜色。
## @param outline_width 目标选择描边使用的像素宽度。
## @param duration 缩放过渡持续时间（秒）。
## @return 无返回值。
func ApplyTargetSelectionVisual(
	target_sprite_scale: Vector2,
	is_dimmed: bool,
	dim_color: Color,
	show_outline: bool,
	outline_color: Color,
	outline_width: float,
	duration: float
) -> void:
	StopTargetSelectionPulse()
	_set_target_selection_dimming(is_dimmed, dim_color)
	_set_target_selection_outline(show_outline, outline_color, outline_width)
	TweenVisualScale(target_sprite_scale, duration)


## 启动怪物卡面的循环呼吸缩放，用于提示仍可手动选择的目标。
##
## @param minimum_sprite_scale 呼吸动画的最小 Sprite2D 缩放值。
## @param maximum_sprite_scale 呼吸动画的最大 Sprite2D 缩放值。
## @param half_cycle_duration 从最小值到最大值或反向的单程持续时间（秒）。
## @return 无返回值。
func StartTargetSelectionPulse(
	minimum_sprite_scale: Vector2,
	maximum_sprite_scale: Vector2,
	half_cycle_duration: float
) -> void:
	StopTargetSelectionPulse()
	_set_target_selection_dimming(false, Color.WHITE)
	_set_target_selection_outline(false, Color.WHITE, 0.0)

	if _read_base_sprite_scale() == null:
		return

	# 呼吸缩放与行动表现共用同一批卡面节点；启动前先终止静态缩放，避免两个 Tween 争夺同一属性。
	if _visual_scale_tween != null and _visual_scale_tween.is_running():
		_visual_scale_tween.kill()

	_target_selection_pulse_tween = create_tween()
	_target_selection_pulse_tween.set_parallel(true)
	_append_visual_scale_properties(_target_selection_pulse_tween, maximum_sprite_scale, half_cycle_duration)
	_target_selection_pulse_tween.chain().set_parallel(true)
	_append_visual_scale_properties(_target_selection_pulse_tween, minimum_sprite_scale, half_cycle_duration)
	_target_selection_pulse_tween.set_loops()


## 停止目标选择呼吸动画，但不改变当前卡面缩放、颜色或描边状态。
##
## @return 无返回值。
func StopTargetSelectionPulse() -> void:
	if _target_selection_pulse_tween != null and _target_selection_pulse_tween.is_running():
		_target_selection_pulse_tween.kill()

	_target_selection_pulse_tween = null


## 将怪物卡恢复为普通目标选择状态，清除呼吸、变暗和绿色描边。
##
## @param normal_sprite_scale 怪物卡面 Sprite2D 的正常缩放值。
## @param duration 缩放还原持续时间（秒）。
## @return 无返回值。
func ResetTargetSelectionVisual(normal_sprite_scale: Vector2, duration: float) -> void:
	StopTargetSelectionPulse()
	_set_target_selection_dimming(false, Color.WHITE)
	_set_target_selection_outline(false, Color.WHITE, 0.0)
	TweenVisualScale(normal_sprite_scale, duration)


## 按倍率叠加或恢复卡面各节点的调制颜色。
##
## @param is_dimmed 是否进入不可选变暗状态。
## @param dim_color 变暗时叠乘的颜色倍率。
## @return 无返回值。
func _set_target_selection_dimming(is_dimmed: bool, dim_color: Color) -> void:
	if _visual_modulate_base_map.is_empty():
		_cache_visual_scale_targets()

	for node: Node in _visual_modulate_base_map.keys():
		var canvas_item: CanvasItem = node as CanvasItem
		if canvas_item == null:
			continue
		var base_color: Color = _visual_modulate_base_map[node]
		if is_dimmed:
			canvas_item.modulate = Color(
				base_color.r * dim_color.r,
				base_color.g * dim_color.g,
				base_color.b * dim_color.b,
				base_color.a * dim_color.a
			)
		else:
			canvas_item.modulate = base_color


## 显示或隐藏目标选择描边，并在显示时套用颜色与宽度。
##
## @param is_visible 是否显示描边。
## @param outline_color 描边颜色。
## @param outline_width 描边像素宽度。
## @return 无返回值。
func _set_target_selection_outline(is_visible: bool, outline_color: Color, outline_width: float) -> void:
	if _target_selection_outline == null or not is_instance_valid(_target_selection_outline):
		_target_selection_outline = get_node_or_null(TARGET_SELECTION_OUTLINE_PATH) as Line2D

	if _target_selection_outline == null:
		return

	_target_selection_outline.visible = is_visible
	if is_visible:
		_target_selection_outline.default_color = outline_color
		_target_selection_outline.width = outline_width


## 读取卡面基准 Sprite2D 的初始缩放。
##
## @return 基准缩放；Sprite2D 缺失或未缓存时返回 null。
func _read_base_sprite_scale() -> Variant:
	if _visual_scale_base_map.is_empty():
		_cache_visual_scale_targets()

	# Sprite2D 是卡面缩放比例的基准节点，其他内部节点都据此计算相同的相对倍率。
	var sprite_node: Node = get_node_or_null(SPRITE_PATH)
	if sprite_node != null and _visual_scale_base_map.has(sprite_node):
		return _visual_scale_base_map[sprite_node]

	return null


## 把同一批卡面节点写入 Tween，卡面用绝对目标缩放、内部节点按同一倍率缩放。
##
## @param tween 目标 Tween；调用方负责并行与循环设置。
## @param target_sprite_scale 怪物卡面 Sprite2D 的目标缩放值。
## @param duration 单段动画持续时间（秒）。
## @return 无返回值。
func _append_visual_scale_properties(tween: Tween, target_sprite_scale: Vector2, duration: float) -> void:
	var base_value: Variant = _read_base_sprite_scale()
	if base_value == null:
		return
	var base_sprite_scale: Vector2 = base_value

	# Sprite2D 引用用于准确识别基准卡面，避免以节点名称比较导致重命名后缩放比例失效。
	var sprite_node: Node = get_node_or_null(SPRITE_PATH)
	if sprite_node == null:
		return

	# 缩放比例会同步应用到卡名、属性和状态栏，使它们围绕卡面保持原有的相对布局。
	var ratio := Vector2(
		target_sprite_scale.x / base_sprite_scale.x if base_sprite_scale.x != 0.0 else 1.0,
		target_sprite_scale.y / base_sprite_scale.y if base_sprite_scale.y != 0.0 else 1.0
	)

	for node: Node in _visual_scale_base_map.keys():
		var base_scale: Vector2 = _visual_scale_base_map[node]
		# 卡面使用绝对目标缩放，内部节点使用与基准卡面相同的倍率。
		var target_scale := (
			target_sprite_scale
			if node == sprite_node
			else Vector2(base_scale.x * ratio.x, base_scale.y * ratio.y)
		)
		tween.tween_property(node, "scale", target_scale, duration)

		if _visual_position_base_map.has(node):
			var base_position: Vector2 = _visual_position_base_map[node]
			# 同步位置可让卡面内部文字围绕同一中心缩放，而血条不在缓存内所以不会被移动。
			var target_position := Vector2(base_position.x * ratio.x, base_position.y * ratio.y)
			tween.tween_property(node, "position", target_position, duration)


## 统一缩放怪物卡面与内部文字/属性内容，但不缩放血条。
##
## @param target_sprite_scale 怪物卡面 Sprite2D 的目标缩放值。
## @param duration 缩放动画持续时间（秒）。
## @return 无返回值。
func TweenVisualScale(target_sprite_scale: Vector2, duration: float) -> void:
	StopTargetSelectionPulse()
	if _read_base_sprite_scale() == null:
		return

	if _visual_scale_tween != null and _visual_scale_tween.is_running():
		_visual_scale_tween.kill()

	_visual_scale_tween = create_tween()
	_visual_scale_tween.set_parallel(true)
	_append_visual_scale_properties(_visual_scale_tween, target_sprite_scale, duration)


## 将怪物卡面与内部内容恢复到场景中的初始缩放，血条保持不变。
##
## @param duration 缩放动画持续时间（秒）。
## @return 无返回值。
func ResetVisualScale(duration: float) -> void:
	if _visual_scale_base_map.is_empty():
		_cache_visual_scale_targets()

	var sprite_node: Node = get_node_or_null(SPRITE_PATH)
	if sprite_node != null and _visual_scale_base_map.has(sprite_node):
		var base_sprite_scale: Vector2 = _visual_scale_base_map[sprite_node]
		TweenVisualScale(base_sprite_scale, duration)


## 从技能组件获取当前怪物配置的战斗技能。
##
## @return 当前怪物可用的有效战斗技能数组。
func GetCombatSkills() -> Array[Resource]:
	var result: Array[Resource] = []
	if SkillComponent == null or not SkillComponent.has_method("GetCombatSkills"):
		return result

	var raw_skills: Variant = SkillComponent.call("GetCombatSkills")
	if typeof(raw_skills) != TYPE_ARRAY:
		return result

	# 技能资产已切换为 GDScript 实现，统一用能力协议过滤，避免把语言判定写死在消费端。
	for value: Variant in (raw_skills as Array):
		var skill: Resource = value as Resource
		if skill != null and _is_combat_skill_data(skill):
			result.append(skill)

	return result


## 为怪物自动回合选择一个战斗技能。
##
## @return 已配置的战斗技能；没有技能组件或没有技能时返回 null。
func GetRandomCombatSkill() -> Resource:
	if SkillComponent == null or not SkillComponent.has_method("GetRandomCombatSkill"):
		return null

	var candidate: Resource = SkillComponent.call("GetRandomCombatSkill") as Resource
	if candidate != null and _is_combat_skill_data(candidate):
		return candidate

	return null


## 判断资源是否为新旧战斗技能，避免把其他 Resource 当成技能执行。
##
## 判定只看能力协议（`Execute` + `RequiresTarget`），不看脚本路径或类型名：
## GDScript 生产技能、旧 C# 垫片与将来任何同协议资源都会被一致接受，
## 而物品技能卡（`ApplyEffect`）等不具备该协议的资源仍被拒绝。
##
## @param value 待判断的资源。
## @return 实现战斗技能协议时返回 true。
func _is_combat_skill_data(value: Variant) -> bool:
	if not (value is Resource):
		return false

	var resource: Resource = value as Resource
	for method_name: StringName in COMBAT_SKILL_REQUIRED_METHODS:
		if not resource.has_method(method_name):
			return false

	return true


## 按字段名读取怪物数据持有的资源字段。
##
## @param data 旧 C# MonsterData 或 GDScript monster_data.gd 资源，允许为空。
## @param field_name 字段名，必须与两侧实现保持一致。
## @return 字段资源；字段缺失或类型不符时返回 null。
func _read_resource_field(data: Resource, field_name: String) -> Resource:
	if data == null:
		return null
	return data.get(field_name) as Resource


## 读取怪物显示名称。
##
## @param data 旧 C# MonsterData 或 GDScript monster_data.gd 资源。
## @return 旧实现的名称；字段缺失或类型不符时返回空字符串。
func _read_monster_name(data: Resource) -> String:
	if data == null:
		return ""

	var value: Variant = data.get("MonsterName")
	if typeof(value) == TYPE_STRING:
		return String(value)

	return ""


## 读取怪物五行属性枚举值。
##
## @param data 旧 C# MonsterData 或 GDScript monster_data.gd 资源。
## @return 与 ElementType 一致的整数值；读取失败时返回 0（None）。
func _read_elemental_property(data: Resource) -> int:
	if data == null:
		return ELEMENT_NONE

	var value: Variant = data.get("ElementalProperty")
	if typeof(value) == TYPE_INT:
		return int(value)

	return ELEMENT_NONE


## 读取怪物阵营枚举值。
##
## @param data 旧 C# MonsterData 或 GDScript monster_data.gd 资源。
## @return 与 MonsterFaction 一致的整数值；读取失败时返回 0（Hostile）。
func _read_faction(data: Resource) -> int:
	if data == null:
		return 0

	var value: Variant = data.get("Faction")
	if typeof(value) == TYPE_INT:
		return int(value)

	return 0
