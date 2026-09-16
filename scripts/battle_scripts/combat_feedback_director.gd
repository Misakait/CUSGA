## 战斗反馈导演。
## 该节点只消费 C# 伤害结算与生命变化信号，将其映射为浮字、目标受力和屏幕冲击；绝不修改伤害或回合状态。
class_name CombatFeedbackDirector
extends Node

## 表现配方资源，未配置时使用安全的运行时默认值。
@export var profile: CombatFeedbackProfile

## CanvasLayer 路径，浮字必须位于独立层避免被怪物卡面裁切。
@export var feedback_layer_path: NodePath

## 容纳浮字的全屏 Control 路径。
@export var popup_container_path: NodePath

## 玩家受击数字使用的场景锚点路径，避免结算层硬编码 HUD 节点。
@export var player_feedback_anchor_path: NodePath

## 屏幕冲击控制器路径。
@export var screen_impulse_path: NodePath

## 普通命中浮字回收池。
var _available_popups: Array[CombatFeedbackPopup] = []

## 正在显示的浮字，用于在播放结束后归还对象池；不限制同一目标或全战场的同时显示数量。
var _active_popups: Array[CombatFeedbackPopup] = []

## 已连接的伤害接收组件，键为实例 ID 以防新怪生成时重复连接。
var _connected_receivers: Dictionary = {}

## 已连接的生命组件及其上次生命值，用于只在实际恢复时显示绿色浮字。
var _connected_health_components: Dictionary = {}

## 已连接的怪物死亡信号及其 Callable，必须缓存以便可靠断连。
var _connected_death_presenters: Dictionary = {}

## 正在控制目标反应的 Tween；同一目标的允许受击动画会进入队列，绝不覆盖已开始的反馈。
var _impact_tweens: Dictionary = {}

## 按目标实例 ID 存储的待播放受力配方；每个多段序列只保存 Profile 允许次数内的受击动画。
var _impact_queues: Dictionary = {}

## 正在控制怪物下冲攻击的 Tween 及其归位位置，防止连续行动争夺怪物位置。
var _monster_attack_tweens: Dictionary = {}

## 导演当前生效的表现强度稳定值。
var _feedback_intensity: String = "full"

## 浮字所在的 CanvasLayer。
var _feedback_layer: CanvasLayer

## 浮字容器。
var _popup_container: Control

## 玩家反馈锚点。
var _player_feedback_anchor: CanvasItem

## 战场冲击控制器。
var _screen_impulse: CombatScreenImpulse

## 当前战斗根节点。
var _battle_root: Node

## 当前怪物管理器。
var _monster_manager: Node

## 当前玩家管理器。
var _player_manager: Node

## 在所有同级节点就绪后绑定实体，确保 BattleManager 已完成初始怪物生成。
## @return void 无返回值。
func _ready() -> void:
	_battle_root = get_parent()
	_feedback_layer = get_node_or_null(feedback_layer_path) as CanvasLayer
	_popup_container = get_node_or_null(popup_container_path) as Control
	_player_feedback_anchor = get_node_or_null(player_feedback_anchor_path) as CanvasItem
	_screen_impulse = get_node_or_null(screen_impulse_path) as CombatScreenImpulse
	if profile == null:
		profile = CombatFeedbackProfile.new()
	call_deferred("_initialize_feedback_bindings")

## 解析场景依赖、加载玩家偏好并连接当前及后续战斗实体。
## @return void 无返回值。
func _initialize_feedback_bindings() -> void:
	if _battle_root == null:
		return
	_monster_manager = _battle_root.get_node_or_null("MonsterManager")
	_player_manager = _battle_root.get_node_or_null("PlayerManager")
	_load_feedback_intensity()
	_configure_settings_panel()
	_connect_player_receiver()
	_connect_active_monster_receivers()
	if _monster_manager and _monster_manager.has_signal("monsters_spawned") and not _monster_manager.is_connected("monsters_spawned", _on_monsters_spawned):
		_monster_manager.connect("monsters_spawned", _on_monsters_spawned)

## 绑定玩家实体的伤害和状态信号。
## @return void 无返回值。
func _connect_player_receiver() -> void:
	if _player_manager == null:
		return
	var player_entity: Node = _player_manager.call("get_combat_entity") if _player_manager.has_method("get_combat_entity") else _player_manager
	_connect_entity_feedback(player_entity)

## 绑定当前场上所有怪物实体的伤害、状态和死亡表现信号。
## @return void 无返回值。
func _connect_active_monster_receivers() -> void:
	if _monster_manager == null:
		return
	var active_monsters: Array = _monster_manager.get("active_monsters")
	for monster in active_monsters:
		_connect_entity_feedback(monster)

## 当怪物管理器补充新怪时连接其反馈信号。
## @return void 无返回值。
func _on_monsters_spawned() -> void:
	_connect_active_monster_receivers()

