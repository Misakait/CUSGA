## 卡牌管理器 (CardManager)
## 负责处理手牌中的交互逻辑（如拖拽、悬停高亮、打出检测）。
## 它实时监测鼠标的射线投射并拦截输入操作。
extends Node2D

@onready var deck_manager = $"../DeckManager"
@onready var control_lock = $"../ControlLock"
@onready var player_manager = $"../PlayerManager"
@onready var battle_manager = $".."
@onready var tooltip_panel = $"../UI/TooltipPanel"

const COLLISION_MASK_CARD = 1
const COLLISION_MASK_CARD_SLOT = 2
const SKILL_TARGETING_TYPE_BRIDGE := preload("res://scripts/battle_scripts/skill_targeting_type_bridge.gd")

# 通过桥接器读取 C# 枚举，避免在 GDScript 中重复维护顺序。
@onready var _skill_targeting_type_map: Dictionary = SKILL_TARGETING_TYPE_BRIDGE.get_map()

@export_group("视觉缩放参数")
@export var card_normal_scale: Vector2 = Vector2(1.0, 1.0) ## 卡牌正常大小
@export var card_hover_scale: Vector2 = Vector2(1.05, 1.05) ## 卡牌悬停放大
@export var card_drag_scale: Vector2 = Vector2(0.95, 0.95) ## 卡牌拖拽时略微缩小
@export var monster_normal_scale: Vector2 = Vector2(1.5, 1.5) ## 怪物正常大小
@export var monster_hover_scale: Vector2 = Vector2(1.6, 1.6) ## 怪物被选中悬停时放大
@export var scale_tween_duration: float = 0.08 ## 缩放动画过度时间

@export_group("自我施放参数")
@export var allow_self_cast_on_empty: bool = true ## 当卡牌为【对自己使用】时，允许拖到空白处直接施放

var screen_size
var card_being_dragged:Node2D
var is_hovering_on_card:bool
var player_hand_referencd #玩家手牌引用
var drag_offset: Vector2 # 用于记录拖拽偏移量
#var currently_hovered_slot: Node2D = null # 记录当前被悬停的卡槽，修改为下面
var currently_highlighted_entities: Array[Node] = [] # 记录当前被悬停的卡槽

const MONSTER_BASE_SCALE_META := "_card_hover_base_scale"

func _ready() -> void:
	screen_size = get_viewport_rect().size
	player_hand_referencd = $"../PlayerHand"

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

## 根据拖拽的卡牌类型，动态计算并更新受影响范围的实体高亮
## @param new_slot 鼠标射线命中的卡槽节点，可能为空。
## @param release_in_hand_area 当前拖拽位置是否回到手牌区（用于避免误判）。
## @return void 无返回值。
func update_hovered_targets(new_slot: Node2D, release_in_hand_area: bool = false):
	var intended_targets: Array[Node] = []

	# 只有在手里抓着牌时才计算高亮，避免无意义的 UI 抖动
	if card_being_dragged and card_being_dragged.data:
		# 如果悬停在有效卡槽上，开始计算波及范围
		if new_slot:
			var target = new_slot.get_parent()
			# 这里用字典映射，避免 GDScript 自己维护一份枚举顺序
			var target_self = _skill_targeting_type_map.get("Self", 0)
			var target_single_enemy = _skill_targeting_type_map.get("SingleEnemy", 1)
			var target_all_enemies = _skill_targeting_type_map.get("AllEnemies", 2)
			var target_any_single = _skill_targeting_type_map.get("AnySingleUnit", 3)
			var target_all_units = _skill_targeting_type_map.get("AllUnits", 4)
			var target_random_enemy = _skill_targeting_type_map.get("RandomEnemy", 5)
			var target_spread_from_enemy = _skill_targeting_type_map.get("SpreadFromEnemy", 6)

			var targeting_type: int = target_single_enemy

			# 尝试安全获取目标类型
			if card_being_dragged.data.get("Skill") != null and card_being_dragged.data.Skill.get("TargetingType") != null:
				targeting_type = int(card_being_dragged.data.Skill.TargetingType)

			match targeting_type:
				target_self:
					intended_targets.append(player_manager)

				target_single_enemy, target_any_single:
					if target:
						intended_targets.append(target)

				target_all_enemies, target_random_enemy:
					# 全体和随机都会高亮所有敌人，以提示波及范围
					if battle_manager.monster_manager and battle_manager.monster_manager.active_monsters:
						intended_targets.assign(battle_manager.monster_manager.active_monsters)

				target_all_units:
					# 所有人，包括玩家
					intended_targets.assign(battle_manager.get_all_combatants())

				target_spread_from_enemy:
					# 扩散逻辑：主目标 + 左右相邻
					if target and battle_manager.monster_manager and battle_manager.monster_manager.active_monsters:
						var monsters = battle_manager.monster_manager.active_monsters
						var target_index = monsters.find(target)

						if target_index != -1:
							intended_targets.append(target) # 本身
							if target_index > 0:
								intended_targets.append(monsters[target_index - 1]) # 左侧
							if target_index < monsters.size() - 1:
								intended_targets.append(monsters[target_index + 1]) # 右侧
				_:
					if target:
						intended_targets.append(target)
		else:
			# 当没有命中卡槽时，若当前是自我施放卡且位置可释放，则提前高亮玩家（用于行动条提示）
			if allow_self_cast_on_empty and not release_in_hand_area and is_self_target_card(card_being_dragged):
				intended_targets.append(player_manager)

	# 1. 找出需要取消高亮的实体（在旧数组中，但不在新数组中）
	for entity in currently_highlighted_entities:
		if not entity in intended_targets:
			set_entity_highlight(entity, false)

	# 2. 找出需要新增高亮的实体（在新数组中，但不在旧数组中）
	for entity in intended_targets:
		if not entity in currently_highlighted_entities:
			set_entity_highlight(entity, true)

	# 更新当前的记录
	currently_highlighted_entities = intended_targets

