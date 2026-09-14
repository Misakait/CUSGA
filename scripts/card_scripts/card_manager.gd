## 卡牌管理器 (CardManager)
## 负责处理手牌中的交互逻辑（如拖拽、悬停高亮、打出检测）。
## 它实时监测鼠标的射线投射并拦截输入操作。
extends Node2D

@onready var deck_manager = $"../DeckManager"
@onready var control_lock = $"../ControlLock"
@onready var player_manager = $"../PlayerManager"
@onready var battle_manager = $".."
@onready var tooltip_panel = $"../UI/TooltipPanel"
# 战斗右上角的操作模式设置组件。
# 它只负责展示和发出选择信号，具体模式状态仍由本管理器拥有。
@onready var _settings_panel: Control = $"../UI/BattleSettingsPanel"
# 点击模式下显示确认与取消按钮的操作栏组件。
# 它通过信号请求操作，避免 UI 直接修改卡牌或战斗状态。
@onready var _click_mode_action_bar: HBoxContainer = $"../UI/ClickModeActionBar"

const COLLISION_MASK_CARD = 1
const COLLISION_MASK_CARD_SLOT = 2
const SKILL_TARGETING_TYPE := preload("res://scripts/generated/SkillTargetingType.gd")
# 操作模式设置在通用本地配置中的分组名称。
# 该分组只定义战斗偏好，修改会导致已保存模式无法被后续版本读取。
const OPERATION_MODE_SETTINGS_SECTION: String = "battle"
# 操作模式设置在战斗分组中的键名。
# 使用稳定英文键可避免 UI 文案变化影响已保存玩家偏好。
const OPERATION_MODE_SETTINGS_KEY: String = "operation_mode"
# 点击模式的稳定存储值。
# 它是首次运行、缺失配置和无效配置时的默认值。
const OPERATION_MODE_CLICK: String = "click"
# 拖拽模式的稳定存储值。
# 该值对应改动前已有的卡牌按下、拖动和松开交互。
const OPERATION_MODE_DRAG: String = "drag"

@export_group("视觉缩放参数")
@export var card_normal_scale: Vector2 = Vector2(1.0, 1.0) ## 卡牌正常大小
@export var card_hover_scale: Vector2 = Vector2(1.05, 1.05) ## 卡牌悬停放大
@export var card_drag_scale: Vector2 = Vector2(0.95, 0.95) ## 卡牌拖拽时略微缩小
@export var monster_normal_scale: Vector2 = Vector2(1.5, 1.5) ## 怪物正常大小
@export var monster_hover_scale: Vector2 = Vector2(1.6, 1.6) ## 怪物被选中悬停时放大
@export var scale_tween_duration: float = 0.08 ## 缩放动画过度时间

@export_group("点击模式选中参数")
# 点击模式选中卡牌向上移动的距离。
# 该值独立于悬停缩放，确保玩家即使移开鼠标也能识别待确认卡牌。
@export var click_selected_card_lift_distance: float = 36.0
# 点击模式选中卡牌上移所用的时间。
# 时长集中在此处，避免交互流程中散落表现参数。
@export var click_selected_card_lift_duration: float = 0.12

@export_group("自我施放参数")
@export var allow_self_cast_on_empty: bool = true ## 当卡牌为【对自己使用】时，允许拖到空白处直接施放

var screen_size
var card_being_dragged:Node2D
var is_hovering_on_card:bool
var player_hand_referencd #玩家手牌引用
var drag_offset: Vector2 # 用于记录拖拽偏移量
#var currently_hovered_slot: Node2D = null # 记录当前被悬停的卡槽，修改为下面
var currently_highlighted_entities: Array[Node] = [] # 记录当前被悬停的卡槽
# 当前生效的卡牌操作模式。
# 值仅允许为 OPERATION_MODE_CLICK 或 OPERATION_MODE_DRAG，默认点击模式可保证首次进入战斗可直接选卡。
var _operation_mode: String = OPERATION_MODE_CLICK
# 点击模式下等待确认施放的卡牌。
# 为 null 表示尚未选择卡牌，此时确认/取消操作栏必须隐藏。
var _selected_click_card: SkillCard = null
# 点击模式下显式选择的敌人目标。
# 为 null 时确认操作会以玩家自身为目标，符合未选择敌人的默认规则。
var _selected_click_target: Node = null

