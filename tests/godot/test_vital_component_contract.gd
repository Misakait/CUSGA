@tool
extends McpTestSuite

## 数值型资源组件（生命 / 能量 / 饱食）GDScript 生产边界契约套件。
##
## 套件锁定生产场景的脚本切换、恢复与扣除的返回值语义、上限钳制规则、
## Depleted 与 ValueChanged 的信号顺序，以及 C# 消费者只依赖稳定协议。

const VITAL_SCRIPT: GDScript = preload("res://entities/components/vital_component_base.gd")
const HEALTH_SCRIPT: GDScript = preload("res://entities/components/health_component.gd")
const ENERGY_SCRIPT: GDScript = preload("res://entities/components/energy_component.gd")
const SATIETY_SCRIPT: GDScript = preload("res://entities/components/satiety_component.gd")
## C# 可选助手：C# 缺席时安全收起跨语言对照，避免解析期错误与「空源文假通过」。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")

## 玩家场景序列化的生命上限，迁移前后必须保持同一个值。
const PLAYER_HEALTH_MAX: int = 1000


## 返回套件名称，供 MCP 按批次筛选测试。
func suite_name() -> String:
	return "vital_component_contract"


## 在编辑场景根下创建一个测试宿主节点，让子组件的 _ready 正常触发。
##
## @return 宿主节点；当前没有打开场景时返回 null。
func _make_host() -> Node:
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return null

	var host_node := Node.new()
	host_node.name = "_McpTestVitalHost"
	scene_root.add_child(host_node)
	track(host_node)
	return host_node


## 进入场景树时记录 ValueChanged 事件。
##
## @param component 数值组件。
## @return 用于收集事件的数组。
func _watch_value_changed(component: Node) -> Array:
	var changes: Array = []
	component.ValueChanged.connect(
		func(current_value: int, max_value: int) -> void:
			changes.append(Vector2i(current_value, max_value))
	)
	return changes


## 进入场景树时记录 Depleted 事件。
##
## @param component 数值组件。
## @return 用于收集事件的数组。
func _watch_depleted(component: Node) -> Array:
	var depletions: Array = []
	component.Depleted.connect(func() -> void: depletions.append(true))
	return depletions


## 验证生产场景已切换到 GDScript 组件，旧 C# 实现仍作为垫片保留。
func test_production_scenes_and_compat_shims() -> void:
	var player_scene: String = FileAccess.get_file_as_string("res://scenes/player_scenes/player.tscn")
	for gd_name: String in [
		"energy_component.gd", "health_component.gd", "satiety_component.gd",
	]:
		assert_true(
			player_scene.contains("res://entities/components/" + gd_name),
			"玩家场景必须使用 GDScript %s。" % gd_name
		)
	for legacy_name: String in [
		"EnergyComponent.cs", "HealthComponent.cs", "SatietyComponent.cs",
	]:
		assert_false(
			player_scene.contains(legacy_name),
			"玩家场景不得继续引用旧 C# %s。" % legacy_name
		)
	assert_true(
		player_scene.contains("MaxValue = %d" % PLAYER_HEALTH_MAX),
		"玩家生命上限序列化值必须保持不变。"
	)

	var monster_scene: String = FileAccess.get_file_as_string("res://scenes/monster_scenes/monster.tscn")
	assert_true(
		monster_scene.contains("res://entities/components/health_component.gd"),
		"怪物场景必须使用 GDScript 生命组件。"
	)
	assert_false(
		monster_scene.contains("HealthComponent.cs"),
		"怪物场景不得继续引用旧 C# 生命组件。"
	)

	for compat_path: String in [
		"res://entities/components/VitalComponentBase.cs",
		"res://entities/components/HealthComponent.cs",
		"res://entities/components/EnergyComponent.cs",
		"res://entities/components/SatietyComponent.cs",
	]:
		## C# 垫片仍在时必须可加载；C# 退役后这些路径按条件收起（不再有可加载对象）。
		assert_true(
			not CS_OPTIONAL.present(compat_path) or load(compat_path) != null,
			"%s 必须作为兼容垫片保留并且可以加载。" % compat_path
		)


