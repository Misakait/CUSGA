extends Node2D

var player_entity: Node = null
var health_component: Node = null
var energy_component: Node = null
var attribute_component: Node = null

var hp: int:
	get:
		if health_component:
			var val = health_component.get("CurrentValue")
			if val != null and val > 0: return val
			if val != null and val == 0: return 0
		return _fallback_hp

var max_hp: int:
	get:
		if health_component:
			var val = health_component.get("MaxValue")
			if val != null and val > 0: return val
		return _fallback_max_hp

var energy: int:
	get:
		if energy_component:
			var val = energy_component.get("CurrentValue")
			if val != null and val > 0: return val
			if val != null and val == 0: return 0
		return _fallback_energy

var max_energy: int:
	get:
		if energy_component:
			var val = energy_component.get("MaxValue")
			if val != null and val > 0: return val
		return _fallback_max_energy

## 速度越高，计算出的行动值 (action_value) 越低，在 ATB 机制下就能更快获得回合。
var speed: float:
	get:
		if attribute_component:
			var val = attribute_component.get("Speed")
			# AttributeComponent 未初始化时，Speed 会被 C# 限制为最小的 1.0。
			# 如果速度 <= 1.0，说明大概率是未初始化的临时玩家，强制走兜底的 100.0
			if val != null and val > 1.0:
				return float(val)
		return _fallback_speed

## 玩家的行动值（决定回合顺序的内部计量尺）。
## BattleManager 每次会在 CALCULATE_TURN 中将全体人员的 action_value 逐步扣除，谁先归零谁先行动。
var action_value: float = 0.0

# 兜底变量，当没有找到全局玩家时使用
var _fallback_hp: int = 1000
var _fallback_max_hp: int = 1000
var _fallback_energy: int = 100
var _fallback_max_energy: int = 100
var _fallback_speed: float = 100.0

func _ready() -> void:
	_initialize_player_entity()
	refresh_energy(true)
	refresh_hp(true)
	reset_action_value()

## 初始化玩家实体，将战斗系统与全局玩家实体解耦/耦合
func _initialize_player_entity() -> void:
	# 尝试从全局或根节点获取真实的玩家实体
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		player_entity = players[0]
	else:
		# 尝试从常见路径寻找
		var gameplay_port = get_tree().root.get_node_or_null("Main/Gameplay/GameplayPort")
		if gameplay_port and gameplay_port.Player:
			player_entity = gameplay_port.Player
		else:
			var main_player = get_tree().root.get_node_or_null("Main/Player")
			if main_player:
				player_entity = main_player

	if not player_entity:
		# 如果还是没找到，为了允许独立测试战斗场景，临时实例化一个
		var player_scene = load("res://scenes/player_scenes/player.tscn")
		if player_scene:
			player_entity = player_scene.instantiate()
			add_child(player_entity)
			print("未找到全局玩家，已为战斗系统临时实例化一个玩家实体。")

			# 为临时玩家强行注入兜底生命值，避免被直接秒杀
			var temp_hc = player_entity.get_node_or_null("Components/HealthComponent")
			if temp_hc and temp_hc.has_method("InitializeMax"):
				temp_hc.call("InitializeMax", _fallback_max_hp)

			var temp_ec = player_entity.get_node_or_null("Components/EnergyComponent")
			if temp_ec and temp_ec.has_method("InitializeMax"):
				temp_ec.call("InitializeMax", _fallback_max_energy)

	if player_entity:
		health_component = player_entity.get_node_or_null("Components/HealthComponent")
		energy_component = player_entity.get_node_or_null("Components/EnergyComponent")
		attribute_component = player_entity.get_node_or_null("Components/AttributeComponent")

		if health_component:
			if health_component.has_signal("ValueChanged"):
				health_component.connect("ValueChanged", _on_health_changed)
			elif health_component.has_signal("value_changed"):
				health_component.connect("value_changed", _on_health_changed)

		if energy_component:
			if energy_component.has_signal("ValueChanged"):
				energy_component.connect("ValueChanged", _on_energy_changed)
			elif energy_component.has_signal("value_changed"):
				energy_component.connect("value_changed", _on_energy_changed)

func get_combat_entity() -> Node:
	if player_entity:
		return player_entity
	return self

func _on_health_changed(_current: int, _max_val: int) -> void:
	refresh_hp()

func _on_energy_changed(_current: int, _max_val: int) -> void:
	refresh_energy()

## 回合开始时被 BattleManager 调用，用于重置该实体的行动条
func reset_action_value() -> void:
	# 核心公式：10000 / 速度
	action_value = 10000.0 / speed

func recover_hp(amount:int):
	if health_component and health_component.has_method("Add"):
		health_component.call("Add", amount)
	else:
		_fallback_hp = min(_fallback_hp + amount, _fallback_max_hp)
		refresh_hp()

func take_damage(amount:int):
	if health_component and health_component.has_method("TakeDamage"):
		# 传入0代表 ElementType.None
		health_component.call("TakeDamage", amount, 0)
	else:
		_fallback_hp = max(_fallback_hp - amount, 0)
		refresh_hp()

func lose_hp(amount:int):
	if health_component and health_component.has_method("Subtract"):
		health_component.call("Subtract", amount)
	else:
		_fallback_hp = max(_fallback_hp - amount, 0)
		refresh_hp()

func recover_energy(amount:int):
	if energy_component and energy_component.has_method("Add"):
		energy_component.call("Add", amount)
	else:
		_fallback_energy = min(_fallback_energy + amount, _fallback_max_energy)
		refresh_energy()

func consume_energy(amount:int):
	if energy_component and energy_component.has_method("Subtract"):
		energy_component.call("Subtract", amount)
	else:
		_fallback_energy = max(_fallback_energy - amount, 0)
		refresh_energy()

func refresh_energy(instant: bool = false):
	var bar = $"../UI/EnergyBar"
	if bar and bar.has_method("update_stat"):
		bar.update_stat(energy, max_energy, instant)

func refresh_hp(instant: bool = false):
	var bar = $"../UI/HpBar"
	if bar and bar.has_method("update_stat"):
		bar.update_stat(hp, max_hp, instant)