func _ready() -> void:
	screen_size = get_viewport_rect().size
	player_hand_referencd = $"../PlayerHand"
	_operation_mode = _load_operation_mode()
	# UI 节点与 CardManager 是同级节点，延后到所有同级节点完成 _ready 后再绑定，避免读取到未初始化的 @onready 引用。
	call_deferred("_initialize_operation_mode_components")

func _process(delta: float) -> void:
	if card_being_dragged:
		var mouse_pos = get_global_mouse_position()
		# 将偏移量应用到目标位置上
		var target_pos = mouse_pos + drag_offset
		card_being_dragged.position = Vector2(
			clamp(target_pos.x, 0, screen_size.x),
			clamp(target_pos.y, 0, screen_size.y)
		)

		# 检测是否拖拽到了某个卡槽上，将命中结果交由多目标高亮方法处理
		var card_slot_found = raycast_check_for_card_slot()
		# 同步检测当前位置是否在手牌区，避免自我施放卡在回收路径上误触高亮
		var release_in_hand_area: bool = false
		if player_hand_referencd and player_hand_referencd.has_method("is_release_in_hand_area"):
			release_in_hand_area = player_hand_referencd.is_release_in_hand_area(card_being_dragged.global_position)
		update_hovered_targets(card_slot_found, release_in_hand_area)

	check_cards_energy()
	if _is_click_operation_mode() and _selected_click_card and (control_lock.is_lock or battle_manager.current_state != battle_manager.BattleState.PLAYER_TURN):
		# 玩家失去输入权时必须丢弃临时选择，防止下一个回合误用已经过期的目标或卡牌。
		clear_click_selection()

## 初始化操作模式设置面板与点击模式操作栏。
## 该方法延后调用，以确保场景中所有同级 UI 节点都已完成自身初始化。
## @return void 无返回值。
func _initialize_operation_mode_components() -> void:
	if _settings_panel:
		if _settings_panel.has_method("configure_options"):
			_settings_panel.call("configure_options", get_operation_mode_options(), _operation_mode)
		if _settings_panel.has_signal("operation_mode_selected") and not _settings_panel.is_connected("operation_mode_selected", _on_operation_mode_selected):
			_settings_panel.connect("operation_mode_selected", _on_operation_mode_selected)

	if _click_mode_action_bar:
		if _click_mode_action_bar.has_signal("confirm_requested") and not _click_mode_action_bar.is_connected("confirm_requested", _on_click_mode_confirm_requested):
			_click_mode_action_bar.connect("confirm_requested", _on_click_mode_confirm_requested)
		if _click_mode_action_bar.has_signal("cancel_requested") and not _click_mode_action_bar.is_connected("cancel_requested", _on_click_mode_cancel_requested):
			_click_mode_action_bar.connect("cancel_requested", _on_click_mode_cancel_requested)
		_set_click_mode_action_bar_visible(false)

## 返回设置面板所需的操作模式选项。
## 由 CardManager 作为稳定值与显示文案的唯一来源，避免 UI 与输入层各自维护一套模式定义。
## @return Array[Dictionary] 每项包含 value（存储值）和 label（显示文案）。
func get_operation_mode_options() -> Array[Dictionary]:
	return [
		{"value": OPERATION_MODE_CLICK, "label": "点击"},
		{"value": OPERATION_MODE_DRAG, "label": "拖拽"},
	]

## 返回当前已经生效的卡牌操作模式。
## @return String 当前模式的稳定存储值。
func get_operation_mode() -> String:
	return _operation_mode

## 切换并持久化卡牌操作模式。
## 切换前先清理临时卡牌与目标状态，避免两种输入方式之间遗留高亮、缩放或待确认操作。
## @param operation_mode 需要切换到的稳定模式值。
## @return void 无返回值。
func set_operation_mode(operation_mode: String) -> void:
	if not _is_valid_operation_mode(operation_mode):
		push_warning("忽略未知的卡牌操作模式：%s" % operation_mode)
		return

	if _operation_mode == operation_mode:
		return

	_cancel_active_drag()
	clear_click_selection()
	_operation_mode = operation_mode
	SettingsManager.set_setting(OPERATION_MODE_SETTINGS_SECTION, OPERATION_MODE_SETTINGS_KEY, _operation_mode)
	if _settings_panel and _settings_panel.has_method("set_active_mode"):
		_settings_panel.call("set_active_mode", _operation_mode)

