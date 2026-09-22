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
# 拖拽虚影的固定不透明度；50% 能清楚区分目标预览与仍留在手牌区的真实卡牌。
@export_range(0.0, 1.0, 0.05) var card_drag_ghost_opacity: float = 0.5
@export var monster_normal_scale: Vector2 = Vector2(1.5, 1.5) ## 怪物正常大小
@export var monster_hover_scale: Vector2 = Vector2(1.6, 1.6) ## 怪物被选中悬停时放大
@export var scale_tween_duration: float = 0.08 ## 缩放动画过度时间

@export_group("目标选择视觉参数")
# 可手动指定目标时呼吸动画的最小缩放，略大于正常卡面以提示可点击性。
@export var monster_selectable_min_scale: Vector2 = Vector2(1.53, 1.53)
# 可手动指定目标时呼吸动画的最大缩放，必须大于最小缩放以形成可感知的循环变化。
@export var monster_selectable_max_scale: Vector2 = Vector2(1.56, 1.56)
# 主目标选中后的缩放，必须大于悬停和次级目标以表达目标优先级。
@export var monster_primary_selected_scale: Vector2 = Vector2(1.66, 1.66)
# 次级目标选中后的缩放，必须小于主目标但大于正常卡面以表达扩散影响范围。
@export var monster_secondary_selected_scale: Vector2 = Vector2(1.60, 1.60)
# 次级目标在鼠标悬停时的二次放大倍率，必须介于次级选中与主选中之间以保留主次层级。
@export var monster_secondary_hover_scale: Vector2 = Vector2(1.64, 1.64)
# 呼吸动画从最小缩放移动到最大缩放所需时间，较短节奏能保持目标提示可见但不干扰战斗阅读。
@export var target_selection_pulse_half_duration: float = 0.25
# 不可选目标叠乘的颜色倍率，保留轮廓信息同时明显降低其视觉权重。
@export var target_selection_unavailable_modulate: Color = Color(0.45, 0.45, 0.45, 1.0)
# 已选中目标描边的绿色，用统一参数保证所有目标类型的确认反馈一致。
@export var target_selection_outline_color: Color = Color(0.25, 1.0, 0.35, 1.0)
# 次级目标描边使用更浅且略透明的绿色，保留扩散范围提示但避免与主目标争夺视觉焦点。
@export var target_selection_secondary_outline_color: Color = Color(0.55, 1.0, 0.65, 0.80)
# 已选中目标描边的像素宽度，默认值需要在卡面缩放后仍保持可辨识。
@export_range(1.0, 12.0, 0.5) var target_selection_outline_width: float = 2.0

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
# 当前跟随鼠标的临时卡牌虚影；它只提供拖拽预览，绝不能进入手牌或行动队列。
var _card_drag_ghost: Node2D = null
var is_hovering_on_card:bool
var player_hand_referencd #玩家手牌引用
var drag_offset: Vector2 # 用于记录拖拽偏移量
#var currently_hovered_slot: Node2D = null # 记录当前被悬停的卡槽，修改为下面
var currently_highlighted_entities: Array[Node] = [] # 记录当前被悬停的卡槽
# 目标选择视觉状态常量由 CardManager 统一拥有，避免输入模式和怪物卡面各自解释状态含义。
enum TargetSelectionVisualState {
	NORMAL,
	AVAILABLE,
	HOVERED,
	PRIMARY_SELECTED,
	SECONDARY_SELECTED,
	SECONDARY_HOVERED,
	UNAVAILABLE,
}
# 上一轮已应用到怪物卡的视觉状态，以实体为键避免 _process 每帧重复创建 Tween。
var _target_selection_visual_states: Dictionary = {}
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
		if control_lock.is_lock or battle_manager.current_state != battle_manager.BattleState.PLAYER_TURN:
			# 玩家失去输入权时立即回收虚影，避免结算或敌方回合残留不可操作的拖拽状态。
			_cancel_active_drag()
		else:
			# 虚影独占鼠标跟随；真实手牌继续停在 PlayerHand 已计算的标准位置。
			var drag_preview_position: Vector2 = _update_card_drag_ghost_position()
			# 检测虚影当前位置命中的卡槽，将结果交由既有多目标高亮方法处理。
			var card_slot_found: Node2D = raycast_check_for_card_slot_at_position(drag_preview_position)
			# 同步检测虚影是否回到手牌区，避免自身目标卡在回收路径上误触施放。
			var release_in_hand_area: bool = false
			if player_hand_referencd and player_hand_referencd.has_method("is_release_in_hand_area"):
				release_in_hand_area = player_hand_referencd.is_release_in_hand_area(drag_preview_position)
			update_hovered_targets(card_slot_found, release_in_hand_area)
	elif _is_click_operation_mode() and _selected_click_card:
		# 点击模式没有拖拽位置更新，需主动读取鼠标下目标以提供未点击前的悬停放大反馈。
		_update_click_mode_target_highlights()

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
	# 先同步确认按钮再隐藏操作栏：隐藏动作会恢复按钮的默认可用状态，
	# 从而保证禁用状态永远不会跨越两次选择残留下来。
	_refresh_click_mode_confirm_availability()
	_set_click_mode_action_bar_visible(false)