## 辅助函数：统一处理实体的视觉放大和时间轴高亮
func set_entity_highlight(entity: Node, is_highlighted: bool):
	if not entity:
		return

	# 处理缩放动画（怪物：放大整个节点，确保 HealthBar/CardName/Element 同步缩放）
	if _is_monster_entity(entity):
		var monster = entity as Node2D
		var base_scale = _get_monster_base_scale(monster)
		var ratio = _get_monster_hover_ratio()
		var target_scale = base_scale if not is_highlighted else Vector2(base_scale.x * ratio.x, base_scale.y * ratio.y)
		var tween = create_tween()
		tween.tween_property(monster, "scale", target_scale, scale_tween_duration)
		if not is_highlighted:
			_clear_monster_base_scale(monster)
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

func _get_monster_base_scale(monster: Node2D) -> Vector2:
	if monster.has_meta(MONSTER_BASE_SCALE_META):
		return monster.get_meta(MONSTER_BASE_SCALE_META)
	var base_scale: Vector2 = monster.scale
	monster.set_meta(MONSTER_BASE_SCALE_META, base_scale)
	return base_scale

func _clear_monster_base_scale(monster: Node2D) -> void:
	if monster.has_meta(MONSTER_BASE_SCALE_META):
		monster.remove_meta(MONSTER_BASE_SCALE_META)

func _get_monster_hover_ratio() -> Vector2:
	return Vector2(
		monster_hover_scale.x / monster_normal_scale.x if monster_normal_scale.x != 0 else 1.0,
		monster_hover_scale.y / monster_normal_scale.y if monster_normal_scale.y != 0 else 1.0
	)

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

## 监听全局输入事件，捕捉卡牌拖拽意图。
## 增加条件：如果不处于玩家操作回合（如敌方回合或技能结算时），直接拦截操作。
func _input(event):
	if control_lock.is_lock or battle_manager.current_state != battle_manager.BattleState.PLAYER_TURN:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var card = raycast_check_for_card()
			if card:
				start_drag(card)
		else:
			if card_being_dragged:
				finish_drag()

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
	var target_self = _skill_targeting_type_map.get("Self", 0)
	var targeting_type: int = _skill_targeting_type_map.get("SingleEnemy", 1)
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

	if card.is_lock:
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
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()

	#将鼠标改为卡牌中心，即卡牌中心进入框内即可放入卡槽
	parameters.position = card_being_dragged.global_position
	#parameters.position = get_global_mouse_position()

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