## 连接一个战斗实体的可选反馈信号，缺失组件时安全降级。
## @param entity 玩家实体、怪物实体或包装节点。
## @return void 无返回值。
func _connect_entity_feedback(entity: Node) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var real_entity: Node = entity.call("get_combat_entity") if entity.has_method("get_combat_entity") else entity
	if real_entity == null:
		return
	var receiver: Node = real_entity.get_node_or_null("Components/DamageReceiverComponent")
	if receiver and receiver.has_signal("DamageResolved"):
		var receiver_id: int = receiver.get_instance_id()
		if not _connected_receivers.has(receiver_id):
			receiver.connect("DamageResolved", _on_damage_resolved)
			_connected_receivers[receiver_id] = receiver
	var health_component: Node = real_entity.get_node_or_null("Components/HealthComponent")
	if health_component and health_component.has_signal("ValueChanged"):
		var health_id: int = health_component.get_instance_id()
		if not _connected_health_components.has(health_id):
			# 先记录当前生命值，避免实体初始化或重新绑定时把满血状态误显示为治疗。
			var initial_health: int = int(health_component.get("CurrentValue"))
			var health_callable: Callable = _on_health_value_changed.bind(real_entity, health_component)
			health_component.connect("ValueChanged", health_callable)
			_connected_health_components[health_id] = {
				"component": health_component,
				"callable": health_callable,
				"last_value": initial_health
			}
	if entity.has_signal("DeathPresentationRequested"):
		var entity_id: int = entity.get_instance_id()
		if not _connected_death_presenters.has(entity_id):
			# 死亡信号回调用明确 Callable 类型保存，避免 bind 结果在警告即错误配置下退化为 Variant。
			var death_callable: Callable = _on_monster_death_requested.bind(entity)
			entity.connect("DeathPresentationRequested", death_callable)
			_connected_death_presenters[entity_id] = {"entity": entity, "callable": death_callable}

## 将已结算的伤害事实变换为一次受控反馈。
## @param result C# DamageReceiverComponent 产生的只读伤害结果。
## @return void 无返回值。
func _on_damage_resolved(result: RefCounted) -> void:
	if not profile.enabled or result == null:
		return
	# 伤害目标决定浮字锚点与局部受力队列，缺失目标时只能安全跳过表现。
	var target: Node = _read_result_node(result, "Target")
	if target == null or not is_instance_valid(target):
		return
	# 实际扣血量是主伤害浮字的绝对数值输入。
	var actual_damage: int = _read_result_int(result, "ActualDamage")
	# 段号用于浮字空间布局，并决定本段是否仍处于目标受击动画上限内。
	var hit_index: int = _read_result_int(result, "HitIndex")
	# 总段数控制同锚点浮字布局与播放加速，至少为一以避免除零。
	var hit_count: int = maxi(1, _read_result_int(result, "HitCount"))
	# 闪避结果没有数值碰撞，但仍需要显示固定轻量提示。
	var is_evaded: bool = _read_result_bool(result, "IsEvaded")
	# 暴击结果为数值曲线配方增加可配置的结果语义加成。
	var is_critical: bool = _read_result_bool(result, "IsCritical")
	# 致死结果为数值曲线配方增加可配置的终结语义加成。
	var is_lethal: bool = _read_result_bool(result, "IsLethal")
	# 护盾吸收量驱动灰色数字；与实际伤害相加后代表本次碰撞总量。
	var shield_absorbed: int = _read_result_int(result, "ShieldAbsorbedDamage")
	# 护盾破裂结果为数值曲线配方增加可配置的结果语义加成。
	var shield_broken: bool = _read_result_bool(result, "ShieldWasBroken")
	if actual_damage <= 0 and not is_evaded and shield_absorbed <= 0:
		return

	# 主数字配方由真实结果和数值曲线决定；总段数只缩短离场时长，不改变数值强度。
	var display: Dictionary = _build_damage_display(actual_damage, is_evaded, is_critical, is_lethal, shield_absorbed, hit_count)
	# 当前数字的时长已经按总段数加速，后续段以该时长为间隔顺序显示。
	var popup_duration: float = float(display.get("duration", profile.popup_duration_min))
	# 段号决定顺序入场位置，使高频数字不会在同一目标锚点同时堆叠。
	var popup_delay: float = profile.resolve_multi_hit_popup_delay(popup_duration, hit_index, hit_count)
	display["delay"] = popup_delay
	# 目标锚点确保怪物与玩家 HUD 使用各自正确的浮字位置。
	var anchor_position: Vector2 = _resolve_feedback_position(target)
	# 同锚点多段同时以空间分布和加速离场减少高频数字重叠，不延迟任何一段的入场。
	var popup_offset: Vector2 = _resolve_hit_popup_offset(hit_index, hit_count)
	_spawn_popup(display, anchor_position + popup_offset)
	if shield_absorbed > 0 and actual_damage > 0:
		# 部分吸收保留独立灰色数值，并按吸收量使用同一条曲线而非固定小字号。
		var shield_display: Dictionary = _build_guard_display(shield_absorbed, hit_count)
		# 护盾数字同样随总段数加速；轻微下移只分离本段的伤害与吸收数值。
		var shield_popup_offset: Vector2 = Vector2(0.0, profile.multi_hit_popup_spread_distance * profile.multi_hit_popup_vertical_spread_ratio)
		# 同一段的护盾数字与主数字同步进入，下一段仍由相同延迟顺序开始。
		shield_display["delay"] = popup_delay
		_spawn_popup(shield_display, anchor_position + popup_offset + shield_popup_offset)
	if is_evaded:
		return

	# 总碰撞量让部分护盾既保留实际伤害的数字语义，也保留被吸收部分的受击重量。
	var impact_amount: int = actual_damage + shield_absorbed
	# 同一数值配方同时交给局部目标反应与全局冲击，避免两条视觉曲线发生漂移。
	var impact_recipe: Dictionary = _build_impact_recipe(impact_amount, is_critical, is_lethal, shield_broken)
	# 受击动画只保留多段序列的前几次，避免高段数将同一目标的受力队列拖得过长。
	if profile.should_play_multi_hit_impact(hit_index):
		_enqueue_target_impact(target, display.get("color", Color.WHITE), impact_recipe)
	_request_value_scaled_impulse(impact_recipe)

