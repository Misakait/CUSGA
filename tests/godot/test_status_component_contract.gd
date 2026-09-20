@tool
extends McpTestSuite

## 状态组件（StatusComponent）生产迁移契约套件。
##
## 套件锁定四件事：状态集合与 Hook 分发改用 GDScript 生产实现、方法/信号协议面与旧 C#
## 逐字一致、两个实体场景完成脚本切换、C# 消费者与垫片保留同样的非 ref 包装边界。
## 运行时“真的能挂上状态、重算属性、结算伤害与推进持续时间”由运行中的游戏经
## game_eval 验证，编辑器侧只锁定形状与枚举同步，避免依赖非 @tool 脚本的编辑器实例化。

## 本批 GDScript 生产脚本与其 uid 旁车。
const STATUS_COMPONENT_GD: String = "res://entities/components/status_component.gd"
const STATUS_COMPONENT_UID_PATH: String = "res://entities/components/status_component.gd.uid"

## 旧 C# 兼容垫片与状态实例基类。
const STATUS_COMPONENT_CS: String = "res://entities/components/StatusComponent.cs"
const STATUS_EFFECT_INSTANCE_CS: String = "res://core/combat/status/StatusEffectInstance.cs"
const SKILL_EXECUTION_CONTEXT_CS: String = "res://core/combat/skills/SkillExecutionModifierContext.cs"

## 跨语言 DTO。
const STATUS_CHANGE_CONTEXT_CS: String = "res://core/combat/status/StatusChangeContext.cs"
const ATTRIBUTE_CHANGE_CONTEXT_CS: String = "res://core/attributes/AttributeChangeContext.cs"

## 本批迁移的 GDScript 生产载体与状态实例基类。
const STATUS_CHANGE_CONTEXT_GD: String = "res://core/combat/status/status_change_context.gd"
const STATUS_CHANGED_EVENT_GD: String = "res://core/combat/status/status_changed_event.gd"
const STATUS_EFFECT_INSTANCE_GD: String = "res://core/combat/status/status_effect_instance.gd"

## 旧 C# 枚举定义路径。
const HOOK_PHASE_CS: String = "res://core/combat/status/StatusHookPhase.cs"
const CHANGE_REASON_CS: String = "res://core/combat/status/StatusChangeReason.cs"
const STACK_POLICY_CS: String = "res://core/combat/status/StackPolicy.cs"
const TICK_TIMING_CS: String = "res://core/combat/status/DurationTickTiming.cs"

## 本批切换脚本引用的实体场景。
const PLAYER_SCENE: String = "res://scenes/player_scenes/player.tscn"
const MONSTER_SCENE: String = "res://scenes/monster_scenes/monster.tscn"

## 需要同步检查的 C# 消费者。
const COMPONENT_LOOKUP_CS: String = "res://entities/components/ComponentLookup.cs"
const ATTRIBUTE_COMPONENT_CS: String = "res://entities/components/AttributeComponent.cs"
const DAMAGE_RECEIVER_CS: String = "res://entities/components/DamageReceiverComponent.cs"
const PLAYER_CS: String = "res://entities/Player.cs"
const MONSTER_CS: String = "res://entities/Monster.cs"

## 迁移期 C# 可选助手：C# 退役后 C# 对照断言自动退场，GDScript 侧断言照跑。
## 说明见 tests/godot/csharp_optional.gd。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")

## 旧 C# 状态组件必须保留的对外协议方法（含非 ref 包装）。
const REQUIRED_PUBLIC_METHODS: Array[String] = [
	"GetActiveStatusesSnapshot",
	"HasStatus",
	"GetStatusOrNull",
	"AddStatus",
	"RemoveStatus",
	"ClearAllStatuses",
	"OnTurnStarted",
	"OnTurnEnded",
	"OnRoundStarted",
	"OnRoundEnded",
	"ProcessBeforeAttributeChange",
	"ProcessAfterAttributeChanged",
	"ProcessBeforeSkillExecution",
	"ProcessAfterSkillExecution",
	"ApplyDamageHitCountModifiers",
	"ApplyDamageEffectSegmentDamageModifiers",
	"ApplyModifyOutgoingDamage",
	"ApplyModifyIncomingDamageBeforeMitigation",
	"ApplyModifyIncomingDamageAfterMitigation",
	"ApplyBeforeHealthDamage",
]

