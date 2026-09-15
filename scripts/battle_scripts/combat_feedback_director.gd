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

## 正在控制目标反应的 Tween，新的高优先级命中会安全替换旧反应。
var _impact_tweens: Dictionary = {}

## 正在控制怪物下冲攻击的 Tween 及其归位位置，防止连续行动争夺怪物位置。
var _monster_attack_tweens: Dictionary = {}

## 导演当前生效的表现强度稳定值。
var _feedback_intensity: String = "full"

## 上次 Hit Stop 请求的时间，用于范围命中节流。
var _last_hit_stop_msec: int = -1000000

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
			var death_callable := _on_monster_death_requested.bind(entity)
			entity.connect("DeathPresentationRequested", death_callable)
			_connected_death_presenters[entity_id] = {"entity": entity, "callable": death_callable}

## 将已结算的伤害事实变换为一次受控反馈。
## @param result C# DamageReceiverComponent 产生的只读伤害结果。
## @return void 无返回值。
func _on_damage_resolved(result: RefCounted) -> void:
	if not profile.enabled or result == null:
		return
	var target: Node = _read_result_node(result, "Target")
	if target == null or not is_instance_valid(target):
		return
	var actual_damage: int = _read_result_int(result, "ActualDamage")
	var hit_index: int = _read_result_int(result, "HitIndex")
	var hit_count: int = maxi(1, _read_result_int(result, "HitCount"))
	var is_evaded: bool = _read_result_bool(result, "IsEvaded")
	var is_critical: bool = _read_result_bool(result, "IsCritical")
	var is_lethal: bool = _read_result_bool(result, "IsLethal")
	var shield_absorbed: int = _read_result_int(result, "ShieldAbsorbedDamage")
	var shield_broken: bool = _read_result_bool(result, "ShieldWasBroken")
	if actual_damage <= 0 and not is_evaded and shield_absorbed <= 0:
		return

	var priority: int = _resolve_priority(is_lethal, is_critical, shield_broken, is_evaded, actual_damage)
	var is_high_damage: bool = actual_damage >= profile.high_damage_hit_stop_threshold
	var is_combo_middle: bool = hit_count > 1 and hit_index > 0 and hit_index < hit_count - 1
	var display: Dictionary = _build_damage_display(actual_damage, is_evaded, is_critical, is_lethal, shield_absorbed, is_combo_middle, hit_index, hit_count)
	var anchor_position: Vector2 = _resolve_feedback_position(target)
	_spawn_popup(display, anchor_position)
	if shield_absorbed > 0 and actual_damage > 0:
		# 部分吸收不能把实际扣血数字染成灰色，因此以第二条较小浮字保留护盾事实。
		_spawn_popup({
			"text": "%d" % shield_absorbed,
			"color": profile.guard_color,
			"scale": 0.76,
			"rise": profile.popup_rise_distance * 0.78,
			"duration": float(display.get("duration", profile.popup_duration)),
			"delay": float(display.get("delay", 0.0))
		}, anchor_position + Vector2(0.0, 24.0))

	# 多段中间段只保留紧凑数字；首段和末段才驱动完整受力与画面冲击。
	if not is_combo_middle:
		_play_target_impact(target, maxi(priority, 85) if is_high_damage else priority, display.get("color", Color.WHITE))
		_request_high_priority_impulse(priority, is_high_damage)

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
	var recovered_amount: int = current_value - previous_value
	_spawn_popup({
		"text": "+%d" % recovered_amount,
		"color": profile.heal_color,
		"scale": 1.0,
		"rise": profile.popup_rise_distance,
		"duration": profile.popup_duration
	}, _resolve_feedback_position(owner))

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
	var monster_2d := monster as Node2D
	var tween := monster_2d.create_tween()
	tween.set_parallel(true)
	tween.tween_property(monster_2d, "scale", monster_2d.scale * 1.12, 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(monster_2d, "modulate:a", 0.0, 0.26).set_delay(0.08)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(monster) and monster.has_method("FinalizeCombatDeathPresentation"):
			monster.call("FinalizeCombatDeathPresentation")
	)

