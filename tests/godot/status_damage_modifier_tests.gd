extends SceneTree

const ATTRIBUTE_SCRIPT := "res://entities/components/AttributeComponent.cs"
const BURN_STATUS_SCRIPT := "res://core/combat/buffs/BurnStatusData.cs"
const DAMAGE_RECEIVER_SCRIPT := "res://entities/components/DamageReceiverComponent.cs"
const HEALTH_SCRIPT := "res://entities/components/HealthComponent.cs"
const STARTING_STATS_SCRIPT := "res://resources/stats/StartingStats.cs"

const DAMAGE_MODIFIER_CRITICAL := 2
const DAMAGE_TYPE_REAL := 2
const ELEMENT_NONE := 0

var _failures: Array[String] = []
var _created_nodes: Array[Node] = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_status_damage_defaults_to_no_direct_attack_modifiers()
	_test_status_damage_can_enable_critical_without_other_modifiers()

	_finish()


func _test_status_damage_defaults_to_no_direct_attack_modifiers() -> void:
	var source := _create_combat_entity("Source", 100)
	var target := _create_combat_entity("Target", 100)
	_add_attributes(source, 1.0, 3.0, 0.0, 1.0)
	_add_attributes(target, 0.0, 1.5, 1.0, 0.0)
	_health(source).TakeDamage(50, ELEMENT_NONE)
	var receiver = _damage_receiver(target)
	receiver.RandomVarianceMin = 2.0
	receiver.RandomVarianceMax = 2.0
	var burn = _create_real_burn(10.0)

	burn.CreateInstance(source, target).OnOwnerTurnStart()

	_assert(_health(target).CurrentValue == 90, "状态伤害默认不应触发闪避、暴击或随机浮动。")
	_assert(_health(source).CurrentValue == 50, "状态伤害默认不应触发吸血。")


func _test_status_damage_can_enable_critical_without_other_modifiers() -> void:
	var source := _create_combat_entity("Source", 100)
	var target := _create_combat_entity("Target", 100)
	_add_attributes(source, 1.0, 3.0, 0.0, 1.0)
	_add_attributes(target, 0.0, 1.5, 1.0, 0.0)
	_health(source).TakeDamage(50, ELEMENT_NONE)
	var receiver = _damage_receiver(target)
	receiver.RandomVarianceMin = 2.0
	receiver.RandomVarianceMax = 2.0
	var burn = _create_real_burn(10.0)
	burn.DamageModifiers = DAMAGE_MODIFIER_CRITICAL

	burn.CreateInstance(source, target).OnOwnerTurnStart()

	_assert(_health(target).CurrentValue == 70, "只开启暴击的状态伤害应造成 10 * 3 点伤害。")
	_assert(_health(source).CurrentValue == 50, "只开启暴击时不应顺带触发吸血。")


func _create_real_burn(damage_per_stack: float):
	var burn = load(BURN_STATUS_SCRIPT).new()
	burn.DamagePerStack = damage_per_stack
	burn.DamageType = DAMAGE_TYPE_REAL
	burn.Element = ELEMENT_NONE
	return burn


func _create_combat_entity(entity_name: String, max_health: int) -> Node:
	var entity := Node.new()
	entity.name = entity_name
	_created_nodes.append(entity)
	var components := Node.new()
	components.name = "Components"
	entity.add_child(components)

	var health = load(HEALTH_SCRIPT).new()
	health.name = "HealthComponent"
	components.add_child(health)
	health.InitializeMax(max_health)

	var receiver = load(DAMAGE_RECEIVER_SCRIPT).new()
	receiver.name = "DamageReceiverComponent"
	receiver.RandomVarianceMin = 1.0
	receiver.RandomVarianceMax = 1.0
	components.add_child(receiver)

	return entity


func _add_attributes(
	entity: Node,
	crit_rate: float,
	crit_damage: float,
	evasion_rate: float,
	lifesteal_rate: float
) -> void:
	var attributes = load(ATTRIBUTE_SCRIPT).new()
	attributes.name = "AttributeComponent"
	entity.get_node("Components").add_child(attributes)
	var stats = load(STARTING_STATS_SCRIPT).new()
	stats.BaseMaxHealth = 100.0
	stats.BaseCritRate = crit_rate
	stats.BaseCritDamage = crit_damage
	stats.BaseEvasionRate = evasion_rate
	stats.BaseLifestealRate = lifesteal_rate
	attributes.InitializeWithData(stats)


func _health(entity: Node):
	return entity.get_node("Components/HealthComponent")


func _damage_receiver(entity: Node):
	return entity.get_node("Components/DamageReceiverComponent")


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for node in _created_nodes:
		if is_instance_valid(node):
			node.free()

	if _failures.is_empty():
		print("All status damage modifier Godot tests passed.")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)