## 仅在生命值实际增加时创建治疗浮字；伤害继续由 DamageResolved 保证带有暴击、护盾等完整语义。
## @param current_value 生命组件发出的当前生命值。
## @param max_value 生命组件发出的最大生命值，当前只用于匹配信号签名。
## @param owner 发生生命变化的真实战斗实体。
## @param health_component 发出信号的生命组件。
## @return void 无返回值。
func _on_health_value_changed(current_value: int, _max_value: int, owner: Node, health_component: Node) -> void:
	if health_component == null or not is_instance_valid(health_component):
		return
	var health_id: int = health_component.get_instance_id()
	if not _connected_health_components.has(health_id):
		return
	var health_entry: Dictionary = _connected_health_components[health_id]
	var previous_value: int = int(health_entry.get("last_value", current_value))
	health_entry["last_value"] = current_value
	_connected_health_components[health_id] = health_entry
	if not profile.enabled or current_value <= previous_value or owner == null or not is_instance_valid(owner):
		return
	# 实际生命增量是治疗浮字唯一的绝对数值输入。
	var recovered_amount: int = current_value - previous_value
	# 治疗只放大自身浮字，不请求受击、震屏或 Hit Stop。
	var heal_display: Dictionary = _build_heal_display(recovered_amount)
	_spawn_popup(heal_display, _resolve_feedback_position(owner))

## 在怪物逻辑死亡时抢占视觉收尾；若没有导演或配置禁用，怪物会走自身的安全即时销毁兜底。
## @param monster 需要播放死亡收尾的怪物节点。
## @return void 无返回值。
func _on_monster_death_requested(monster: Node) -> void:
	if monster == null or not is_instance_valid(monster) or not profile.enabled:
		return
	if not monster.has_method("TryClaimDeathPresentation") or not monster.call("TryClaimDeathPresentation"):
		return
	_play_monster_death(monster)

## 播放一次性怪物死亡收尾并在视觉结束后释放节点。
## @param monster 已从逻辑目标池移除的怪物节点。
## @return void 无返回值。
func _play_monster_death(monster: Node) -> void:
	if not (monster is Node2D):
		if monster.has_method("FinalizeCombatDeathPresentation"):
			monster.call("FinalizeCombatDeathPresentation")
		return
	# 怪物节点使用显式 Node2D 类型，确保死亡表现只修改可定位的视觉实体。
	var monster_2d: Node2D = monster as Node2D
	# 死亡收尾 Tween 使用显式类型，避免工厂调用的静态推断受项目警告设置影响。
	var tween: Tween = monster_2d.create_tween()
	tween.set_parallel(true)
	tween.tween_property(monster_2d, "scale", monster_2d.scale * 1.12, 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(monster_2d, "modulate:a", 0.0, 0.26).set_delay(0.08)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(monster) and monster.has_method("FinalizeCombatDeathPresentation"):
			monster.call("FinalizeCombatDeathPresentation")
	)