## 根据结果优先级构建文字、颜色、大小与时长。
## @param actual_damage 实际扣血量。
## @param is_evaded 是否闪避。
## @param is_critical 是否暴击。
## @param is_lethal 是否致死。
## @param shield_absorbed 护盾吸收量。
## @param is_combo_middle 是否为多段中间段。
## @param hit_index 当前伤害在多段序列中的零基索引。
## @param hit_count 本次伤害序列的总段数。
## @return Dictionary 浮字播放参数。
func _build_damage_display(actual_damage: int, is_evaded: bool, is_critical: bool, is_lethal: bool, shield_absorbed: int, is_combo_middle: bool, hit_index: int, hit_count: int) -> Dictionary:
	# 多段浮字以更短时长完成相同上浮距离，形成更快的连击节奏。
	var duration: float = profile.popup_duration * profile.multi_hit_popup_duration_multiplier if hit_count > 1 else profile.popup_duration
	# 同帧结算的多段数字按段号依次进入画面，避免彼此完全遮挡。
	var start_delay: float = profile.multi_hit_popup_stagger_seconds * float(hit_index) if hit_count > 1 else 0.0
	if is_evaded:
		return {"text": "MISS", "color": profile.evade_color, "scale": 1.00, "rise": profile.popup_rise_distance, "duration": duration, "delay": start_delay}
	if shield_absorbed > 0 and actual_damage <= 0:
		return {"text": "%d" % shield_absorbed, "color": profile.guard_color, "scale": 0.95, "rise": profile.popup_rise_distance, "duration": duration, "delay": start_delay}
	var color: Color = profile.normal_damage_color
	var scale_multiplier: float = 0.74 if is_combo_middle else 1.0
	var is_underlined: bool = false
	var is_emphasized: bool = false
	if is_critical:
		color = profile.critical_damage_color
		scale_multiplier = 1.42
		is_emphasized = true
	if is_lethal:
		scale_multiplier = maxf(scale_multiplier, 1.58)
		is_underlined = true
	return {"text": "%d" % actual_damage, "color": color, "scale": scale_multiplier, "rise": profile.popup_rise_distance, "duration": duration, "delay": start_delay, "underlined": is_underlined, "emphasized": is_emphasized}

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
		float(display.get("rise", profile.popup_rise_distance)),
		float(display.get("duration", profile.popup_duration)),
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