## 清除点击模式的待确认卡牌、目标与所有关联高亮。
## 非确认路径会将选中卡牌还原到手牌布局；确认路径则保留节点给行动队列播放飞行表现。
## @param restore_hand_layout 为 true 时将选中卡牌返回正常手牌位置；确认施放时传入 false。
## @return void 无返回值。
func clear_click_selection(restore_hand_layout: bool = true) -> void:
	if _selected_click_card and is_instance_valid(_selected_click_card):
		if restore_hand_layout:
			_restore_click_mode_card_to_hand(_selected_click_card)
		highlight_card(_selected_click_card, false)

	_selected_click_card = null
	_selected_click_target = null
	_apply_target_highlights([])
	_set_click_mode_action_bar_visible(false)

## 取消尚未松开的拖拽卡牌并将其放回手牌布局。
## 模式在拖拽期间改变时不能让卡牌停留在鼠标位置，否则下次输入会使用过期的拖拽状态。
## @return void 无返回值。
func _cancel_active_drag() -> void:
	if not card_being_dragged:
		return

	# 被模式切换中止的卡牌节点，需要回到 PlayerHand 的正常布局。
	var dragged_card: Node2D = card_being_dragged
	card_being_dragged = null
	update_hovered_targets(null, true)
	if player_hand_referencd:
		player_hand_referencd.add_card_to_hand(dragged_card)

## 从本地设置读取操作模式，并将缺失或无效值安全回退为点击模式。
## @return String 经过校验的操作模式值。
func _load_operation_mode() -> String:
	# 从通用配置读取的原始模式值；必须先校验再作为输入分支条件使用。
	var saved_mode: String = str(SettingsManager.get_setting(OPERATION_MODE_SETTINGS_SECTION, OPERATION_MODE_SETTINGS_KEY, OPERATION_MODE_CLICK))
	if _is_valid_operation_mode(saved_mode):
		return saved_mode
	push_warning("已保存的卡牌操作模式无效，已回退为点击模式：%s" % saved_mode)
	return OPERATION_MODE_CLICK

## 判断一个模式值是否属于当前支持的操作模式。
## @param operation_mode 待校验的模式值。
## @return bool 为 true 表示该值可以安全用于卡牌输入。
func _is_valid_operation_mode(operation_mode: String) -> bool:
	return operation_mode == OPERATION_MODE_CLICK or operation_mode == OPERATION_MODE_DRAG

## 判断当前是否处于点击操作模式。
## @return bool 为 true 时输入按“选卡—选目标—确认”处理。
func _is_click_operation_mode() -> bool:
	return _operation_mode == OPERATION_MODE_CLICK

## 更新点击模式操作栏的可见性。
## @param is_visible 为 true 时显示确认/取消按钮，为 false 时隐藏。
## @return void 无返回值。
func _set_click_mode_action_bar_visible(is_visible: bool) -> void:
	if _click_mode_action_bar and _click_mode_action_bar.has_method("set_actions_available"):
		_click_mode_action_bar.call("set_actions_available", is_visible)

## 接收设置面板发出的模式选择请求。
## @param operation_mode 设置面板选择的稳定模式值。
## @return void 无返回值。
func _on_operation_mode_selected(operation_mode: String) -> void:
	set_operation_mode(operation_mode)

## 接收点击模式操作栏的确认请求。
## @return void 无返回值。
func _on_click_mode_confirm_requested() -> void:
	_confirm_click_mode_card()

## 接收点击模式操作栏的取消请求。
## @return void 无返回值。
func _on_click_mode_cancel_requested() -> void:
	clear_click_selection()