## 旧 C# 状态组件必须保留的聚合非 ref 包装。
const REQUIRED_COMPONENT_WRAPPERS: Array[String] = [
	"ApplyModifyOutgoingDamage",
	"ApplyModifyIncomingDamageBeforeMitigation",
	"ApplyModifyIncomingDamageAfterMitigation",
	"ApplyBeforeHealthDamage",
]

## 旧 C# 状态实例必须保留的单体非 ref 包装。
const REQUIRED_INSTANCE_WRAPPERS: Array[String] = [
	"ApplyModifyDamageHitCount",
	"ApplyModifyDamageEffectSegmentDamage",
	"ApplyModifyOutgoingDamage",
	"ApplyModifyIncomingDamageBeforeMitigation",
	"ApplyModifyIncomingDamageAfterMitigation",
	"ApplyBeforeHealthDamage",
]

## 生产 C# 中不得再出现强类型状态组件边界的位置。
const TYPED_BOUNDARY_PATHS: Array[String] = [
	"res://entities/Player.cs",
	"res://entities/Monster.cs",
	"res://entities/components/ComponentLookup.cs",
	"res://entities/components/DamageReceiverComponent.cs",
	"res://entities/components/AttributeComponent.cs",
	"res://core/combat/skills/CombatSkillData.cs",
	"res://core/combat/effects/ApplyShieldCardEffect.cs",
	"res://core/combat/effects/ApplyStatusCardEffect.cs",
	"res://core/combat/effects/DamageEffect.cs",
	"res://core/combat/buffs/ShieldStatusInstance.cs",
]


## 返回 GodotAI 使用的稳定套件名称。
##
## @return 状态组件契约套件名。
func suite_name() -> String:
	return "status_component_contract"


## 验证生产脚本存在、继承 Node、声明同名信号且不声明 class_name。
func test_production_script_exists_and_extends_node() -> void:
	assert_true(FileAccess.file_exists(STATUS_COMPONENT_GD), "状态组件生产脚本必须存在。")
	var text: String = FileAccess.get_file_as_string(STATUS_COMPONENT_GD)
	assert_true(text.begins_with("extends Node"), "状态组件生产脚本必须直接继承 Node。")
	assert_true(text.contains("signal StatusChanged("), "必须保留同名 StatusChanged 信号。")
	var declares_class_name := false
	for raw_line: String in text.split("\n"):
		if raw_line.strip_edges().begins_with("class_name"):
			declares_class_name = true
	assert_false(declares_class_name, "生产脚本不得声明 class_name，避免与 C# 全局类型冲突。")
	assert_true(text.contains("push_error(\"StatusComponent received null status.\")"), "空状态诊断文本必须与旧 C# 一致。")
	assert_true(text.contains("push_error(\"StatusEffectData has empty Id.\")"), "空 Id 诊断文本必须与旧 C# 一致。")


## 验证生产脚本暴露旧 C# 的全部公开方法与信号协议。
func test_production_script_exposes_legacy_method_surface() -> void:
	var text: String = FileAccess.get_file_as_string(STATUS_COMPONENT_GD)
	for method_name: String in REQUIRED_PUBLIC_METHODS:
		assert_true(
			text.contains("func %s(" % method_name),
			"生产脚本必须提供与旧 C# 同名的方法：%s" % method_name
		)


## 验证 GDScript 枚举常量与旧 C# 枚举逐项同步。
func test_enum_constants_match_legacy_csharp_enums() -> void:
	var text: String = FileAccess.get_file_as_string(STATUS_COMPONENT_GD)

	var hook_members: Array[String] = _read_csharp_enum_members(HOOK_PHASE_CS)
	var policy_members: Array[String] = _read_csharp_enum_members(STACK_POLICY_CS)
	var timing_members: Array[String] = _read_csharp_enum_members(TICK_TIMING_CS)
	var reason_members: Array[String] = _read_csharp_enum_members(CHANGE_REASON_CS)
	# C# 垫片退役后没有枚举名对照源：只保留 GDScript 侧「常量按枚举顺序从 0 递增」的不变量。
	var legacy_available: bool = not (
		hook_members.is_empty()
		or policy_members.is_empty()
		or timing_members.is_empty()
		or reason_members.is_empty()
	)
	var hook_values: Array[int] = _read_const_values(text, "PHASE_")
	if legacy_available:
		assert_eq(hook_members.size(), 16, "旧 C# StatusHookPhase 成员数必须仍是 16。")
		assert_eq(hook_values.size(), hook_members.size(), "阶段常量数量必须与旧 C# 枚举一致。")
	for index: int in range(hook_values.size()):
		assert_eq(
			hook_values[index],
			index,
			"阶段常量必须与旧 C# 枚举顺序一致：%s" % _member_label(hook_members, index)
		)

	var policy_values: Array[int] = _read_const_values(text, "POLICY_")
	if legacy_available:
		assert_eq(policy_values.size(), policy_members.size(), "叠加策略常量数量必须一致。")
	for index: int in range(policy_values.size()):
		assert_eq(policy_values[index], index, "叠加策略常量必须与旧 C# 枚举顺序一致。")

	var timing_values: Array[int] = _read_const_values(text, "TIMING_")
	if legacy_available:
		assert_eq(timing_values.size(), timing_members.size(), "扣减时机常量数量必须一致。")
	for index: int in range(timing_values.size()):
		assert_eq(timing_values[index], index, "扣减时机常量必须与旧 C# 枚举顺序一致。")

	var reason_values: Array[int] = _read_const_values(text, "REASON_")
	if legacy_available:
		assert_true(
			reason_values.size() <= reason_members.size(),
			"变化原因常量不得超出旧 C# 枚举成员数。"
		)
	for index: int in range(reason_values.size()):
		assert_eq(
			reason_values[index],
			index,
			"变化原因常量必须与旧 C# 枚举顺序一致：%s" % _member_label(reason_members, index)
		)


