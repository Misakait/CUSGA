extends Control
class_name ActionTimeline

# ==========================================
# 动画与视觉参数配置区 (可在 Godot 检查器中直接调整)
# ==========================================

@export_category("显示设置")

@export_group("布局设置")
## 行动轴内最多显示的角色数量上限
@export var max_timeline_slots: int = 8
## 轴内各个角色方块之间的间隔间距
@export var slot_spacing: int = 1
## 每个实体名称块的基础宽高尺寸
@export var ui_item_size: Vector2 = Vector2(100, 30)

@export_group("缩放设置")
## 普通实体的行动块缩放比例
@export var scale_normal: Vector2 = Vector2(0.8, 0.8)
## 玩家拖拽卡牌悬停选择目标时的缩放比例
@export var scale_highlight: Vector2 = Vector2(0.9, 0.9)
## 当前正在行动的实体的行动块缩放比例
@export var scale_current: Vector2 = Vector2(0.95, 0.95)

@export_group("颜色设置")
## 玩家名称块的颜色（默认为浅蓝）
@export var color_player: Color = Color(0.5, 0.8, 1.0)
## 敌方名称块的颜色（默认为淡红）
@export var color_enemy: Color = Color(1.0, 0.5, 0.5)
## 当前正在行动实体的文字高亮颜色（默认为黄色）
@export var color_active_font: Color = Color(1.0, 1.0, 1.0, 1.0)
## 行动块的半透明背景底色
@export var color_bg: Color = Color(0.2, 0.2, 0.2, 0.8)

@export_group("动画设置")
## 缩放动画的过渡时间（秒）
@export var anim_tween_duration: float = 0.2


# ==========================================
# 内部状态变量
# ==========================================

## 存储当前在轴上实际展示的 UI 节点列表
var active_labels: Array[Label] = []
## 内部记录的当前正在行动的实体对象
var _current_active_entity: Variant = null
## 内部记录当前模拟出来的实体顺序（支持同一实体出现多次）
var _predicted_sequence: Array = []
## 行动值总量，来自 BattleManager，用于保持时间轴预测一致
var _action_total: float = 10000.0

func _ready() -> void:
	# 初始化时清空所有占位的子节点
	for child in get_children():
		child.queue_free()

## 更新行动轴的对外接口，完全与 BattleManager 解耦
## @param combatants: 当前所有存活实体的数组
## @param current_active: 当前正在执行回合的实体（可为 null）
func update_timeline(combatants: Array, current_active: Variant, action_total: float = 10000.0) -> void:
	_current_active_entity = current_active
	# 统一行动值基准，避免时间轴与战斗实际顺序出现偏差
	_action_total = action_total if action_total > 0 else 10000.0

	# 根据当前战斗状态模拟未来几个回合的行动序列（会自动剔除死亡怪物，并在速度差异大时重复出现同一角色）
	_predicted_sequence = _predict_turns(combatants, current_active)

	_refresh_ui()

## 核心算法：模拟并预测战斗行动轴顺序
func _predict_turns(combatants: Array, current_active: Variant) -> Array:
	var sim_state: Array = []

	# 步骤 1：搜集有效存活实体的当前行动值（AV）与速度状态
	for entity in combatants:
		# 判断实体对象本身是否还有效（剔除已被引擎队列删除的死亡怪物）
		if not is_instance_valid(entity) or entity.is_queued_for_deletion():
			continue

		# 进一步过滤：判断血量，防止有怪物已空血但还未来得及从场景销毁
		if "hp" in entity and entity.hp <= 0:
			continue # 玩家等 GDScript 节点，血量不足
		var health_comp = entity.get_node_or_null("Components/HealthComponent") if entity.has_method("get_node_or_null") else null
		if health_comp and health_comp.get("CurrentValue") != null and health_comp.get("CurrentValue") <= 0:
			continue # C# 组件的怪物节点，血量不足

		sim_state.append({
			"entity": entity,
			"av": _get_av(entity),
			"speed": _get_speed(entity)
		})

	var sequence: Array = []

	# 步骤 2：处理当前正在行动的实体（它一定处于时间轴的顶端，索引为0）
	if current_active and is_instance_valid(current_active) and not current_active.is_queued_for_deletion():
		sequence.append(current_active)

		# 因为当前行动者可能刚好在 0 点还未重新计算下一个回合的 AV，所以我们在模拟器里需要强行将其 AV 重置，否则会无限连动
		for state in sim_state:
			if state["entity"] == current_active:
				if state["av"] <= 0.01: # 刚到它的回合时，av 会很接近 0
					state["av"] = _action_total / state["speed"]
				break

	# 步骤 3：不断推演，直到填满配置的显示上限
	while sequence.size() < max_timeline_slots:
		if sim_state.is_empty():
			break # 场上没有存活单位了

		# 找到推演状态中行动值最小（最先行动）的实体
		var min_state = sim_state[0]
		for state in sim_state:
			if state["av"] < min_state["av"]:
				min_state = state

		var min_av = min_state["av"]

		# 将其存入预测队列
		sequence.append(min_state["entity"])

		# 时间推进：所有人的行动值均减去经历的这部分时间
		for state in sim_state:
			state["av"] -= min_av

		# 获得回合的人模拟结束行动，行动值重置，准备参与下一轮顺位的推演（速度越快，重置后的初始值越低，越早进入下一次回合）
		min_state["av"] = _action_total / min_state["speed"]

	return sequence

## 安全获取实体行动值的辅助函数
func _get_av(entity: Variant) -> float:
	if entity.has_method("get_meta") and entity.has_meta("action_value"):
		return entity.get_meta("action_value")
	elif "action_value" in entity:
		return float(entity.action_value)
	return 100.0