## 验证默认补满、上限初始化与 GDScript 子类继承关系。
func test_default_refill_and_initialize_max() -> void:
	var host_node: Node = _make_host()
	if host_node == null:
		skip("当前没有打开的场景，无法验证 _ready 补满行为。")
		return

	var component: Node = VITAL_SCRIPT.new()
	component.name = "Vital"
	component.set("MaxValue", 250)
	host_node.add_child(component)
	assert_eq(
		int(component.get("CurrentValue")),
		250,
		"进入场景树时当前值必须补满到上限。"
	)

	var changes: Array = _watch_value_changed(component)
	component.call("InitializeMax", 400)
	assert_eq(int(component.get("MaxValue")), 400, "InitializeMax 必须更新上限。")
	assert_eq(int(component.get("CurrentValue")), 400, "InitializeMax 必须把当前值补满。")
	assert_eq(changes.size(), 1, "InitializeMax 必须发出一次 ValueChanged。")
	assert_eq(changes[0], Vector2i(400, 400), "ValueChanged 必须携带新的当前值与上限。")

	var health: Node = HEALTH_SCRIPT.new()
	assert_true(health.has_signal("ValueChanged"), "生命组件必须继承数值组件的 ValueChanged 信号。")
	assert_true(health.has_signal("Depleted"), "生命组件必须继承数值组件的 Depleted 信号。")
	assert_true(health.has_signal("DamageTaken"), "生命组件必须保留 DamageTaken 信号。")
	assert_true(health.has_method("Add"), "生命组件必须继承 Add 方法协议。")
	assert_true(health.has_method("TakeDamage"), "生命组件必须暴露 TakeDamage 方法协议。")
	assert_true(ENERGY_SCRIPT.new().has_signal("Depleted"), "能量组件必须继承数值组件行为。")
	assert_true(SATIETY_SCRIPT.new().has_signal("Depleted"), "饱食组件必须继承数值组件行为。")


## 验证恢复与扣除都返回受边界限制后的实际数值。
func test_add_and_subtract_return_actual_amounts() -> void:
	var component: Node = VITAL_SCRIPT.new()
	track(component)
	component.call("InitializeMax", 100)

	assert_eq(component.call("Add", 50), 0, "已满时恢复必须返回 0。")
	assert_eq(component.call("Subtract", 30), 30, "扣除必须返回实际扣量。")
	assert_eq(int(component.get("CurrentValue")), 70, "扣除后必须保留剩余值。")
	assert_eq(component.call("Subtract", 1000), 70, "超额扣除必须被当前值限制。")
	assert_eq(int(component.get("CurrentValue")), 0, "超额扣除后必须归零。")
	assert_eq(component.call("Add", 40), 40, "恢复必须返回实际恢复量。")
	assert_eq(int(component.get("CurrentValue")), 40, "恢复后必须写入新的当前值。")
	assert_eq(component.call("Add", 0), 0, "非正数恢复必须返回 0。")
	assert_eq(component.call("Subtract", -5), 0, "非正数扣除必须返回 0。")


## 验证归零时的信号数量与先后顺序。
func test_depleted_and_value_changed_order() -> void:
	var component: Node = VITAL_SCRIPT.new()
	track(component)
	component.call("InitializeMax", 20)

	var events: Array = []
	component.ValueChanged.connect(
		func(current_value: int, max_value: int) -> void:
			events.append("changed:%d/%d" % [current_value, max_value])
	)
	component.Depleted.connect(func() -> void: events.append("depleted"))

	assert_eq(component.call("Subtract", 5), 5, "未归零的扣除必须返回实际扣量。")
	assert_eq(events.size(), 1, "未归零时只允许发出 ValueChanged。")
	assert_eq(component.call("Subtract", 40), 15, "归零扣除必须返回剩余值。")
	assert_eq(events.size(), 3, "归零时必须先发 ValueChanged 再发 Depleted。")
	assert_eq(events[1], "changed:0/20", "归零的 ValueChanged 必须携带当前值 0。")
	assert_eq(events[2], "depleted", "归零必须发出 Depleted。")