## 取消尚未松开的拖拽预览并清理其目标视觉。
## 真实卡从未离开 PlayerHand，因此取消时不能额外触发归位或弃牌表现。
## @return void 无返回值。
func _cancel_active_drag() -> void:
	if not card_being_dragged and not _card_drag_ghost:
		return

	# 先关闭真实卡的拖拽状态，再回收虚影，防止同一帧的输入继续读取过期预览节点。
	card_being_dragged = null
	_clear_card_drag_ghost()
	update_hovered_targets(null, true)

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
	# 只有拖拽未回到手牌区且命中目标时，才把悬停目标预览为主选中状态。
	var is_primary_preview: bool = primary_target != null and not release_in_hand_area
	# 只有自身目标牌在非回手拖拽时沿用既有的自身默认目标时间轴高亮。
	var should_default_to_self: bool = allow_self_cast_on_empty and not release_in_hand_area and is_self_target_card(card_being_dragged)
	_refresh_target_selection_visuals(card_being_dragged, primary_target, is_primary_preview, should_default_to_self)

## 更新点击模式当前卡牌和目标的预览高亮，并同步确认按钮的可用性。
## 点击模式不再无条件以玩家自身作为缺省目标：只有自身目标牌才这样预览，
## 需要显式敌人的卡牌在未选中敌人时既不高亮玩家，也不允许点击“确定”。
## 该函数是点击模式选卡、选目标与每帧刷新共用的唯一出口。
## @return void 无返回值。
func _update_click_mode_target_highlights() -> void:
	if not _selected_click_card:
		_apply_target_highlights([])
		_refresh_click_mode_confirm_availability()
		return

	# 自动目标牌不能在点击模式保存敌人主目标，否则确认后会把该敌人错误传入单体飞行动画。
	var targeting_type: int = _get_card_targeting_type(_selected_click_card)
	if not _requires_manual_enemy_target(targeting_type):
		_selected_click_target = null
		# 只有【对自己使用】的卡牌才以玩家为缺省预览目标，判据与拖拽模式保持完全一致。
		_refresh_target_selection_visuals(_selected_click_card, null, false, is_self_target_card(_selected_click_card))
		_refresh_click_mode_confirm_availability()
		return

	# 点击模式在尚未点击目标时读取鼠标下卡槽，以显示仅放大、不描边的悬停反馈。
	var hovered_slot: Node2D = raycast_check_for_card_slot_at_position(get_global_mouse_position())
	# 鼠标下的敌人仅用于悬停预览，真正确认的主目标仍由点击状态独立保存。
	var hovered_target: Node = hovered_slot.get_parent() if hovered_slot else null
	# 已点击目标优先于悬停目标，确保鼠标移开后主选中状态仍能稳定保留。
	var primary_target: Node = _selected_click_target if _selected_click_target else hovered_target
	# 只有已点击目标才在点击模式中显示绿色主选中状态。
	var is_primary_selected: bool = _selected_click_target != null
	# 已选目标与当前鼠标目标分别传入；这样确认前仍可观察其他敌人的悬停放大，不会丢失已选目标描边。
	# 第四参数固定为 false：需要显式敌人的卡牌不能退回玩家自身，
	# 否则未选中敌人时时间轴会高亮玩家，向玩家暗示这张牌可以打自己，而确认按钮实际处于禁用状态。
	_refresh_target_selection_visuals(_selected_click_card, primary_target, is_primary_selected, false, hovered_target)
	_refresh_click_mode_confirm_availability()

## 从卡牌数据读取目标类型，并在数据缺失时使用既有的单体敌人保守回退。
## @param card 需要读取目标类型的卡牌对象。
## @return int 生成的 SkillTargetingType 枚举值。
func _get_card_targeting_type(card: Variant) -> int:
	# 单体敌人是历史逻辑的默认目标类型，缺少数据时继续使用它可保持既有结算行为。
	var targeting_type: int = SKILL_TARGETING_TYPE.Value.SingleEnemy
	if card and card.data and card.data.get("Skill") != null and card.data.Skill.get("TargetingType") != null:
		targeting_type = int(card.data.Skill.TargetingType)
	return targeting_type

## 判断目标类型是否必须由玩家点击一名敌人作为主目标。
## 自动目标与自身目标必须返回 false，保证点击模式不会把鼠标下敌人错误写入行动动画目标。
## @param targeting_type 当前卡牌的 SkillTargetingType 枚举值。
## @return bool 为 true 时允许保存并确认一名显式敌人主目标。
func _requires_manual_enemy_target(targeting_type: int) -> bool:
	return targeting_type == SKILL_TARGETING_TYPE.Value.SingleEnemy \
		or targeting_type == SKILL_TARGETING_TYPE.Value.AnySingleUnit \
		or targeting_type == SKILL_TARGETING_TYPE.Value.SpreadFromEnemy