## 安全获取实体速度的辅助函数
func _get_speed(entity: Variant) -> float:
	var real_entity = entity.get_combat_entity() if entity.has_method("get_combat_entity") else entity
	if real_entity and real_entity.has_method("get_node_or_null"):
		var attr_comp = real_entity.get_node_or_null("Components/AttributeComponent")
		if attr_comp and attr_comp.has_method("GetEffectiveValue"):
			var val = attr_comp.call("GetEffectiveValue", 4)
			if val != null and float(val) > 1.0:
				return float(val)

	# 假设玩家在 player_manager 中定义了 speed
	if "speed" in entity:
		return float(entity.speed)
	# 否则这里作为通用默认值返回 100.0 (后续可在怪物数据里读取)
	return 100.0

## 安全获取实体名称的辅助函数
func _get_name(entity: Variant) -> String:
	if entity.has_method("get_meta") and entity.has_meta("MonsterName"):
		return entity.get_meta("MonsterName")
	elif entity.get("BaseData") and entity.get("BaseData").get("MonsterName"):
		return entity.get("BaseData").get("MonsterName")
	elif "player" in entity.name.to_lower():
		return "玩家"
	return "未知"

## 根据预测出的序列全量刷新 UI，实现基于实体的平滑移动与复用
func _refresh_ui() -> void:
	var new_labels: Array[Label] = []
	var old_labels = active_labels.duplicate()

	# 弹出上一个行动者的标签，防止其错误匹配到该实体的未来回合导致向下滑动
	var popped_old_active: Label = null
	if old_labels.size() > 0 and _current_active_entity != null:
		if old_labels[0].get_meta("entity") != _current_active_entity:
			popped_old_active = old_labels.pop_front()

	for i in range(_predicted_sequence.size()):
		var entity = _predicted_sequence[i]

		# 尝试在旧标签中找到匹配的实体
		var matched_label: Label = null
		for j in range(old_labels.size()):
			if old_labels[j].get_meta("entity") == entity:
				matched_label = old_labels[j]
				old_labels.remove_at(j)
				break

		if not matched_label:
			# 如果没有找到匹配的，创建一个新的
			matched_label = Label.new()
			matched_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			matched_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			matched_label.pivot_offset = Vector2(ui_item_size.x / 2.0, ui_item_size.y / 2.0)
			matched_label.custom_minimum_size = ui_item_size

			var style = StyleBoxFlat.new()
			style.bg_color = color_bg
			style.corner_radius_top_left = 5
			style.corner_radius_top_right = 5
			style.corner_radius_bottom_right = 5
			style.corner_radius_bottom_left = 5
			matched_label.add_theme_stylebox_override("normal", style)

			# 新节点从下方滑入
			matched_label.position = Vector2(0, (i + 2) * (ui_item_size.y + slot_spacing))
			matched_label.modulate.a = 0.0 # 初始透明

			add_child(matched_label)

		# 绑定实体引用与更新名字
		matched_label.set_meta("entity", entity)
		matched_label.text = _get_name(entity)

		# 根据实体类型设置颜色
		var base_color = color_player if "player" in entity.name.to_lower() else color_enemy

		# 计算该实体本次所在的目标位置
		var target_pos = Vector2(0, i * (ui_item_size.y + slot_spacing))

		# 并行执行位置和颜色的过渡动画
		var t_pos = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t_pos.set_parallel(true)
		t_pos.tween_property(matched_label, "position", target_pos, anim_tween_duration)
		t_pos.tween_property(matched_label, "modulate", base_color, anim_tween_duration)

		# 第一个索引（顶端）通常为当前行动实体，采用最大号缩放且文字高亮（实现回合更替时的平滑放大效果）
		if i == 0 and entity == _current_active_entity:
			_tween_scale(matched_label, scale_current)
			matched_label.add_theme_color_override("font_color", color_active_font)
		else:
			_tween_scale(matched_label, scale_normal)
			matched_label.remove_theme_color_override("font_color")

		new_labels.append(matched_label)

	if popped_old_active:
		old_labels.append(popped_old_active)

	# 移除不再需要的旧标签（例如死亡或被挤出时间轴的实体），添加向上滑出动画
	for old_label in old_labels:
		var t_fade = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t_fade.set_parallel(true)
		t_fade.tween_property(old_label, "position:y", old_label.position.y - (ui_item_size.y + slot_spacing), anim_tween_duration)
		t_fade.tween_property(old_label, "modulate:a", 0.0, anim_tween_duration)
		t_fade.chain().tween_callback(old_label.queue_free)

	active_labels = new_labels

## 外部接口：供卡牌管理器(CardManager)在选卡拖拽到怪物身上时，实现行动轴中相关怪物方块联动高亮放大
func highlight_entity(target_entity: Variant, is_highlight: bool) -> void:
	if not target_entity:
		return

	# 遍历整个时间轴的节点寻找该目标（如果目标速度极快，时间轴里可能有好几个他的行动回合）
	for i in range(active_labels.size()):
		var label = active_labels[i]
		var entity = label.get_meta("entity", null)

		if entity == target_entity:
			# 若该槽位刚好是时间轴顶部当前正在行动的主回合，不覆盖其巨大的特写缩放
			if i == 0 and entity == _current_active_entity:
				continue

			if is_highlight:
				_tween_scale(label, scale_highlight)
			else:
				_tween_scale(label, scale_normal)

## 执行平滑缩放效果的工具方法
func _tween_scale(node: Control, target_scale: Vector2) -> void:
	var t = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(node, "scale", target_scale, anim_tween_duration)