## 验证上限更新的保留当前值与钳制规则。
func test_set_max_preserving_current_semantics() -> void:
	var component: Node = VITAL_SCRIPT.new()
	track(component)
	component.call("InitializeMax", 100)
	component.call("Subtract", 30)

	var changes: Array = _watch_value_changed(component)
	component.call("SetMaxValuePreservingCurrent", 200)
	assert_eq(int(component.get("CurrentValue")), 70, "上限提高必须保留当前值。")
	assert_eq(changes.size(), 1, "上限变化必须发出一次 ValueChanged。")

	component.call("SetMaxValuePreservingCurrent", 50)
	assert_eq(int(component.get("MaxValue")), 50, "上限必须被写入。")
	assert_eq(int(component.get("CurrentValue")), 50, "当前值超出新上限时必须被钳制。")

	changes.clear()
	component.call("SetMaxValuePreservingCurrent", 50)
	assert_eq(changes.size(), 0, "上限与当前值都没有变化时不得发出信号。")

	component.call("SetMaxValuePreservingCurrent", 0)
	assert_eq(int(component.get("MaxValue")), 1, "低于 1 的上限必须按 1 处理。")
	assert_eq(int(component.get("CurrentValue")), 1, "钳制后当前值不得高于上限。")


## 验证生命组件的伤害入口、受伤信号与归零行为。
func test_health_take_damage_protocol() -> void:
	var health: Node = HEALTH_SCRIPT.new()
	track(health)
	health.call("InitializeMax", 500)

	var taken: Array = []
	health.DamageTaken.connect(
		func(amount: int, element_type: int) -> void:
			taken.append(Vector2i(amount, element_type))
	)
	assert_eq(health.call("TakeDamage", 120, 3), 120, "有效伤害必须返回实际扣血量。")
	assert_eq(int(health.get("CurrentValue")), 380, "伤害必须从当前生命值中扣除。")
	assert_eq(taken.size(), 1, "有效伤害必须发出一次 DamageTaken。")
	assert_eq(taken[0], Vector2i(120, 3), "DamageTaken 必须携带实际伤害与元素取值。")

	assert_eq(health.call("TakeDamage", 0, 1), 0, "零伤害必须返回 0。")
	assert_eq(taken.size(), 1, "零伤害不得发出 DamageTaken。")

	var depletions: Array = _watch_depleted(health)
	assert_eq(health.call("TakeDamage", 9999, 0), 380, "致死伤害必须返回剩余生命值。")
	assert_eq(depletions.size(), 1, "生命归零必须发出 Depleted。")
	assert_eq(health.call("TakeDamage", 10, 0), 0, "归零后的伤害必须返回 0。")
	assert_eq(
		String(health.get_script().resource_path),
		"res://entities/components/health_component.gd",
		"生命组件必须由本批 GDScript 实现提供。"
	)


## 验证 C# 消费者只依赖稳定属性/方法/信号协议，不再编译期引用具体类型。
func test_consumers_use_dynamic_protocol() -> void:
	## 本用例整体只对照 C# 源文；C# 退役后记跳过，而不是退化成「空源文假通过」或 0 断言失败。
	if not CS_OPTIONAL.present("res://entities/Player.cs"):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var expectations: Dictionary = {
		"res://entities/Player.cs": ['Call("TakeDamage"', '"Depleted"'],
		"res://entities/Monster.cs": ['Callable.From<int, int>(OnHealthChanged)', '"Depleted"'],
		"res://entities/components/AttributeComponent.cs": [
			'Call("InitializeMax"', 'Call("SetMaxValuePreservingCurrent"',
		],
		"res://entities/components/DamageReceiverComponent.cs": [
			'Call("TakeDamage"', '"CurrentValue"', 'Call("Add"',
		],
		"res://entities/components/AttributeComponent.cs#health-lookup": ['GetNodeOrNull<Node>("HealthComponent")'],
		"res://core/combat/effects/DamageEffect.cs": ['"CurrentValue"'],
		"res://core/combat/buffs/BossDamageCapStatusInstance.cs": ['"MaxValue"'],
		"res://core/application/GameplayPort.cs": ["public Node PlayerHealth"],
		"res://core/ui/hud/HealthBarUI.cs": ['Connect("ValueChanged"', "public void Bind(Node health)"],
	}
	for source_path: String in expectations.keys():
		var real_path: String = source_path.split("#")[0]
		var source: String = FileAccess.get_file_as_string(real_path)
		assert_false(
			source.contains("GetNode<HealthComponent>"),
			"%s 不得继续以泛型方式获取具体生命组件类型。" % real_path
		)
		assert_false(
			source.contains("GetNodeOrNull<HealthComponent>"),
			"%s 不得继续以泛型方式获取具体生命组件类型。" % real_path
		)
		for needle: String in expectations[source_path]:
			assert_true(source.contains(needle), "%s 必须包含稳定协议 %s。" % [real_path, needle])