## 根据实际数值与结果语义构建伤害、护盾或闪避浮字配方。
## @param actual_damage 实际扣血量。
## @param is_evaded 是否闪避。
## @param is_critical 是否暴击。
## @param is_lethal 是否致死。
## @param shield_absorbed 护盾吸收量。
## @param hit_count 当前多段伤害的总段数，用于加速浮字离场。
## @return Dictionary 浮字播放参数。
func _build_damage_display(actual_damage: int, is_evaded: bool, is_critical: bool, is_lethal: bool, shield_absorbed: int, hit_count: int = 1) -> Dictionary:
	# 缺失或异常的段数按单段处理，确保所有浮字调用方保持兼容。
	var safe_hit_count: int = maxi(hit_count, 1)
	if is_evaded:
		# 闪避没有数值输入，使用曲线最小值维持固定的轻量可读提示。
		var evade_intensity: float = profile.resolve_feedback_intensity(0.0)
		return {
			"text": "MISS",
			"color": profile.evade_color,
			"scale": profile.resolve_popup_scale(evade_intensity),
			"rise": profile.resolve_popup_rise_distance(evade_intensity),
			"duration": profile.resolve_multi_hit_popup_duration(profile.resolve_popup_duration(evade_intensity), safe_hit_count),
			"delay": 0.0
		}
	if shield_absorbed > 0 and actual_damage <= 0:
		return _build_guard_display(shield_absorbed, safe_hit_count)

	# 实际扣血量决定伤害数字的连续视觉强度。
	var damage_intensity: float = profile.resolve_feedback_intensity(float(actual_damage))
	# 数值曲线先得到基础缩放，暴击和击杀再叠加可配置的结果语义强化。
	var damage_scale: float = profile.resolve_popup_scale(damage_intensity)
	if is_critical:
		damage_scale *= profile.critical_popup_scale_multiplier
	if is_lethal:
		damage_scale *= profile.lethal_popup_scale_multiplier
	# 最终钳制使结果语义叠加和超高数值都不会超出 Inspector 的安全上限。
	damage_scale = minf(damage_scale, profile.popup_scale_cap)
	# 暴击改用深红色，但数字大小仍以实际伤害曲线为基础。
	var damage_color: Color = profile.critical_damage_color if is_critical else profile.normal_damage_color
	# 击杀仅增加下划线而不插入额外文字标签。
	var is_underlined: bool = is_lethal
	# 暴击保持加粗字形，击杀沿用数字与下划线表达终结感。
	var is_emphasized: bool = is_critical
	return {
		"text": "%d" % actual_damage,
		"color": damage_color,
		"scale": damage_scale,
		"rise": profile.resolve_popup_rise_distance(damage_intensity),
		"duration": profile.resolve_multi_hit_popup_duration(profile.resolve_popup_duration(damage_intensity), safe_hit_count),
		"delay": 0.0,
		"underlined": is_underlined,
		"emphasized": is_emphasized
	}

## 根据护盾吸收量构建灰色数值浮字配方。
## @param shield_absorbed 本次护盾实际吸收的数值。
## @param hit_count 当前多段伤害的总段数，用于加速浮字离场。
## @return Dictionary 护盾浮字播放参数。
func _build_guard_display(shield_absorbed: int, hit_count: int = 1) -> Dictionary:
	# 护盾吸收量使用自身的绝对数值曲线，避免固定小数字掩盖高额防御。
	var guard_intensity: float = profile.resolve_feedback_intensity(float(shield_absorbed))
	# 缺失或异常的段数按单段处理，保证独立护盾吸收提示不被意外加速。
	var safe_hit_count: int = maxi(hit_count, 1)
	return {
		"text": "%d" % shield_absorbed,
		"color": profile.guard_color,
		"scale": profile.resolve_popup_scale(guard_intensity),
		"rise": profile.resolve_popup_rise_distance(guard_intensity),
		"duration": profile.resolve_multi_hit_popup_duration(profile.resolve_popup_duration(guard_intensity), safe_hit_count),
		"delay": 0.0
	}

## 根据实际回复量构建绿色治疗浮字配方。
## @param recovered_amount 本次生命真实增加的数值。
## @return Dictionary 治疗浮字播放参数。
func _build_heal_display(recovered_amount: int) -> Dictionary:
	# 治疗量使用同一条绝对数值曲线，使大额回复也能直观表达其数值价值。
	var heal_intensity: float = profile.resolve_feedback_intensity(float(recovered_amount))
	return {
		"text": "+%d" % recovered_amount,
		"color": profile.heal_color,
		"scale": profile.resolve_popup_scale(heal_intensity),
		"rise": profile.resolve_popup_rise_distance(heal_intensity),
		"duration": profile.resolve_popup_duration(heal_intensity),
		"delay": 0.0
	}

## 为同一锚点的多段数字生成确定性空间偏移，不改动任何播放强度或时序。
## @param hit_index 当前伤害在多段序列中的零基索引。
## @param hit_count 本次伤害序列的总段数。
## @return Vector2 本次浮字叠加到锚点的位置偏移。
func _resolve_hit_popup_offset(hit_index: int, hit_count: int) -> Vector2:
	if hit_count <= 1 or profile.multi_hit_popup_spread_distance <= 0.0:
		return Vector2.ZERO
	# 有效索引确保不规范的跨语言数据不会产生不可预测的布局角度。
	var safe_hit_index: int = clampi(hit_index, 0, hit_count - 1)
	# 均匀环绕角度让同帧数字可读，同时不通过时间错开制造多段节流。
	var slot_angle: float = TAU * float(safe_hit_index) / float(hit_count)
	# 纵向压缩由 Profile 参数决定，避免环绕布局干扰卡面名称区域。
	var vertical_distance: float = profile.multi_hit_popup_spread_distance * profile.multi_hit_popup_vertical_spread_ratio
	return Vector2(cos(slot_angle) * profile.multi_hit_popup_spread_distance, sin(slot_angle) * vertical_distance)