## 判断一名敌人是否可以作为点击模式的显式施放目标。
## 目标必须在选择之后仍然存活且留在当前战场，避免选中后被击杀或已离场的敌人仍能通过确认。
## @param target 待校验的候选敌人节点，允许为空。
## @return bool 为 true 时该节点可以安全地作为显式主目标传入行动队列。
func _is_valid_click_mode_enemy_target(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not battle_manager or not battle_manager.monster_manager:
		return false
	return battle_manager.monster_manager.active_monsters.has(target)

## 判断一张卡牌与它当前的待确认目标是否满足点击模式的施放条件。
## 该函数只依赖入参而不读取临时选择状态，因此可以脱离战斗场景单独验证目标规则。
## @param card 待确认施放的卡牌；为空或节点已失效时视为不可确认。
## @param target 玩家显式选中的敌人，允许为空。
## @return bool 为 true 时允许扣除能量并把该卡牌交给行动队列。
func _is_click_selection_target_ready(card: Variant, target: Node) -> bool:
	if not card or not is_instance_valid(card):
		return false

	# 自动目标与自身目标牌不需要玩家指定敌人，选中卡牌本身即可确认。
	if not _requires_manual_enemy_target(_get_card_targeting_type(card)):
		return true

	# 单体、任意单体与扩散牌必须指向一名仍在场的敌人：
	# 缺少有效敌人时确认会把玩家自身当成目标，因此这类卡牌在未选目标时必须拒绝确认。
	return _is_valid_click_mode_enemy_target(target)

## 判断当前点击模式选择是否已经具备可施放的目标。
## @return bool 为 true 时点击模式操作栏的“确定”按钮应保持可用。
func _can_confirm_click_selection() -> bool:
	return _is_click_selection_target_ready(_selected_click_card, _selected_click_target)

## 把当前选择的确认可用性同步到点击模式操作栏。
## 让“必须指定敌人的卡牌不能对自己使用”这条规则在 UI 层直接可见，而不是只在点下按钮后才被拒绝。
## @return void 无返回值。
func _refresh_click_mode_confirm_availability() -> void:
	if _click_mode_action_bar and _click_mode_action_bar.has_method("set_confirm_available"):
		_click_mode_action_bar.call("set_confirm_available", _can_confirm_click_selection())

## 返回当前仍有效的场上怪物，集中过滤已删除节点以避免目标预览访问过期实体。
## @return Array[Node] 当前可展示目标视觉的怪物节点列表。
func _get_active_monsters() -> Array[Node]:
	# 返回数组只保存本次刷新仍有效的怪物，不持久化战斗管理器的可变数组引用。
	var active_monsters: Array[Node] = []
	if not battle_manager or not battle_manager.monster_manager or not battle_manager.monster_manager.active_monsters:
		return active_monsters

	for monster in battle_manager.monster_manager.active_monsters:
		if is_instance_valid(monster):
			active_monsters.append(monster)
	return active_monsters

## 根据当前卡牌、主目标与输入阶段推导所有敌人怪物卡的视觉状态。
## @param card 当前点击或拖拽中的卡牌；为空时会清除全部目标选择表现。
## @param primary_target 鼠标悬停或已点击的敌人主目标；自动目标卡可以为空。
## @param is_primary_selected 为 true 时将主目标作为已选中预览，否则只显示悬停状态。
## @param default_to_self 为 true 时沿用既有逻辑，将无显式敌人目标的预览回退为玩家自身。
## @param hovered_target 当前鼠标悬停的敌人；已确认主目标存在时仍用于显示其他敌人的悬停放大。
## @return void 无返回值。
func _refresh_target_selection_visuals(card: Variant, primary_target: Node, is_primary_selected: bool, default_to_self: bool, hovered_target: Node = null) -> void:
	if not card or not card.data:
		_apply_target_visual_states({})
		return

	# 当前在场怪物是唯一需要渲染目标选择状态的卡面集合，玩家 HUD 不纳入本功能。
	var active_monsters: Array[Node] = _get_active_monsters()
	# 默认先将所有敌人标记为不可选，再按目标类型覆盖为可选或选中状态。
	var next_states: Dictionary = {}
	for monster in active_monsters:
		next_states[monster] = TargetSelectionVisualState.UNAVAILABLE

	# 当前卡牌的目标类型来自既有生成枚举，不引入新的目标规则或跨语言数据格式。
	var targeting_type: int = _get_card_targeting_type(card)
	match targeting_type:
		SKILL_TARGETING_TYPE.Value.Self:
			# 自身目标没有敌人候选；保留全部不可选状态即可满足敌人变暗要求。
			pass

		SKILL_TARGETING_TYPE.Value.SingleEnemy, SKILL_TARGETING_TYPE.Value.AnySingleUnit:
			for monster in active_monsters:
				next_states[monster] = TargetSelectionVisualState.AVAILABLE
			_apply_primary_target_visual_state(next_states, active_monsters, primary_target, is_primary_selected)

		SKILL_TARGETING_TYPE.Value.SpreadFromEnemy:
			for monster in active_monsters:
				next_states[monster] = TargetSelectionVisualState.AVAILABLE
			_apply_spread_target_visual_states(next_states, active_monsters, primary_target, is_primary_selected)

		SKILL_TARGETING_TYPE.Value.AllEnemies, SKILL_TARGETING_TYPE.Value.RandomEnemy, SKILL_TARGETING_TYPE.Value.AllUnits:
			# 自动目标卡不等待鼠标或点击确认；所有受影响敌人直接显示已选中反馈。
			for monster in active_monsters:
				next_states[monster] = TargetSelectionVisualState.PRIMARY_SELECTED

		_:
			# 未识别类型沿用旧的单体敌人回退，避免新视觉层扩大未知卡牌的行为差异。
			for monster in active_monsters:
				next_states[monster] = TargetSelectionVisualState.AVAILABLE
			_apply_primary_target_visual_state(next_states, active_monsters, primary_target, is_primary_selected)

	_apply_hovered_target_visual_state(next_states, active_monsters, primary_target, hovered_target)

	# 时间轴继续消费旧的范围解析结果，确保本功能只替换怪物卡面表现而不改变行动提示语义。
	var timeline_targets: Array[Node] = _resolve_intended_targets(card, primary_target, default_to_self)
	_apply_target_visual_states(next_states, timeline_targets, true)

## 为单体目标设置主选中或悬停状态，并拒绝场外或已失效节点。
## @param next_states 本次刷新即将应用的实体状态映射。
## @param active_monsters 当前仍在场的有效怪物列表。
## @param primary_target 需要显示主目标反馈的候选节点。
## @param is_primary_selected 为 true 时显示主选中，否则显示悬停。
## @return void 无返回值。
func _apply_primary_target_visual_state(next_states: Dictionary, active_monsters: Array[Node], primary_target: Node, is_primary_selected: bool) -> void:
	if primary_target and is_instance_valid(primary_target) and primary_target in active_monsters:
		next_states[primary_target] = TargetSelectionVisualState.PRIMARY_SELECTED if is_primary_selected else TargetSelectionVisualState.HOVERED

## 为扩散目标设置主目标与左右相邻次级目标，未确认时只保留主目标的悬停反馈。
## @param next_states 本次刷新即将应用的实体状态映射。
## @param active_monsters 当前仍在场的有效怪物列表，数组顺序定义左右相邻关系。
## @param primary_target 需要作为扩散中心的候选节点。
## @param is_primary_selected 为 true 时同时展示主/次级选中状态。
## @return void 无返回值。
func _apply_spread_target_visual_states(next_states: Dictionary, active_monsters: Array[Node], primary_target: Node, is_primary_selected: bool) -> void:
	if not primary_target or not is_instance_valid(primary_target):
		return

	# 主目标的数组索引既用于验证其仍在场，也用于保持既有左右相邻扩散规则。
	var primary_index: int = active_monsters.find(primary_target)
	if primary_index == -1:
		return

	next_states[primary_target] = TargetSelectionVisualState.PRIMARY_SELECTED if is_primary_selected else TargetSelectionVisualState.HOVERED
	if not is_primary_selected:
		return

	if primary_index > 0:
		# 左侧相邻怪物只有在主目标已确认或拖拽预览时才显示次级绿色描边。
		var left_secondary_target: Node = active_monsters[primary_index - 1]
		next_states[left_secondary_target] = TargetSelectionVisualState.SECONDARY_SELECTED
	if primary_index < active_monsters.size() - 1:
		# 右侧相邻怪物与左侧使用相同状态，避免扩散范围在两个方向表现不一致。
		var right_secondary_target: Node = active_monsters[primary_index + 1]
		next_states[right_secondary_target] = TargetSelectionVisualState.SECONDARY_SELECTED

## 在已确认主目标后，仍为其他鼠标悬停敌人保留独立放大反馈。
## 已在扩散范围内的次级目标会保留浅绿色描边，并进入独立的二次放大状态。
## @param next_states 本次刷新即将应用的实体状态映射。
## @param active_monsters 当前仍在场的有效怪物列表。
## @param primary_target 已确认或预览中的主目标；它必须保留主选中样式。
## @param hovered_target 当前鼠标下的候选敌人。
## @return void 无返回值。
func _apply_hovered_target_visual_state(next_states: Dictionary, active_monsters: Array[Node], primary_target: Node, hovered_target: Node) -> void:
	if hovered_target == null or not is_instance_valid(hovered_target) or hovered_target == primary_target or active_monsters.find(hovered_target) == -1:
		return

	# 读取原状态以识别当前鼠标是否落在已由扩散范围确认的次级目标上。
	var current_state: int = int(next_states.get(hovered_target, TargetSelectionVisualState.NORMAL))
	if current_state == TargetSelectionVisualState.SECONDARY_SELECTED:
		# 次级目标悬停不得降级为普通悬停，否则会错误移除其浅绿色范围描边。
		next_states[hovered_target] = TargetSelectionVisualState.SECONDARY_HOVERED
		return

	# 悬停只覆盖当前鼠标下的其他普通敌人，主选目标及其确认描边继续稳定保留。
	next_states[hovered_target] = TargetSelectionVisualState.HOVERED

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

	# 目标类型解析集中在共享函数内，避免视觉预览与自我施放判断对缺失数据做出不同回退。
	var targeting_type: int = _get_card_targeting_type(card)

	match targeting_type:
		SKILL_TARGETING_TYPE.Value.Self:
			intended_targets.append(player_manager)

		SKILL_TARGETING_TYPE.Value.SingleEnemy, SKILL_TARGETING_TYPE.Value.AnySingleUnit:
			if primary_target:
				intended_targets.append(primary_target)
			elif default_to_self:
				intended_targets.append(player_manager)

		SKILL_TARGETING_TYPE.Value.AllEnemies, SKILL_TARGETING_TYPE.Value.RandomEnemy:
			# 全体和随机都会高亮所有敌人，以提示波及范围。
			if battle_manager.monster_manager and battle_manager.monster_manager.active_monsters:
				intended_targets.assign(battle_manager.monster_manager.active_monsters)

		SKILL_TARGETING_TYPE.Value.AllUnits:
			# 所有人，包括玩家。
			intended_targets.assign(battle_manager.get_all_combatants())

		SKILL_TARGETING_TYPE.Value.SpreadFromEnemy:
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
	# 兼容旧调用入口：缺少完整状态语义时，旧高亮集合仍按主选中状态呈现。
	var legacy_states: Dictionary = {}
	for entity in intended_targets:
		legacy_states[entity] = TargetSelectionVisualState.PRIMARY_SELECTED
	_apply_target_visual_states(legacy_states)

## 将本次状态映射与上一轮作差后应用到怪物卡，并同步既有时间轴高亮。
## @param next_states 当前所有需要显示目标选择状态的怪物卡映射。
## @return void 无返回值。
func _apply_target_visual_states(next_states: Dictionary, timeline_targets: Array[Node] = [], use_explicit_timeline_targets: bool = false) -> void:
	# 先还原已离开目标选择集合的旧实体，避免取消、目标死亡或切换模式后遗留边框与呼吸。
	for entity in _target_selection_visual_states:
		if is_instance_valid(entity) and not next_states.has(entity):
			_apply_target_visual_state(entity, TargetSelectionVisualState.NORMAL)

	# 仅在状态发生变化时创建新的怪物 Tween，点击模式的每帧悬停检查不会造成动画抖动。
	for entity in next_states:
		if not is_instance_valid(entity):
			continue
		# 从映射读取的值始终是本地枚举整数，显式转换可避免动态 Dictionary 值参与分支时类型漂移。
		var next_state: int = int(next_states[entity])
		if not _target_selection_visual_states.has(entity) or int(_target_selection_visual_states[entity]) != next_state:
			_apply_target_visual_state(entity, next_state)

	_target_selection_visual_states = next_states.duplicate()
	_sync_target_timeline_highlights(next_states, timeline_targets, use_explicit_timeline_targets)

## 将单个怪物卡切换到指定目标选择状态，并通过 C# 接口保持血条不受卡面缩放影响。
## @param entity 需要更新视觉状态的怪物节点。
## @param visual_state TargetSelectionVisualState 枚举值。
## @return void 无返回值。
func _apply_target_visual_state(entity: Node, visual_state: int) -> void:
	if not _is_monster_entity(entity):
		return

	# 默认表现对应正常卡面；后续状态只覆盖缩放、边框或不可选颜色这些必要差异。
	var target_scale: Vector2 = monster_normal_scale
	# 不可选状态只降低怪物卡面及内部内容的亮度，血条继续保持可读。
	var is_dimmed: bool = visual_state == TargetSelectionVisualState.UNAVAILABLE
	# 次级选中和次级悬停共用浅绿色描边，避免鼠标反馈抹去已经确认的扩散范围。
	var is_secondary_outline: bool = visual_state == TargetSelectionVisualState.SECONDARY_SELECTED or visual_state == TargetSelectionVisualState.SECONDARY_HOVERED
	# 主选中、次级选中、次级悬停和自动目标都需要显示确认描边。
	var show_outline: bool = visual_state == TargetSelectionVisualState.PRIMARY_SELECTED or is_secondary_outline
	# 次级目标使用更淡的绿色，主选中与自动选中继续沿用主描边颜色。
	var outline_color: Color = target_selection_secondary_outline_color if is_secondary_outline else target_selection_outline_color

	match visual_state:
		TargetSelectionVisualState.HOVERED:
			target_scale = monster_hover_scale
		TargetSelectionVisualState.PRIMARY_SELECTED:
			target_scale = monster_primary_selected_scale
		TargetSelectionVisualState.SECONDARY_SELECTED:
			target_scale = monster_secondary_selected_scale
		TargetSelectionVisualState.SECONDARY_HOVERED:
			target_scale = monster_secondary_hover_scale

	if visual_state == TargetSelectionVisualState.AVAILABLE and entity.has_method("StartTargetSelectionPulse"):
		entity.call("StartTargetSelectionPulse", monster_selectable_min_scale, monster_selectable_max_scale, target_selection_pulse_half_duration)
		return

	if visual_state == TargetSelectionVisualState.NORMAL and entity.has_method("ResetTargetSelectionVisual"):
		entity.call("ResetTargetSelectionVisual", monster_normal_scale, scale_tween_duration)
		return

	if entity.has_method("ApplyTargetSelectionVisual"):
		entity.call("ApplyTargetSelectionVisual", target_scale, is_dimmed, target_selection_unavailable_modulate, show_outline, outline_color, target_selection_outline_width, scale_tween_duration)
		return

	# 兜底怪物缺少新接口时仍恢复旧缩放行为，避免自定义卡面阻断目标选择流程。
	var fallback_sprite: Sprite2D = entity.get_node_or_null("Sprite2D")
	if fallback_sprite:
		fallback_sprite.modulate = target_selection_unavailable_modulate if is_dimmed else Color.WHITE
		var fallback_tween: Tween = create_tween()
		fallback_tween.tween_property(fallback_sprite, "scale", target_scale, scale_tween_duration)

## 根据选中状态映射维护既有行动时间轴高亮，不把可选或不可选状态错误写入时间轴。
## @param visual_states 当前所有怪物卡的目标选择状态映射。
## @param timeline_targets 既有范围解析得到的时间轴目标集合。
## @param use_explicit_timeline_targets 为 true 时优先使用 timeline_targets，保留旧的范围提示语义。
## @return void 无返回值。
func _sync_target_timeline_highlights(visual_states: Dictionary, timeline_targets: Array[Node] = [], use_explicit_timeline_targets: bool = false) -> void:
	# 时间轴可继续使用旧范围解析集合；兼容入口没有该集合时才从主/次级视觉状态推导。
	var timeline_highlighted_entities: Array[Node] = []
	if use_explicit_timeline_targets:
		for entity in timeline_targets:
			if is_instance_valid(entity):
				timeline_highlighted_entities.append(entity)
	else:
		for entity in visual_states:
			var visual_state: int = int(visual_states[entity])
			if visual_state == TargetSelectionVisualState.PRIMARY_SELECTED or visual_state == TargetSelectionVisualState.SECONDARY_SELECTED or visual_state == TargetSelectionVisualState.SECONDARY_HOVERED:
				timeline_highlighted_entities.append(entity)

	# 找到行动时间轴后再同步，保持战斗场景缺少该可选 UI 时的安全降级。
	var timeline: Node = get_node_or_null("../UI/ActionTimeline")
	if not timeline:
		currently_highlighted_entities = timeline_highlighted_entities
		return

	for entity in currently_highlighted_entities:
		if is_instance_valid(entity) and not entity in timeline_highlighted_entities:
			timeline.highlight_entity(entity, false)
	for entity in timeline_highlighted_entities:
		if not entity in currently_highlighted_entities:
			timeline.highlight_entity(entity, true)

	currently_highlighted_entities = timeline_highlighted_entities

## 辅助函数：统一处理实体的视觉放大和时间轴高亮
## @param entity 需要高亮或取消高亮的战斗实体。
## @param is_highlighted 为 true 时放大高亮，为 false 时恢复正常大小。
## @return void 无返回值。
func set_entity_highlight(entity: Node, is_highlighted: bool):
	if not entity:
		return

	# 保留旧方法供动态调用方兼容，并将其映射到新的完整视觉状态接口。
	var legacy_states: Dictionary = {}
	if is_highlighted:
		legacy_states[entity] = TargetSelectionVisualState.PRIMARY_SELECTED
	_apply_target_visual_states(legacy_states)

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

	# 鼠标下的 GUI 控件用于阻止设置、确认和结束回合等界面误触；怪物卡面控件则必须放行给物理卡槽查询。
	var hovered_control: Control = get_viewport().gui_get_hovered_control()
	if hovered_control and not _is_monster_card_presentation_control(hovered_control):
		return

	# 本次鼠标点击命中的最上层手牌；命中手牌优先于目标选择以支持直接改选卡牌。
	var clicked_card = raycast_check_for_card()
	if clicked_card:
		_select_click_mode_card(clicked_card)
		return

	if _selected_click_card:
		_select_click_mode_target_at_mouse()

## 判断 GUI 控件是否属于怪物卡面的纯展示节点。
## 通过父链识别可覆盖 MonsterAttribute 的动态子控件，避免名称、属性、元素等展示层阻挡敌人目标选择。
## @param control 当前鼠标下被 GUI 系统命中的控件。
## @return bool 为 true 时应继续执行怪物卡槽的目标选择。
func _is_monster_card_presentation_control(control: Control) -> bool:
	# 从当前控件逐级向上查找怪物根节点，保证不依赖固定的属性栏或标签节点名称。
	var current_node: Node = control
	while current_node:
		if _is_monster_entity(current_node):
			return true
		current_node = current_node.get_parent()
	return false

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
	# 全体、随机、全体单位和自身等自动目标牌不接受敌人点击，避免产生错误的单体表现目标。
	if not _selected_click_card or not _requires_manual_enemy_target(_get_card_targeting_type(_selected_click_card)):
		_selected_click_target = null
		_update_click_mode_target_highlights()
		return

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
	# 需要显式敌人的卡牌缺少有效目标时必须拒绝确认，否则会把玩家自身当成单体目标错误施放。
	# 这里刻意保留当前选择而不清理：玩家可以直接补选一名敌人后再次点击“确定”。
	if not _can_confirm_click_selection():
		_refresh_click_mode_confirm_availability()
		return

	# 确认瞬间仍有效的施放目标；自动目标牌固定为 PlayerManager。
	var confirmed_target: Node = _get_confirmed_click_mode_target()
	# 提前保存节点引用后清理点击状态，确认路径不再触发手牌归位动画，避免抢占随后的飞行动画。
	var confirmed_card: SkillCard = _selected_click_card
	clear_click_selection(false)
	player_manager.consume_energy(confirmed_card.data.cost)
	deck_manager.play_card(confirmed_card, confirmed_target)

## 返回点击模式确认时仍然有效的目标。
## 自动目标牌与自身目标牌会安全回退到玩家自身；需要显式敌人的卡牌在目标失效时返回空值，
## 由确认入口拒绝整次施放，而不是把玩家自身当成单体目标。
## @return Node 用于既有 DeckManager.play_card 的目标节点；无法确定有效目标时返回 null。
func _get_confirmed_click_mode_target() -> Node:
	# 自动目标牌不允许携带显式敌人到行动队列，范围效果会在 BattleManager 按卡牌固有目标类型展开。
	if not _selected_click_card or not _requires_manual_enemy_target(_get_card_targeting_type(_selected_click_card)):
		return player_manager
	# 需要显式敌人的卡牌只能指向已选中的敌人；缺少有效敌人时不得回退为玩家自身，
	# 否则单体伤害牌会对自己结算。
	if _is_valid_click_mode_enemy_target(_selected_click_target):
		return _selected_click_target
	return null

## 当鼠标按下并检测到点中某张可用的卡时创建拖拽虚影。
## 真实卡只保存为行动队列候选节点，拖拽期间始终保留在原手牌布局中。
## @param card 被按住的真实手牌节点。
## @return void 无返回值。
func start_drag(card: SkillCard) -> void:
	# 如果当前能量小于该卡牌的消耗则不能拖拽。
	if player_manager.energy < card.data.cost:
		return
	card_being_dragged = card
	# 记录鼠标点击位置与卡牌原点之间的差值，使虚影保持原有按住位置而不是跳到鼠标中心。
	drag_offset = card.position - get_global_mouse_position()
	# 真实卡恢复普通手牌缩放，避免鼠标离开后仍保留悬停表现而与虚影争夺视觉焦点。
	highlight_card(card, false)
	_create_card_drag_ghost(card)
	_update_card_drag_ghost_position()

	if tooltip_panel:
		tooltip_panel.hide_tooltip()

## 创建只承担视觉预览的卡牌虚影。
## 完整复制卡面内容以避免维护第二套展示节点，但随后必须隔离复制节点的所有输入能力。
## @param card 用于创建虚影的真实手牌节点。
## @return Node2D 新建的虚影节点；复制失败时返回 null。
func _create_card_drag_ghost(card: SkillCard) -> Node2D:
	_clear_card_drag_ghost()
	if not card or not is_instance_valid(card):
		return null

	# 从真实手牌复制完整卡面，保证名称、元素、费用和锁定遮罩与原卡始终一致。
	var drag_ghost: Node2D = card.duplicate() as Node2D
	if not drag_ghost:
		push_warning("无法创建卡牌拖拽虚影，已保留真实手牌位置。")
		return null

	# 复制节点沿用真实卡的主题颜色，但统一覆写透明度以形成明确的临时预览层。
	var ghost_modulate: Color = card.modulate
	ghost_modulate.a = card_drag_ghost_opacity
	drag_ghost.modulate = ghost_modulate
	drag_ghost.scale = card_drag_scale
	drag_ghost.name = "CardDragGhost"
	_disable_card_drag_ghost_input(drag_ghost)
	add_child(drag_ghost)
	drag_ghost.global_position = card.global_position
	_card_drag_ghost = drag_ghost
	return drag_ghost

## 让完整卡面副本穿透鼠标和物理点查询。
## 递归处理可以覆盖未来加入 SkillCard 场景的标签或额外 Area2D，而无需在此处硬编码节点路径。
## @param node 需要解除输入能力的虚影节点或其后代。
## @return void 无返回值。
func _disable_card_drag_ghost_input(node: Node) -> void:
	if node is Area2D:
		# 虚影不能出现在手牌或目标卡槽的 PhysicsPointQuery 结果中。
		var ghost_area: Area2D = node as Area2D
		ghost_area.collision_layer = 0
		ghost_area.collision_mask = 0
		ghost_area.input_pickable = false
		ghost_area.monitoring = false
		ghost_area.monitorable = false
	if node is Control:
		# 卡面标签也必须允许鼠标穿透，避免虚影在 UI 层遮挡后续交互。
		var ghost_control: Control = node as Control
		ghost_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_disable_card_drag_ghost_input(child)

## 计算并更新当前拖拽预览的屏幕位置。
## 真实卡绝不在此方法中移动；虚影创建失败时仍返回计算位置以保证目标判定安全退化。
## @return Vector2 经过屏幕边界限制的预览位置。
func _update_card_drag_ghost_position() -> Vector2:
	# 鼠标与按下偏移共同决定预览位置，保持改动前拖拽手感。
	var drag_preview_position: Vector2 = _get_drag_preview_position()
	if _card_drag_ghost and is_instance_valid(_card_drag_ghost):
		_card_drag_ghost.position = drag_preview_position
	return drag_preview_position

## 返回当前拖拽虚影应使用的屏幕位置。
## @return Vector2 已按当前视口范围裁剪的预览位置。
func _get_drag_preview_position() -> Vector2:
	# 预览坐标沿用旧拖拽的鼠标偏移规则，避免切换为虚影后出现位置跳变。
	var target_position: Vector2 = get_global_mouse_position() + drag_offset
	return Vector2(
		clamp(target_position.x, 0, screen_size.x),
		clamp(target_position.y, 0, screen_size.y)
	)

## 立即隐藏并延迟释放拖拽虚影。
## 隐藏保证松开鼠标后的当前帧不再可见，延迟释放保持 Godot 场景树迭代安全。
## @return void 无返回值。
func _clear_card_drag_ghost() -> void:
	if not _card_drag_ghost:
		return
	if is_instance_valid(_card_drag_ghost):
		_card_drag_ghost.hide()
		_card_drag_ghost.queue_free()
	_card_drag_ghost = null

## 辅助函数：判断卡牌是否为【对自己使用】
func is_self_target_card(card: SkillCard) -> bool:
	if not card or not card.data:
		return false
	# 复用统一的目标类型读取逻辑，避免自身施放分支与视觉状态在技能数据缺失时出现不同回退。
	return _get_card_targeting_type(card) == SKILL_TARGETING_TYPE.Value.Self

## 当鼠标松开时触发，使用虚影位置确认目标并将真实手牌交给既有行动队列。
## @return void 无返回值。
func finish_drag() -> void:
	if not card_being_dragged or not is_instance_valid(card_being_dragged):
		_cancel_active_drag()
		return

	# 保存真实卡引用；虚影会在施放判定前清理，真实卡才是唯一可进入 Action.presentation_card 的节点。
	var dragged_card: SkillCard = card_being_dragged as SkillCard
	if not dragged_card:
		_cancel_active_drag()
		return
	# 松开位置必须在回收虚影前读取，确保判定使用玩家看到的预览位置。
	var release_position: Vector2 = _get_drag_preview_position()
	# 先判断是否回到手牌区，用于避免自我施放卡在回收路径上误触。
	var release_in_hand_area: bool = false
	if player_hand_referencd and player_hand_referencd.has_method("is_release_in_hand_area"):
		release_in_hand_area = player_hand_referencd.is_release_in_hand_area(release_position)

	# 通过虚影释放位置获取是否命中了一个接收区域。
	var card_slot_found: Node2D = raycast_check_for_card_slot_at_position(release_position)
	# 虚影必须先于真实卡进入既有飞行链路消失，避免两张卡同时出现在目标区域。
	_clear_card_drag_ghost()
	card_being_dragged = null
	if card_slot_found:
		# 命中目标：扣除能量
		player_manager.consume_energy(dragged_card.data.cost)
		# 让DeckManager将卡牌推入战斗状态机的 Action Queue (行动队列)
		# 范围、随机、全体单位与自身等自动目标牌只把命中卡槽当作有效释放区域，不能把该实体传入行动队列成为单体表现目标。
		if _requires_manual_enemy_target(_get_card_targeting_type(dragged_card)):
			deck_manager.play_card(dragged_card, card_slot_found.get_parent())
		else:
			deck_manager.play_card(dragged_card)
	else:
		# 真实卡始终留在手牌区；无效释放只需要结束虚影预览，不再播放多余归位动画。
		# 特例：当卡牌是【对自己使用】类型时，允许直接在空白处施放
		if allow_self_cast_on_empty and is_self_target_card(dragged_card) and not release_in_hand_area:
			player_manager.consume_energy(dragged_card.data.cost)
			deck_manager.play_card(dragged_card)

	# 松开后卡牌会立刻入队或保留在手牌区，必须清理预览状态以停止呼吸并避免绿色描边残留。
	_apply_target_highlights([])

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

## 同样是通过射线检测目标卡槽（通常在实体身上）。
## 拖拽模式始终使用虚影预览位置，不能再读取真实手牌的固定位置。
func raycast_check_for_card_slot():
	if not card_being_dragged:
		return null
	return raycast_check_for_card_slot_at_position(_get_drag_preview_position())

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