## 对怪物卡面或玩家 HUD 播放短促受力与颜色反馈。
## @param target 本次结算目标。
## @param priority 决定普通或重击强度。
## @param impact_color 结果语义色。
## @return void 无返回值。
func _play_target_impact(target: Node, priority: int, impact_color: Color) -> void:
	if target is Node2D:
		var target_2d := target as Node2D
		var target_id: int = target_2d.get_instance_id()
		var old_tween: Tween = _impact_tweens.get(target_id)
		if old_tween and old_tween.is_valid() and old_tween.is_running():
			old_tween.kill()
		var base_position: Vector2 = target_2d.position
		var offset: float = profile.heavy_impact_offset if priority >= 90 else profile.normal_impact_offset
		var direction: float = -1.0 if target_id % 2 == 0 else 1.0
		var tween := target_2d.create_tween()
		tween.set_parallel(true)
		tween.tween_property(target_2d, "position", base_position + Vector2(offset * direction, -offset * 0.16), profile.impact_duration * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(target_2d, "position", base_position, profile.impact_duration * 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		var sprite := target_2d.get_node_or_null("Sprite2D") as Sprite2D
		if sprite:
			tween.tween_property(sprite, "self_modulate", impact_color.lightened(0.28), profile.impact_duration * 0.25)
			tween.chain().tween_property(sprite, "self_modulate", Color.WHITE, profile.impact_duration * 0.75)
		_impact_tweens[target_id] = tween
		return
	if _player_feedback_anchor:
		var player_ui := _player_feedback_anchor.get_parent()
		var health_bar := player_ui.get_node_or_null("HpBar") as CanvasItem if player_ui else null
		if health_bar:
			var player_tween := health_bar.create_tween()
			player_tween.tween_property(health_bar, "modulate", impact_color.lightened(0.18), profile.impact_duration * 0.35)
			player_tween.tween_property(health_bar, "modulate", Color.WHITE, profile.impact_duration * 0.65)

## 只允许暴击、击杀、高额命中和护盾破裂申请屏幕冲击；减弱模式保留信息但禁用 Hit Stop。
## @param priority 本次结果优先级。
## @param is_high_damage 是否达到 Profile 配置的高额伤害阈值。
## @return void 无返回值。
func _request_high_priority_impulse(priority: int, is_high_damage: bool) -> void:
	if _screen_impulse == null or (priority < 80 and not is_high_damage):
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_hit_stop_msec < profile.hit_stop_cooldown_msec:
		return
	_last_hit_stop_msec = now_msec
	var reduced: bool = _feedback_intensity == "reduced"
	var shake_pixels: float = profile.full_screen_shake_pixels * (profile.reduced_screen_shake_ratio if reduced else 1.0)
	var hit_stop_seconds: float = 0.0
	if not reduced:
		if priority >= 100:
			hit_stop_seconds = profile.lethal_hit_stop_seconds
		elif priority >= 90:
			hit_stop_seconds = profile.critical_hit_stop_seconds
		else:
			hit_stop_seconds = profile.shield_break_hit_stop_seconds if priority >= 80 else profile.high_damage_hit_stop_seconds
	_screen_impulse.request_impulse(shake_pixels, 0.12, hit_stop_seconds, profile.hit_stop_time_scale)

## 根据结果事实给出独占反馈优先级。
## @param is_lethal 是否致死。
## @param is_critical 是否暴击。
## @param shield_broken 是否破盾。
## @param is_evaded 是否闪避。
## @param actual_damage 实际扣血量。
## @return int 优先级数值，越大越重要。
func _resolve_priority(is_lethal: bool, is_critical: bool, shield_broken: bool, is_evaded: bool, actual_damage: int) -> int:
	if is_lethal:
		return 100
	if is_critical and actual_damage > 0:
		return 90
	if shield_broken:
		return 80
	if is_evaded:
		return 70
	return 60 if actual_damage > 0 else 50

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
	var value = result.get(property_name)
	return int(value) if value != null else 0

## 从跨语言 RefCounted 结果中安全读取布尔值。
## @param result C# 结果对象。
## @param property_name 属性名。
## @return bool 读取到的布尔值，缺失时返回 false。
func _read_result_bool(result: RefCounted, property_name: StringName) -> bool:
	if result.has_method("GetFeedbackBool"):
		return bool(result.call("GetFeedbackBool", str(property_name)))
	var value = result.get(property_name)
	return bool(value) if value != null else false

## 从跨语言 RefCounted 结果中安全读取节点引用。
## @param result C# 结果对象。
## @param property_name 属性名。
## @return Node 节点引用，缺失或类型不符时返回 null。
func _read_result_node(result: RefCounted, property_name: StringName) -> Node:
	if result.has_method("GetFeedbackNode"):
		return result.call("GetFeedbackNode", str(property_name)) as Node
	var value = result.get(property_name)
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
	var settings_panel := _battle_root.get_node_or_null("UI/BattleSettingsPanel") if _battle_root else null
	if settings_panel and settings_panel.has_method("set_active_feedback_intensity"):
		settings_panel.call("set_active_feedback_intensity", _feedback_intensity)

## 配置设置面板并接收用户的强度选择意图。
## @return void 无返回值。
func _configure_settings_panel() -> void:
	var settings_panel := _battle_root.get_node_or_null("UI/BattleSettingsPanel") if _battle_root else null
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