## 创建或复用一个浮字；每次结算都获得独立显示，不按目标或战场数量丢弃结果。
## @param display 文字、颜色和时长参数。
## @param anchor_position 浮字起点。
## @return void 无返回值。
func _spawn_popup(display: Dictionary, anchor_position: Vector2) -> void:
	if _popup_container == null:
		return
	var popup: CombatFeedbackPopup = _acquire_popup()
	if popup == null:
		return
	popup.play_feedback(
		str(display.get("text", "")),
		display.get("color", Color.WHITE),
		anchor_position,
		float(display.get("scale", 1.0)),
		float(display.get("rise", profile.popup_rise_min)),
		float(display.get("duration", profile.popup_duration_min)),
		bool(display.get("underlined", false)),
		bool(display.get("emphasized", false)),
		float(display.get("delay", 0.0))
	)

## 从空闲池取得浮字；池为空时创建新节点，确保所有同帧结果都能显示。
## @return CombatFeedbackPopup 可播放浮字；容器缺失时返回 null。
func _acquire_popup() -> CombatFeedbackPopup:
	if not _available_popups.is_empty():
		var available: CombatFeedbackPopup = _available_popups.pop_back()
		_active_popups.append(available)
		return available
	var created: CombatFeedbackPopup = CombatFeedbackPopup.new()
	_popup_container.add_child(created)
	created.playback_finished.connect(_on_popup_playback_finished)
	_active_popups.append(created)
	return created

## 将已完成浮字从活跃列表转回空闲池。
## @param popup 已结束动画的浮字节点。
## @return void 无返回值。
func _on_popup_playback_finished(popup: CombatFeedbackPopup) -> void:
	_active_popups.erase(popup)
	if not _available_popups.has(popup):
		_available_popups.append(popup)