## 根据拖拽的卡牌类型，动态计算并更新受影响范围的实体高亮
## @param new_slot 鼠标射线命中的卡槽节点，可能为空。
## @param release_in_hand_area 当前拖拽位置是否回到手牌区（用于避免误判）。
## @return void 无返回值。
func update_hovered_targets(new_slot: Node2D, release_in_hand_area: bool = false):
	# 当前命中卡槽所属的战斗实体；空卡槽命中表示没有显式目标。
	var primary_target: Node = new_slot.get_parent() if new_slot else null
	# 仅保留拖拽模式原有的空白处自我施放预览条件，避免本次抽取改变旧操作的视觉提示。
	# 该布尔值为 true 时，目标范围计算才会在无卡槽命中时显示玩家自身。
	var should_default_to_self: bool = allow_self_cast_on_empty and not release_in_hand_area and is_self_target_card(card_being_dragged)
	_apply_target_highlights(_resolve_intended_targets(card_being_dragged, primary_target, should_default_to_self))

## 更新点击模式当前卡牌和目标的预览高亮。
## 点击模式始终允许以玩家自身作为缺省目标，因此没有选择敌人时也会给出明确反馈。
## @return void 无返回值。
func _update_click_mode_target_highlights() -> void:
	_apply_target_highlights(_resolve_intended_targets(_selected_click_card, _selected_click_target, true))

## 根据卡牌目标类型和主目标计算应高亮的实体集合。
## 该函数被拖拽与点击模式共用，确保相同卡牌在两种输入方式下遵循同一套范围提示规则。
## @param card 需要预览目标范围的卡牌。
## @param primary_target 鼠标悬停或点击选中的主目标；为空时由 default_to_self 决定是否回退。
## @param default_to_self 为 true 时没有主目标也以玩家自身作为默认目标。
## @return Array[Node] 应显示高亮的战斗实体。
func _resolve_intended_targets(card: Variant, primary_target: Node, default_to_self: bool) -> Array[Node]:
	# 计算所得的目标预览集合；它会与上一次高亮状态作差量同步。
	var intended_targets: Array[Node] = []
	if not card or not card.data or (not primary_target and not default_to_self):
		return intended_targets

	# 使用编辑器生成的原生枚举，避免运行时解析 C# 文本。
	# “自身”目标类型对应的跨语言枚举值。
	var target_self = SKILL_TARGETING_TYPE.Value.Self
	# “单体敌人”目标类型对应的跨语言枚举值。
	var target_single_enemy = SKILL_TARGETING_TYPE.Value.SingleEnemy
	# “全体敌人”目标类型对应的跨语言枚举值。
	var target_all_enemies = SKILL_TARGETING_TYPE.Value.AllEnemies
	# “任意单体”目标类型对应的跨语言枚举值。
	var target_any_single = SKILL_TARGETING_TYPE.Value.AnySingleUnit
	# “全体单位”目标类型对应的跨语言枚举值。
	var target_all_units = SKILL_TARGETING_TYPE.Value.AllUnits
	# “随机敌人”目标类型对应的跨语言枚举值。
	var target_random_enemy = SKILL_TARGETING_TYPE.Value.RandomEnemy
	# “以敌人为中心扩散”目标类型对应的跨语言枚举值。
	var target_spread_from_enemy = SKILL_TARGETING_TYPE.Value.SpreadFromEnemy
	# 当前卡牌实际配置的目标类型；技能数据缺失时保留单体敌人的保守默认值。
	var targeting_type: int = target_single_enemy

	# 尝试安全获取目标类型。
	if card.data.get("Skill") != null and card.data.Skill.get("TargetingType") != null:
		targeting_type = int(card.data.Skill.TargetingType)

	match targeting_type:
		target_self:
			intended_targets.append(player_manager)

		target_single_enemy, target_any_single:
			if primary_target:
				intended_targets.append(primary_target)
			elif default_to_self:
				intended_targets.append(player_manager)

		target_all_enemies, target_random_enemy:
			# 全体和随机都会高亮所有敌人，以提示波及范围。
			if battle_manager.monster_manager and battle_manager.monster_manager.active_monsters:
				intended_targets.assign(battle_manager.monster_manager.active_monsters)

		target_all_units:
			# 所有人，包括玩家。
			intended_targets.assign(battle_manager.get_all_combatants())

		target_spread_from_enemy:
			# 扩散逻辑：主目标加上左右相邻敌人；没有敌人主目标时，点击模式回退为玩家自身。
			if primary_target and battle_manager.monster_manager and battle_manager.monster_manager.active_monsters:
				# 当前仍在场的怪物顺序，用于按位置求取相邻扩散目标。
				var monsters = battle_manager.monster_manager.active_monsters
				# 主目标在场上怪物顺序中的位置；-1 说明目标已离场或不属于当前战斗。
				var target_index = monsters.find(primary_target)
				if target_index != -1:
					intended_targets.append(primary_target)
					if target_index > 0:
						intended_targets.append(monsters[target_index - 1])
					if target_index < monsters.size() - 1:
						intended_targets.append(monsters[target_index + 1])
			elif default_to_self:
				intended_targets.append(player_manager)

		_:
			if primary_target:
				intended_targets.append(primary_target)
			elif default_to_self:
				intended_targets.append(player_manager)

	return intended_targets