## 验证两个实体场景已把状态组件脚本切换为 GDScript 并保持 uid 一致。
func test_scenes_switched_to_gdscript() -> void:
	var expected_uid: String = FileAccess.get_file_as_string(STATUS_COMPONENT_UID_PATH).strip_edges()
	assert_true(expected_uid.begins_with("uid://"), "状态组件生产脚本必须带 uid 旁车。")

	for scene_path: String in [PLAYER_SCENE, MONSTER_SCENE]:
		var text: String = FileAccess.get_file_as_string(scene_path)
		assert_true(
			text.contains('path="res://entities/components/status_component.gd"'),
			"场景必须引用 GDScript 状态组件：%s" % scene_path
		)
		assert_true(
			text.contains('uid="%s"' % expected_uid),
			"场景必须使用状态组件生产脚本的 uid：%s" % scene_path
		)
		assert_false(
			text.contains("StatusComponent.cs"),
			"场景不得再引用旧 C# 状态组件：%s" % scene_path
		)
		assert_false(
			text.contains("script_class="),
			"场景不得再写 script_class 标记：%s" % scene_path
		)


## 验证 C# 消费者改为按方法协议访问状态组件。
func test_csharp_consumers_use_method_protocol() -> void:
	if not CS_OPTIONAL.present_all(
		[COMPONENT_LOOKUP_CS, DAMAGE_RECEIVER_CS, ATTRIBUTE_COMPONENT_CS, PLAYER_CS, MONSTER_CS]
	):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var lookup: String = FileAccess.get_file_as_string(COMPONENT_LOOKUP_CS)
	assert_true(
		lookup.contains("public static Node GetStatusComponentOrNull"),
		"组件查找必须返回通用 Node，才能同时兼容 C# 与 GDScript 实现。"
	)
	assert_false(lookup.contains("GetNodeOrNull<StatusComponent>"), "组件查找不得再返回强类型状态组件。")

	var receiver: String = FileAccess.get_file_as_string(DAMAGE_RECEIVER_CS)
	assert_true(receiver.contains("FindComponent<Node>(\"StatusComponent\")") or receiver.contains("FindComponent<Node>(payload.Source, \"StatusComponent\")"), "伤害接收组件必须按节点查找状态组件。")
	for method_name: String in REQUIRED_COMPONENT_WRAPPERS:
		assert_true(
			receiver.contains('"%s"' % method_name),
			"伤害接收组件必须通过非 ref 包装调用：%s" % method_name
		)
	assert_false(receiver.contains("defenderStatus?.Process"), "伤害接收组件不得再直接调用 ref Hook。")

	var attribute: String = FileAccess.get_file_as_string(ATTRIBUTE_COMPONENT_CS)
	assert_true(attribute.contains('Connect("StatusChanged"'), "属性组件必须改连 Godot 信号。")
	assert_false(attribute.contains("StatusChangedDetailed"), "属性组件不得再订阅 C# 事件。")
	assert_true(attribute.contains('.Call("ProcessBeforeAttributeChange"'), "属性提交前必须走方法协议。")
	assert_true(attribute.contains('.Call("ProcessAfterAttributeChanged"'), "属性提交后必须走方法协议。")
	assert_true(attribute.contains('.Call("GetActiveStatusesSnapshot")'), "属性修正必须从快照读取状态。")
	assert_false(attribute.contains("_statusComponent.ActiveStatuses"), "属性组件不得再读强类型集合属性。")

	for entity_path: String in [PLAYER_CS, MONSTER_CS]:
		var text: String = FileAccess.get_file_as_string(entity_path)
		assert_true(
			text.contains("public Node Status { get; private set; }"),
			"实体必须把状态组件字段降级为 Node：%s" % entity_path
		)
		assert_true(
			text.contains('GetNode<Node>("%StatusComponent")'),
			"实体必须按通用 Node 获取状态组件：%s" % entity_path
		)