## 让怪物在敌方行动开始时向下方玩家方向短促下冲，再自动回到原排布位置。
## @param monster 发起本次敌方行动的怪物实体。
## @return void 无返回值。
func play_monster_attack_feedback(monster: Node) -> void:
	if not profile.enabled or not (monster is Node2D):
		return
	var monster_2d: Node2D = monster as Node2D
	if not is_instance_valid(monster_2d):
		return
	var monster_id: int = monster_2d.get_instance_id()
	if _monster_attack_tweens.has(monster_id):
		var previous_attack: Dictionary = _monster_attack_tweens[monster_id]
		var previous_tween: Tween = previous_attack.get("tween")
		var previous_base_position: Vector2 = previous_attack.get("base_position", monster_2d.position)
		if previous_tween and previous_tween.is_valid() and previous_tween.is_running():
			previous_tween.kill()
		monster_2d.position = previous_base_position
	var base_position: Vector2 = monster_2d.position
	var attack_tween: Tween = monster_2d.create_tween()
	attack_tween.tween_property(monster_2d, "position", base_position + Vector2(0.0, profile.monster_attack_lunge_distance), profile.monster_attack_lunge_duration * 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	attack_tween.tween_property(monster_2d, "position", base_position, profile.monster_attack_lunge_duration * 0.58).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	attack_tween.finished.connect(_on_monster_attack_finished.bind(monster_2d, base_position), CONNECT_ONE_SHOT)
	_monster_attack_tweens[monster_id] = {"tween": attack_tween, "base_position": base_position}

## 在怪物下冲结束时精确回写原位置并清除记录，避免下一回合沿用过期 Tween。
## @param monster 完成攻击表现的怪物。
## @param base_position 攻击开始前的排布位置。
## @return void 无返回值。
func _on_monster_attack_finished(monster: Node2D, base_position: Vector2) -> void:
	if monster and is_instance_valid(monster):
		monster.position = base_position
		_monster_attack_tweens.erase(monster.get_instance_id())

## 根据本次总碰撞数值和结果语义构建局部与全局共用的冲击配方。
## @param impact_amount 本次实际伤害与护盾吸收量组成的总碰撞数值。
## @param is_critical 是否为暴击结果。
## @param is_lethal 是否为击杀结果。
## @param shield_broken 是否为护盾破裂结果。
## @return Dictionary 已钳制的受力、震屏与 Hit Stop 参数。
func _build_impact_recipe(impact_amount: int, is_critical: bool, is_lethal: bool, shield_broken: bool) -> Dictionary:
	# 总碰撞数值是所有冲击动画共享的绝对输入，避免局部与全局强度曲线不一致。
	var impact_intensity: float = profile.resolve_feedback_intensity(float(impact_amount))
	return {
		"offset": profile.resolve_impact_offset(impact_intensity, is_critical, is_lethal, shield_broken),
		"duration": profile.resolve_impact_duration(impact_intensity),
		"screen_shake_pixels": profile.resolve_screen_shake_pixels(impact_intensity, is_critical, is_lethal, shield_broken),
		"screen_shake_duration": profile.resolve_screen_shake_duration(impact_intensity),
		"hit_stop_seconds": profile.resolve_hit_stop_seconds(impact_intensity, is_critical, is_lethal, shield_broken)
	}

## 将一次目标受力配方追加到目标专属 FIFO，保证连续命中不会覆盖前一段表现。
## @param target 本次结算目标。
## @param impact_color 结果语义色。
## @param impact_recipe 已由绝对数值曲线生成的冲击配方。
## @return void 无返回值。
func _enqueue_target_impact(target: Node, impact_color: Color, impact_recipe: Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		return
	# 实例 ID 作为队列键，确保不同范围目标的反馈彼此独立。
	var target_id: int = target.get_instance_id()
	# 同一目标的历史待播配方需要保留；不存在时从空队列开始。
	var target_queue: Array = _impact_queues.get(target_id, []) as Array
	# 队列条目同时保存颜色与数值配方，后续播放时不再读取可能变化的结算对象。
	var queued_impact: Dictionary = impact_recipe.duplicate()
	queued_impact["color"] = impact_color
	target_queue.append(queued_impact)
	_impact_queues[target_id] = target_queue
	if not _impact_tweens.has(target_id):
		_play_next_target_impact(target, target_id)

## 播放某个目标 FIFO 的下一条受力反馈；完成后再继续下一条，绝不杀死前一段 Tween。
## @param target 当前队列对应的战斗实体。
## @param target_id 队列键对应的实体实例 ID。
## @return void 无返回值。
func _play_next_target_impact(target: Node, target_id: int) -> void:
	if target == null or not is_instance_valid(target):
		_impact_queues.erase(target_id)
		_impact_tweens.erase(target_id)
		return
	# 队列从 Dictionary 取回后仍以数组形式保存，避免动态容器推断为 Variant。
	var target_queue: Array = _impact_queues.get(target_id, []) as Array
	if target_queue.is_empty():
		_impact_queues.erase(target_id)
		_impact_tweens.erase(target_id)
		return
	# 显式声明字典类型，避免 pop_front 的 Variant 返回值在警告即错误配置下失去类型信息。
	var next_impact: Dictionary = target_queue.pop_front()
	_impact_queues[target_id] = target_queue
	# 该命中的受力位移由数值曲线生成，读取时保留安全默认值以支持缺少可选字段的测试配方。
	var impact_offset: float = float(next_impact.get("offset", 0.0))
	# 该命中的总时长由数值曲线生成，不能在队列中被后续命中重写。
	var impact_duration: float = float(next_impact.get("duration", profile.impact_duration_min))
	# 该命中的结果色由结算语义决定。
	var impact_color: Color = next_impact.get("color", Color.WHITE)
	if target is Node2D:
		# Node2D 目标以当前位置作为每一段的独立归位基准，避免队列累积偏移。
		var target_2d: Node2D = target as Node2D
		# 受力起点在实际播放时读取，确保前一段已经精确复位。
		var base_position: Vector2 = target_2d.position
		# 实例 ID 决定左右方向，使同一目标的连续反馈保持稳定而非随机跳动。
		var direction: float = -1.0 if target_id % 2 == 0 else 1.0
		# 本条 Tween 只负责当前队首命中，结束信号会继续消费下一条。
		var impact_tween: Tween = target_2d.create_tween()
		impact_tween.set_parallel(true)
		impact_tween.tween_property(target_2d, "position", base_position + Vector2(impact_offset * direction, -impact_offset * 0.16), impact_duration * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		impact_tween.chain().tween_property(target_2d, "position", base_position, impact_duration * 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		# Sprite2D 缺失时仍完成位置受力，保持自定义怪物场景的安全降级。
		var sprite: Sprite2D = target_2d.get_node_or_null("Sprite2D") as Sprite2D
		if sprite:
			impact_tween.tween_property(sprite, "self_modulate", impact_color.lightened(0.28), impact_duration * 0.25)
			impact_tween.chain().tween_property(sprite, "self_modulate", Color.WHITE, impact_duration * 0.75)
		_impact_tweens[target_id] = impact_tween
		impact_tween.finished.connect(_on_target_impact_finished.bind(target, target_id), CONNECT_ONE_SHOT)
		return
	if _player_feedback_anchor == null:
		_on_target_impact_finished(target, target_id)
		return
	# 玩家实体以血量 UI 作为受击锚点，继续不把 HUD 路径泄露到结算层。
	var player_ui: Node = _player_feedback_anchor.get_parent()
	# 可选血条节点缺失时安全跳过本条并继续队列，不中断后续命中表现。
	var health_bar: CanvasItem = player_ui.get_node_or_null("HpBar") as CanvasItem if player_ui else null
	if health_bar == null:
		_on_target_impact_finished(target, target_id)
		return
	# 玩家血条的颜色闪白使用同一条数值时长曲线。
	var player_impact_tween: Tween = health_bar.create_tween()
	player_impact_tween.tween_property(health_bar, "modulate", impact_color.lightened(0.18), impact_duration * 0.35)
	player_impact_tween.tween_property(health_bar, "modulate", Color.WHITE, impact_duration * 0.65)
	_impact_tweens[target_id] = player_impact_tween
	player_impact_tween.finished.connect(_on_target_impact_finished.bind(target, target_id), CONNECT_ONE_SHOT)

## 在一条目标受力完成后释放占用并继续消费同一目标的下一条命中。
## @param target 当前队列对应的战斗实体。
## @param target_id 队列键对应的实体实例 ID。
## @return void 无返回值。
func _on_target_impact_finished(target: Node, target_id: int) -> void:
	_impact_tweens.erase(target_id)
	_play_next_target_impact(target, target_id)

## 为每个有效命中申请数值驱动的全局冲击；控制器限制连续批次的震屏与 Hit Stop 次数。
## @param impact_recipe 已由绝对数值曲线生成的冲击配方。
## @return void 无返回值。
func _request_value_scaled_impulse(impact_recipe: Dictionary) -> void:
	if _screen_impulse == null:
		return
	# 减弱模式只按固定比例缩小已计算的震屏，不重新解释伤害数值。
	var is_reduced: bool = _feedback_intensity == "reduced"
	# 震屏幅度从数值配方读取，减弱模式仅在最终输出阶段叠乘偏好比例。
	var shake_pixels: float = float(impact_recipe.get("screen_shake_pixels", 0.0))
	if is_reduced:
		shake_pixels *= profile.reduced_screen_shake_ratio
	# 震屏时长完全保留数值曲线结果，确保减弱模式与完整模式的节奏一致。
	var shake_duration: float = float(impact_recipe.get("screen_shake_duration", profile.screen_shake_duration_min))
	# 减弱模式禁用所有 Hit Stop，但仍把每一条震屏请求交给批次控制器消费。
	var hit_stop_seconds: float = 0.0 if is_reduced else float(impact_recipe.get("hit_stop_seconds", 0.0))
	_screen_impulse.enqueue_impulse(shake_pixels, shake_duration, hit_stop_seconds, profile.hit_stop_time_scale, profile.multi_hit_feedback_max_count)

## 将玩家、怪物或通用 CanvasItem 转换到浮字层可使用的屏幕坐标。
## @param target 本次结算目标。
## @return Vector2 浮字起始坐标。
func _resolve_feedback_position(target: Node) -> Vector2:
	if _is_player_feedback_target(target) and _player_feedback_anchor:
		return _player_feedback_anchor.global_position
	if target is Node2D:
		return (target as Node2D).global_position
	if _player_feedback_anchor:
		return _player_feedback_anchor.global_position
	return get_viewport().get_visible_rect().size * 0.5

## 判断目标是否为本战斗的真实玩家实体，以保证玩家的伤害与治疗均从生命 UI 右侧显示。
## @param target 需要判断的战斗实体。
## @return bool 目标是否与 PlayerManager 当前绑定的真实玩家一致。
func _is_player_feedback_target(target: Node) -> bool:
	if target == null or _player_manager == null:
		return false
	var player_entity: Node = _player_manager.call("get_combat_entity") if _player_manager.has_method("get_combat_entity") else _player_manager
	return target == player_entity or target == _player_manager

## 从跨语言 RefCounted 结果中安全读取整数，防止缺失字段阻断战斗流程。
## @param result C# 结果对象。
## @param property_name 属性名。
## @return int 读取到的整数，缺失时返回零。
func _read_result_int(result: RefCounted, property_name: StringName) -> int:
	if result.has_method("GetFeedbackInt"):
		return int(result.call("GetFeedbackInt", str(property_name)))
	# 跨语言属性读取天然返回 Variant，显式标注以通过警告即错误的静态检查。
	var value: Variant = result.get(property_name)
	return int(value) if value != null else 0

## 从跨语言 RefCounted 结果中安全读取布尔值。
## @param result C# 结果对象。
## @param property_name 属性名。
## @return bool 读取到的布尔值，缺失时返回 false。
func _read_result_bool(result: RefCounted, property_name: StringName) -> bool:
	if result.has_method("GetFeedbackBool"):
		return bool(result.call("GetFeedbackBool", str(property_name)))
	# 跨语言属性读取天然返回 Variant，显式标注以通过警告即错误的静态检查。
	var value: Variant = result.get(property_name)
	return bool(value) if value != null else false

## 从跨语言 RefCounted 结果中安全读取节点引用。
## @param result C# 结果对象。
## @param property_name 属性名。
## @return Node 节点引用，缺失或类型不符时返回 null。
func _read_result_node(result: RefCounted, property_name: StringName) -> Node:
	if result.has_method("GetFeedbackNode"):
		return result.call("GetFeedbackNode", str(property_name)) as Node
	# 跨语言属性读取天然返回 Variant，显式标注以通过警告即错误的静态检查。
	var value: Variant = result.get(property_name)
	return value as Node

## 从跨语言 RefCounted 结果中安全读取字符串。
## @param result C# 结果对象。
## @param property_name 属性名。
## @return String 读取到的字符串；缺失时返回空字符串。
## 从统一设置服务读取并校验表现强度偏好。
## @return void 无返回值。
func _load_feedback_intensity() -> void:
	var saved_value: String = str(SettingsManager.get_setting("battle", "feedback_intensity", "full"))
	set_feedback_intensity(saved_value, false)

## 更新表现强度并按需持久化；UI 只发意图，导演负责值校验和写入。
## @param intensity 候选稳定值，只允许 full 或 reduced。
## @param should_persist 是否写入本地设置。
## @return void 无返回值。
func set_feedback_intensity(intensity: String, should_persist: bool = true) -> void:
	if intensity != "full" and intensity != "reduced":
		push_warning("忽略未知的战斗表现强度：%s" % intensity)
		intensity = "full"
	_feedback_intensity = intensity
	if should_persist:
		SettingsManager.set_setting("battle", "feedback_intensity", _feedback_intensity)
	# 设置面板可能不存在，使用显式 Node 类型避免三元表达式推断为 Variant。
	var settings_panel: Node = _battle_root.get_node_or_null("UI/BattleSettingsPanel") if _battle_root else null
	if settings_panel and settings_panel.has_method("set_active_feedback_intensity"):
		settings_panel.call("set_active_feedback_intensity", _feedback_intensity)

## 配置设置面板并接收用户的强度选择意图。
## @return void 无返回值。
func _configure_settings_panel() -> void:
	# 设置面板可能不存在，使用显式 Node 类型避免三元表达式推断为 Variant。
	var settings_panel: Node = _battle_root.get_node_or_null("UI/BattleSettingsPanel") if _battle_root else null
	if settings_panel == null:
		return
	if settings_panel.has_method("configure_feedback_intensity_options"):
		# 通过动态调用传递给 Typed Array 参数时，必须保留 Dictionary 元素类型，避免字面量退化为普通 Array。
		var intensity_options: Array[Dictionary] = []
		intensity_options.append({"value": "full", "label": "完整"})
		intensity_options.append({"value": "reduced", "label": "减弱"})
		settings_panel.call("configure_feedback_intensity_options", intensity_options, _feedback_intensity)
	if settings_panel.has_signal("feedback_intensity_selected") and not settings_panel.is_connected("feedback_intensity_selected", _on_feedback_intensity_selected):
		settings_panel.connect("feedback_intensity_selected", _on_feedback_intensity_selected)

## 转交设置面板的表现强度选择。
## @param intensity 设置面板发出的稳定值。
## @return void 无返回值。
func _on_feedback_intensity_selected(intensity: String) -> void:
	set_feedback_intensity(intensity)

## 断开跨场景信号并回收所有临时表现，防止重进战斗后重复订阅。
## @return void 无返回值。
func _exit_tree() -> void:
	for receiver in _connected_receivers.values():
		if is_instance_valid(receiver) and receiver.has_signal("DamageResolved") and receiver.is_connected("DamageResolved", _on_damage_resolved):
			receiver.disconnect("DamageResolved", _on_damage_resolved)
	_connected_receivers.clear()
	for health_entry in _connected_health_components.values():
		var health_component: Node = health_entry.get("component") as Node
		var health_callable: Callable = health_entry.get("callable")
		if is_instance_valid(health_component) and health_component.has_signal("ValueChanged") and health_component.is_connected("ValueChanged", health_callable):
			health_component.disconnect("ValueChanged", health_callable)
	_connected_health_components.clear()
	for death_presenter in _connected_death_presenters.values():
		var entity: Node = death_presenter.get("entity")
		var death_callable: Callable = death_presenter.get("callable")
		if is_instance_valid(entity) and entity.has_signal("DeathPresentationRequested") and entity.is_connected("DeathPresentationRequested", death_callable):
			entity.disconnect("DeathPresentationRequested", death_callable)
	_connected_death_presenters.clear()
	for monster_id in _monster_attack_tweens.keys():
		var attack_entry: Dictionary = _monster_attack_tweens[monster_id]
		var attack_tween: Tween = attack_entry.get("tween")
		if attack_tween and attack_tween.is_valid() and attack_tween.is_running():
			attack_tween.kill()
	_monster_attack_tweens.clear()
	# 场景退出时终止正在播放的局部受力，防止回调继续访问已释放的战斗节点。
	for impact_tween in _impact_tweens.values():
		if impact_tween and impact_tween.is_valid() and impact_tween.is_running():
			impact_tween.kill()
	_impact_tweens.clear()
	# 未播放的队列只属于当前战斗，离开场景后必须丢弃而不能带入下一场战斗。
	_impact_queues.clear()