## 将实体高亮从上一帧状态同步到新的目标集合。
## 统一处理可避免拖拽预览、点击预览和取消操作在视觉状态上相互残留。
## @param intended_targets 本次应保持高亮的实体集合。
## @return void 无返回值。
func _apply_target_highlights(intended_targets: Array[Node]) -> void:
	# 找出需要取消高亮的实体。
	for entity in currently_highlighted_entities:
		if not entity in intended_targets:
			set_entity_highlight(entity, false)

	# 找出需要新增高亮的实体。
	for entity in intended_targets:
		if not entity in currently_highlighted_entities:
			set_entity_highlight(entity, true)

	currently_highlighted_entities = intended_targets

## 辅助函数：统一处理实体的视觉放大和时间轴高亮
## @param entity 需要高亮或取消高亮的战斗实体。
## @param is_highlighted 为 true 时放大高亮，为 false 时恢复正常大小。
## @return void 无返回值。
func set_entity_highlight(entity: Node, is_highlighted: bool):
	if not entity:
		return

	# 处理缩放动画（怪物：统一调用怪物自身的视觉缩放接口，只放大卡面和内部内容，不影响 HealthBar）
	if _is_monster_entity(entity):
		var target_scale = monster_hover_scale if is_highlighted else monster_normal_scale
		if entity.has_method("TweenVisualScale"):
			# 这里复用 Monster.TweenVisualScale，避免拖拽指定目标和敌方行动使用两套不同的放大规则。
			entity.call("TweenVisualScale", target_scale, scale_tween_duration)
		else:
			# 兜底兼容：如果未来出现非 C# Monster 的怪物节点，至少保持旧的卡面缩放表现。
			var tween = create_tween()
			tween.tween_property(entity.get_node("Sprite2D"), "scale", target_scale, scale_tween_duration)
	elif entity.has_node("Sprite2D"):
		# 兼容其它实体：保持旧逻辑，仅缩放贴图
		var target_scale = monster_hover_scale if is_highlighted else monster_normal_scale
		var tween = create_tween()
		tween.tween_property(entity.get_node("Sprite2D"), "scale", target_scale, scale_tween_duration)

	# 处理时间轴的高亮联动
	var timeline = get_node_or_null("../UI/ActionTimeline")
	if timeline:
		timeline.highlight_entity(entity, is_highlighted)

func _is_monster_entity(entity: Node) -> bool:
	return entity is Node2D \
		and entity.has_node("Sprite2D") \
		and entity.has_node("HealthBar")

## 检查卡牌状态是否可用（例如是否被锁上变暗）。
## 这里判断了两种条件：
## 1. 玩家当前的能量是否足够打出该牌
## 2. 战斗状态机是否处于“玩家回合”(PLAYER_TURN)。如果是在排队播放动画或在敌方回合，卡牌强制锁定变暗。
func check_cards_energy():
	if control_lock.is_lock:
		return
	var pm = player_manager
	for card in player_hand_referencd.player_hand_card:
		if pm.energy < card.data.cost or battle_manager.current_state != battle_manager.BattleState.PLAYER_TURN:
			card.lock()
		else:
			card.unlock()