## 验证旧 C# 垫片与状态实例保留同名的非 ref 包装边界。
func test_legacy_shims_keep_wrapper_parity() -> void:
	# 状态实例族已切到 GDScript 生产实现，同一套非 ref 包装必须由新基类原样提供。
	var gd_instance: String = FileAccess.get_file_as_string(STATUS_EFFECT_INSTANCE_GD)
	for method_name: String in REQUIRED_INSTANCE_WRAPPERS:
		assert_true(
			gd_instance.contains("func %s(" % method_name),
			"GDScript 状态实例必须提供单体非 ref 包装：%s" % method_name
		)
	assert_true(
		gd_instance.contains("var AppliedSequence: int = -1"),
		"GDScript 状态实例的应用序号必须可写，状态组件才能保持 Hook 排序语义。"
	)

	# C# 垫片对照：任一垫片退役即整例退场，上面的 GDScript 断言仍照跑。
	if not CS_OPTIONAL.present_all(
		[STATUS_COMPONENT_CS, STATUS_EFFECT_INSTANCE_CS, SKILL_EXECUTION_CONTEXT_CS]
	):
		return
	var shim: String = FileAccess.get_file_as_string(STATUS_COMPONENT_CS)
	assert_true(shim.contains("public partial class StatusComponent : Node"), "旧 C# 状态组件类必须仍然存在。")
	for method_name: String in REQUIRED_COMPONENT_WRAPPERS:
		assert_true(
			shim.contains("public float %s(" % method_name),
			"旧 C# 状态组件必须提供聚合非 ref 包装：%s" % method_name
		)

	var instance: String = FileAccess.get_file_as_string(STATUS_EFFECT_INSTANCE_CS)
	for method_name: String in REQUIRED_INSTANCE_WRAPPERS:
		assert_true(
			instance.contains("public int %s(" % method_name) or instance.contains("public float %s(" % method_name),
			"状态实例必须提供单体非 ref 包装：%s" % method_name
		)
	assert_true(
		instance.contains("public long AppliedSequence { get; set; }"),
		"应用序号必须可写，GDScript 状态组件才能保持 Hook 排序语义。"
	)

	var modifier_context: String = FileAccess.get_file_as_string(SKILL_EXECUTION_CONTEXT_CS)
	assert_true(
		modifier_context.contains("GetStatusIdsMarkedForConsumptionSnapshot"),
		"技能上下文必须提供可跨语言的待消费状态 Id 快照。"
	)


## 验证跨语言 DTO 已降级为 RefCounted，GDScript 才能构造并传递它们。
func test_cross_language_dtos_are_refcounted() -> void:
	# C# 侧对照：垫片退役后自动退场，下面 GDScript 侧的载体断言仍照跑。
	var status_context: String = CS_OPTIONAL.read(STATUS_CHANGE_CONTEXT_CS)
	if not status_context.is_empty():
		assert_true(
			status_context.contains("public sealed partial class StatusChangeContext("),
			"状态变化上下文必须是 Godot 对象，才能由 GDScript 构造。"
		)
		assert_true(status_context.contains(") : RefCounted"), "状态变化上下文必须继承 RefCounted。")

	# 状态变化载体已迁到 GDScript 生产实现：状态组件构造它们，表现层读取它们。
	for path: String in [STATUS_CHANGE_CONTEXT_GD, STATUS_CHANGED_EVENT_GD]:
		assert_true(FileAccess.file_exists(path), "状态变化载体生产脚本必须存在：%s" % path)
		assert_true(
			FileAccess.get_file_as_string(path).begins_with("extends RefCounted"),
			"状态变化载体必须直接继承 RefCounted：%s" % path
		)

	var component_text: String = FileAccess.get_file_as_string(STATUS_COMPONENT_GD)
	for path: String in [STATUS_CHANGE_CONTEXT_GD, STATUS_CHANGED_EVENT_GD]:
		assert_true(
			component_text.contains(path),
			"状态组件必须构造 GDScript 状态变化载体：%s" % path
		)
	assert_false(
		component_text.contains("StatusChangeContext.cs"),
		"状态组件不得再构造旧 C# 状态变化上下文。"
	)

	var attribute_context: String = CS_OPTIONAL.read(ATTRIBUTE_CHANGE_CONTEXT_CS)
	if not attribute_context.is_empty():
		assert_true(
			attribute_context.contains("public sealed partial class AttributeChangeContext("),
			"属性变化上下文必须是 Godot 对象，才能跨语言传递。"
		)
		assert_true(attribute_context.contains(") : RefCounted"), "属性变化上下文必须继承 RefCounted。")