## 监听全局输入事件，并根据当前操作模式分发给拖拽或点击流程。
## 增加条件：如果不处于玩家操作回合（如敌方回合或技能结算时），直接拦截操作。
## @param event Godot 传入的输入事件。
## @return void 无返回值。
func _input(event: InputEvent) -> void:
	if control_lock.is_lock or battle_manager.current_state != battle_manager.BattleState.PLAYER_TURN:
		return

	if _is_click_operation_mode():
		_handle_click_mode_input(event)
	else:
		_handle_drag_mode_input(event)

## 处理与改动前保持一致的按下、拖动、松开卡牌流程。
## @param event Godot 传入的输入事件。
## @return void 无返回值。
func _handle_drag_mode_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		var card = raycast_check_for_card()
		if card:
			start_drag(card)
	elif card_being_dragged:
		finish_drag()

## 处理点击模式的选卡和选敌人操作。
## GUI 控件位于鼠标下方时不处理世界输入，避免点击确认、取消、设置或结束回合时意外改写目标。
## @param event Godot 传入的输入事件。
## @return void 无返回值。
func _handle_click_mode_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return

	if get_viewport().gui_get_hovered_control() != null:
		return

	# 本次鼠标点击命中的最上层手牌；命中手牌优先于目标选择以支持直接改选卡牌。
	var clicked_card = raycast_check_for_card()
	if clicked_card:
		_select_click_mode_card(clicked_card)
		return

	if _selected_click_card:
		_select_click_mode_target_at_mouse()

## 在点击模式中选择一张待确认施放的卡牌。
## @param card 玩家点击命中的卡牌节点。
## @return void 无返回值。
func _select_click_mode_card(card: SkillCard) -> void:
	if not card or card.is_lock or player_manager.energy < card.data.cost:
		return

	if _selected_click_card == card:
		# 再次点击同一张待确认卡牌表示主动撤销整次选择，统一出口会归位卡牌并清除目标与操作栏。
		clear_click_selection()
		return

	if _selected_click_card and _selected_click_card != card and is_instance_valid(_selected_click_card):
		_restore_click_mode_card_to_hand(_selected_click_card)
		highlight_card(_selected_click_card, false)

	_selected_click_card = card
	_selected_click_target = null
	highlight_card(_selected_click_card, true)
	_animate_click_mode_card_selection(_selected_click_card)
	_update_click_mode_target_highlights()
	_set_click_mode_action_bar_visible(true)
	if tooltip_panel:
		tooltip_panel.hide_tooltip()