## 验证生产 C# 中不再残留强类型状态组件边界。
func test_production_csharp_has_no_typed_status_component_boundary() -> void:
	if not CS_OPTIONAL.any_present(TYPED_BOUNDARY_PATHS):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	for path: String in TYPED_BOUNDARY_PATHS:
		if not CS_OPTIONAL.present(path):
			continue
		var text: String = FileAccess.get_file_as_string(path)
		for marker: String in ["<StatusComponent>", "StatusComponent statusComponent", "StatusComponent _statusComponent"]:
			assert_false(
				text.contains(marker),
				"生产 C# 不得再持有强类型状态组件边界（%s）：%s" % [path, marker]
			)


## 验证回合推进保留旧 C# 的非短路 |= 语义（拥有者回合扣减必须无条件执行）。
func test_turn_tick_keeps_non_short_circuit_semantics() -> void:
	var text: String = FileAccess.get_file_as_string(STATUS_COMPONENT_GD)
	assert_true(
		text.contains("var owner_changed: bool = bool(status.call(\"TickOwnerTurnDuration\", timing))"),
		"拥有者回合扣减必须独立求值，不能被短路跳过。"
	)
	assert_true(
		text.contains("changed = changed or owner_changed"),
		"全局与拥有者回合扣减结果必须按 |= 语义合并。"
	)
	assert_true(text.contains("_is_status_owner_turn("), "必须保留拥有者回合判定。")
	assert_true(text.contains("_resolve_expiration("), "必须保留持续时间归零后的过期结算。")
	assert_true(text.contains("_apply_stack_policy("), "必须保留叠加策略分发。")
	assert_true(text.contains("_consume_marked_skill_execution_statuses("), "必须保留限次状态消费。")
	assert_true(text.contains("sort_custom("), "Hook 分发必须按优先级与应用序号排序。")


## 取枚举第 index 个成员名做断言描述；C# 垫片退役后回退为下标本身。
##
## @param members 枚举成员名数组，允许为空。
## @param index 成员下标。
## @return 描述用字符串。
func _member_label(members: Array[String], index: int) -> String:
	if index < members.size():
		return members[index]
	return str(index)


## 读取旧 C# 枚举的成员名（按声明顺序）。
##
## @param path 旧 C# 枚举脚本的 res:// 路径。
## @return 枚举成员名数组；无法识别时返回空数组。
func _read_csharp_enum_members(path: String) -> Array[String]:
	var members: Array[String] = []
	var inside_enum := false

	if not FileAccess.file_exists(path):
		return members
	for raw_line: String in FileAccess.get_file_as_string(path).split("\n"):
		var line: String = raw_line.strip_edges()

		if not inside_enum:
			# 旧 C# 枚举把 { 写在下一行，因此只按声明行进入枚举体，再跳过花括号行。
			inside_enum = line.begins_with("public enum")
			continue

		if line == "{":
			continue

		if line.begins_with("}"):
			break

		if line.is_empty() or line.begins_with("//"):
			continue

		members.append(line.trim_suffix(","))

	return members


## 读取 GDScript 生产脚本里以指定前缀开头的整数常量值（按声明顺序）。
##
## @param text GDScript 生产脚本全文。
## @param prefix 常量名前缀，例如 "PHASE_"。
## @return 常量值数组。
func _read_const_values(text: String, prefix: String) -> Array[int]:
	var values: Array[int] = []
	var needle := "const %s" % prefix

	for raw_line: String in text.split("\n"):
		var line: String = raw_line.strip_edges()

		if not line.begins_with(needle):
			continue

		var value_text := line.split("=")[-1].strip_edges()
		values.append(int(value_text))

	return values