## 将点击模式选中的卡牌移动到其手牌位置上方。
## 位置基于 hand_position 计算，避免悬停动画或手牌整理过程累积偏移量。
## @param card 已选中的可用手牌节点。
## @return void 无返回值。
func _animate_click_mode_card_selection(card: SkillCard) -> void:
	if not card or not is_instance_valid(card):
		return

	# 选中位置以标准手牌布局为基准，确保多次点击同一张牌不会持续上移。
	var selected_position: Vector2 = card.hand_position + Vector2(0.0, -click_selected_card_lift_distance)
	# 位置 Tween 与卡牌缩放分离，保留既有高亮缩放和工具提示行为。
	var selection_tween: Tween = create_tween()
	selection_tween.tween_property(card, "position", selected_position, click_selected_card_lift_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## 将取消或改选的点击模式卡牌交回 PlayerHand 统一整理。
## @param card 需要恢复到正常手牌布局的卡牌节点。
## @return void 无返回值。
func _restore_click_mode_card_to_hand(card: SkillCard) -> void:
	if not card or not is_instance_valid(card) or not player_hand_referencd:
		return

	# PlayerHand 已知该卡牌时会只播放归位动画，避免重复插入手牌数据。
	player_hand_referencd.add_card_to_hand(card)

## 根据鼠标所在位置选择点击模式的敌人目标。
## 没有命中怪物卡槽时清空显式目标，使确认操作按规则以玩家自身为目标。
## @return void 无返回值。
func _select_click_mode_target_at_mouse() -> void:
	# 鼠标所在位置命中的怪物卡槽；为空时按规则清除敌人目标并预览自身目标。
	var target_slot = raycast_check_for_card_slot_at_position(get_global_mouse_position())
	# 本次点击解析到的候选敌人；它只在点击模式已有待确认卡牌时才会被写入临时选择状态。
	var clicked_target: Node = target_slot.get_parent() if target_slot else null
	if clicked_target and clicked_target == _selected_click_target:
		# 再次点击同一敌人只撤销显式敌人目标，已选卡牌与确认操作仍保留并回退为默认自身目标。
		_selected_click_target = null
	else:
		_selected_click_target = clicked_target
	_update_click_mode_target_highlights()

## 确认点击模式的当前卡牌选择并将其送入既有行动队列。
## 未选择有效敌人时将 PlayerManager 作为显式目标传入，从而实现玩家自身的默认目标规则。
## @return void 无返回值。
func _confirm_click_mode_card() -> void:
	if not _selected_click_card or not is_instance_valid(_selected_click_card):
		clear_click_selection()
		return
	if control_lock.is_lock or battle_manager.current_state != battle_manager.BattleState.PLAYER_TURN:
		clear_click_selection()
		return
	if player_manager.energy < _selected_click_card.data.cost:
		clear_click_selection()
		return

	# 确认瞬间仍有效的施放目标；没有有效敌人时固定为 PlayerManager。
	var confirmed_target: Node = _get_confirmed_click_mode_target()
	# 提前保存节点引用后清理点击状态，确认路径不再触发手牌归位动画，避免抢占随后的飞行动画。
	var confirmed_card: SkillCard = _selected_click_card
	clear_click_selection(false)
	player_manager.consume_energy(confirmed_card.data.cost)
	deck_manager.play_card(confirmed_card, confirmed_target)

## 返回点击模式确认时仍然有效的目标。
## 目标在选择后死亡、离开场上或从未选择敌人时，都会安全回退到玩家自身。
## @return Node 用于既有 DeckManager.play_card 的目标节点。
func _get_confirmed_click_mode_target() -> Node:
	if _selected_click_target and is_instance_valid(_selected_click_target) and battle_manager.monster_manager and battle_manager.monster_manager.active_monsters.has(_selected_click_target):
		return _selected_click_target
	return player_manager

## 当鼠标按下并检测到点中某张可用的卡时触发，开始拖拽逻辑。
func start_drag(card):
	# 如果当前能量小于该卡牌的消耗则不能拖拽
	if player_manager.energy < card.data.cost:
		return
	card_being_dragged = card
	# 记录鼠标点击位置与卡牌原点之间的差值
	drag_offset = card.position - get_global_mouse_position()

	var tween = create_tween()
	tween.tween_property(card, "scale", card_drag_scale, scale_tween_duration)

	if tooltip_panel:
		tooltip_panel.hide_tooltip()

## 辅助函数：判断卡牌是否为【对自己使用】
func is_self_target_card(card: SkillCard) -> bool:
	if not card or not card.data:
		return false
	var target_self = SKILL_TARGETING_TYPE.Value.Self
	var targeting_type: int = SKILL_TARGETING_TYPE.Value.SingleEnemy
	# 尝试安全获取目标类型
	if card.data.get("Skill") != null and card.data.Skill.get("TargetingType") != null:
		targeting_type = int(card.data.Skill.TargetingType)
	return targeting_type == target_self

## 当鼠标松开时触发，结束拖拽判定，主要用射线检测当前位置是否在“卡槽”或目标身上
## @return void 无返回值。
func finish_drag():
	var tween = create_tween()
	tween.tween_property(card_being_dragged, "scale", card_hover_scale, scale_tween_duration)

	# 先判断是否回到手牌区，用于避免自我施放卡在回收时误触。
	var release_in_hand_area: bool = false
	if player_hand_referencd and player_hand_referencd.has_method("is_release_in_hand_area"):
		release_in_hand_area = player_hand_referencd.is_release_in_hand_area(card_being_dragged.global_position)

	# 通过射线获取是否命中了一个接收区域
	var card_slot_found = raycast_check_for_card_slot()
	if card_slot_found:
		# 命中目标：扣除能量
		player_manager.consume_energy(card_being_dragged.data.cost)
		# 让DeckManager将卡牌推入战斗状态机的 Action Queue (行动队列)
		deck_manager.play_card(card_being_dragged, card_slot_found.get_parent())
	else:
		# 如果拖动后没进入有效区域(比如丢到空白处)，则卡牌原路弹回玩家手中
		# 特例：当卡牌是【对自己使用】类型时，允许直接在空白处施放
		if allow_self_cast_on_empty and is_self_target_card(card_being_dragged) and not release_in_hand_area:
			player_manager.consume_energy(card_being_dragged.data.cost)
			deck_manager.play_card(card_being_dragged)
		else:
			player_hand_referencd.add_card_to_hand(card_being_dragged)

	# 松开鼠标时，恢复最后悬停的怪物的缩放
	# 这里强制按“在手牌区”处理，确保不再触发自我施放高亮
	update_hovered_targets(null, true)

	card_being_dragged = null

## 初始化卡牌本身的鼠标悬停信号，在卡牌实例化时绑定过来
func connect_card_signals(card):
	card.connect("hovered", on_hovered_over_card)
	card.connect("hovered_off", on_hovered_off_card)

func on_hovered_over_card(card):
	if !card_being_dragged:
		is_hovering_on_card = true
		var top_card = raycast_check_for_card()
		if top_card:
			highlight_card(top_card, true)
		else:
			highlight_card(card, true)

func on_hovered_off_card(card):
	if !card_being_dragged:
		highlight_card(card, false)
		# Check if hovered off card straight on to another card
		var new_card_hovered = raycast_check_for_card()
		if new_card_hovered:
			highlight_card(new_card_hovered, true)
		else:
			is_hovering_on_card = false
			if tooltip_panel:
				tooltip_panel.hide_tooltip()

## 设置单张卡牌的高亮（视觉放大及置于顶层渲染）
func highlight_card(card, hovered):
	# 【修复】安全检查：如果传入的节点为空，或者它根本不是卡牌，则直接返回
	if not card is SkillCard:
		return

	# 锁定卡牌不应再次获得悬停高亮，但仍必须允许取消流程恢复其原始缩放和层级。
	if card.is_lock and hovered:
		return

	if hovered:
		var tween = create_tween()
		tween.tween_property(card, "scale", card_hover_scale, scale_tween_duration)
		card.z_index = 2
		if tooltip_panel and card.data:
			tooltip_panel.show_tooltip(card.data.CardName, card.data.Description)
	else:
		var tween = create_tween()
		tween.tween_property(card, "scale", card_normal_scale, scale_tween_duration)
		card.z_index = 1

## 光线投射检测（射线检测），用于检查并获取鼠标落点位置最上层的卡牌。
func raycast_check_for_card():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD
	var result = space_state.intersect_point(parameters)

	# 【修复】增加类型过滤：只保留父节点确实为 SkillCard 类型的碰撞体
	var valid_results = []
	for res in result:
		var parent = res.collider.get_parent()
		if parent is SkillCard:
			valid_results.append(res)

	if valid_results.size() > 0:
		return get_card_with_highest_z_index(valid_results)
	return null

## 同样是通过射线检测目标卡槽（通常在实体身上）
func raycast_check_for_card_slot():
	if not card_being_dragged:
		return null
	return raycast_check_for_card_slot_at_position(card_being_dragged.global_position)

## 使用给定的世界坐标检测目标卡槽。
## 拖拽模式传入卡牌中心，点击模式传入鼠标位置，以复用同一套怪物卡槽碰撞层规则。
## @param query_position 需要进行点查询的世界坐标。
## @return Node2D 命中的卡槽节点；没有命中时返回 null。
func raycast_check_for_card_slot_at_position(query_position: Vector2):
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()

	# 拖拽和点击共享该查询；调用方决定使用卡牌中心或鼠标位置。
	parameters.position = query_position

	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD_SLOT
	var result = space_state.intersect_point(parameters)
	if result.size() > 0:
		return result[0].collider.get_parent()
	return null

## 辅助工具：如果在密集手牌区域多张牌重叠，则选取层级(Z-index)最高的那张来交互
func get_card_with_highest_z_index(cards):
	var highest_z_card = cards[0].collider.get_parent()
	var highest_z_index = highest_z_card.z_index
	for i in range(1, cards.size()):
		var current_card = cards[i].collider.get_parent()
		if current_card.z_index > highest_z_index:
			highest_z_card = current_card
			highest_z_index = current_card.z_index
	return highest_z_card
