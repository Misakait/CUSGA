@tool
extends McpTestSuite

## AttributeComponent 生产迁移契约套件。
##
## 套件锁定五件事：属性域类型改为 GDScript 纯数据载体且字段逐字等价旧 C#、玩家与怪物两个
## 场景完成脚本切换、状态实例的属性修饰走跨语言字典出口、C# 状态钩子降级为 Variant 上下文、
## 旧 C# 垫片保留完整实现作为兼容输入与对照（垫片退役后该部分经 CS_OPTIONAL 自动退场）。
## “属性能否真的初始化、状态能否真的改数值、上限能否同步”由运行中的游戏经 game_eval 验证。
## 本批追加属性域类型族：Attributes / AttributeModifier / AttributeRecalculateRequest 等旧 C# 类型
## 都有同名 GDScript 载体，枚举顺序与消费方常量由文本对照锁定，条目与请求的字段协议由运行时构造锁定。

## 本批 GDScript 生产脚本。
const COMPONENT_GD: String = "res://entities/components/attribute_component.gd"
const COMPONENT_GD_UID: String = "res://entities/components/attribute_component.gd.uid"
const ATTRIBUTE_VALUE_GD: String = "res://core/attributes/attribute_value.gd"
const CHANGE_CONTEXT_GD: String = "res://core/attributes/attribute_change_context.gd"
const CHANGED_EVENT_GD: String = "res://core/attributes/attribute_changed_event.gd"

## 属性域类型族（本批新增）GDScript 载体。
const ATTRIBUTES_GD: String = "res://core/attributes/attributes.gd"
const MODIFIER_GD: String = "res://core/attributes/attribute_modifier.gd"
const RECALCULATE_SCOPE_GD: String = "res://core/attributes/attribute_recalculate_scope.gd"
const CHANGE_DIRECTION_GD: String = "res://core/attributes/attribute_change_direction.gd"
const CHANGE_REASON_GD: String = "res://core/attributes/attribute_change_reason.gd"
const RECALCULATE_REQUEST_GD: String = "res://core/attributes/attribute_recalculate_request.gd"
const READ_ONLY_ATTRIBUTE_GD: String = "res://core/attributes/i_read_only_attribute.gd"

## 与上面逐项对应的旧 C# 类型文件。
const MODIFIER_CS: String = "res://core/attributes/AttributeModifier.cs"
const RECALCULATE_SCOPE_CS: String = "res://core/attributes/AttributeRecalculateScope.cs"
const CHANGE_DIRECTION_CS: String = "res://core/attributes/AttributeChangeDirection.cs"
const CHANGE_REASON_CS: String = "res://core/attributes/AttributeChangeReason.cs"
const RECALCULATE_REQUEST_CS: String = "res://core/attributes/AttributeRecalculateRequest.cs"
const READ_ONLY_ATTRIBUTE_CS: String = "res://core/attributes/IReadOnlyAttribute.cs"

## 属性域类型族常量逐值对应表：[枚举脚本, 枚举名, 常量所在脚本, 常量前缀, 枚举成员, 枚举值]。
const TYPE_FAMILY_ROWS: Array = [
	[MODIFIER_GD, "AttributeModifierMode", COMPONENT_GD, "MODIFIER_MODE_", "FlatAdd", 0],
	[MODIFIER_GD, "AttributeModifierMode", COMPONENT_GD, "MODIFIER_MODE_", "PercentAdd", 1],
	[MODIFIER_GD, "AttributeModifierMode", COMPONENT_GD, "MODIFIER_MODE_", "PercentMul", 2],
	[CHANGE_REASON_GD, "AttributeChangeReason", COMPONENT_GD, "REASON_", "Initialization", 0],
	[CHANGE_REASON_GD, "AttributeChangeReason", COMPONENT_GD, "REASON_", "AllocatedPointChanged", 1],
	[CHANGE_REASON_GD, "AttributeChangeReason", COMPONENT_GD, "REASON_", "PermanentBonusChanged", 2],
	[CHANGE_REASON_GD, "AttributeChangeReason", COMPONENT_GD, "REASON_", "BaseValueChanged", 3],
	[CHANGE_REASON_GD, "AttributeChangeReason", COMPONENT_GD, "REASON_", "StatusChanged", 4],
	[CHANGE_REASON_GD, "AttributeChangeReason", COMPONENT_GD, "REASON_", "ForcedRecalculation", 5],
	[RECALCULATE_SCOPE_GD, "AttributeRecalculateScope", COMPONENT_GD, "SCOPE_", "SingleAttribute", 0],
	[RECALCULATE_SCOPE_GD, "AttributeRecalculateScope", COMPONENT_GD, "SCOPE_", "AllAttributes", 1],
	[CHANGE_DIRECTION_GD, "AttributeChangeDirection", CHANGE_CONTEXT_GD, "DIRECTION_", "Any", 0],
	[CHANGE_DIRECTION_GD, "AttributeChangeDirection", CHANGE_CONTEXT_GD, "DIRECTION_", "Increase", 1],
	[CHANGE_DIRECTION_GD, "AttributeChangeDirection", CHANGE_CONTEXT_GD, "DIRECTION_", "Decrease", 2],
]

## 旧 C# 垫片与共享协议文件。
const COMPONENT_CS: String = "res://entities/components/AttributeComponent.cs"
const ATTRIBUTES_CS: String = "res://core/attributes/Attributes.cs"
const STATUS_INSTANCE_CS: String = "res://core/combat/status/StatusEffectInstance.cs"
const MODIFIER_INSTANCE_CS: String = "res://core/combat/buffs/AttributeModifierStatusInstance.cs"
const MODIFIER_PROTOCOL_CS: String = "res://core/combat/status/AttributeModifierDataProtocol.cs"
## C# 可选助手：C# 退役后没有对照源文，相关用例记跳过而不是假通过或 0 断言失败。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")

## 两个必须切换脚本的属性组件场景。
const PLAYER_SCENE: String = "res://scenes/player_scenes/player.tscn"
const MONSTER_SCENE: String = "res://scenes/monster_scenes/monster.tscn"
const MAIN_SCENE: String = "res://scenes/Main.tscn"

## 15 条属性必须逐字一致的展示名与 GDScript 常量后缀。
const ATTRIBUTE_ROWS: Array = [
	[0, "PhysAtk", "PHYS_ATK", "物理攻击"],
	[1, "PhysDef", "PHYS_DEF", "物理抗性"],
	[2, "MagPower", "MAG_POWER", "法术强度"],
	[3, "MagResist", "MAG_RESIST", "法术抗性"],
	[4, "Speed", "SPEED", "速度"],
	[5, "MaxHealth", "MAX_HEALTH", "生命上限"],
	[6, "MaxEnergy", "MAX_ENERGY", "能量上限"],
	[7, "FixedPhysPenetration", "FIXED_PHYS_PENETRATION", "固定物理穿透"],
	[8, "PhysPenetrationRate", "PHYS_PENETRATION_RATE", "物理穿透率"],
	[9, "FixedMagicPenetration", "FIXED_MAGIC_PENETRATION", "固定法术穿透"],
	[10, "MagicPenetrationRate", "MAGIC_PENETRATION_RATE", "法术穿透率"],
	[11, "CritRate", "CRIT_RATE", "暴击率"],
	[12, "CritDamage", "CRIT_DAMAGE", "暴击伤害"],
	[13, "EvasionRate", "EVASION_RATE", "闪避率"],
	[14, "LifestealRate", "LIFESTEAL_RATE", "吸血率"],
]

## 生产脚本必须保留的公开方法面。
const PRODUCTION_METHODS: Array[String] = [
	"func _ready() -> void:",
	"func _exit_tree() -> void:",
	"func InitializeWithData(data: Resource) -> void:",
	"func ReadStat(data: Resource, property_name: String, fallback: float = 0.0) -> float:",
	"func SetAttribute(type: int, display_name: String, base_value: float, growth: float) -> void:",
	"func GetAttribute(type: int) -> RefCounted:",
	"func GetAllAttributes() -> Array:",
	"func GetRawValue(type: int) -> float:",
	"func GetEffectiveValue(type: int) -> float:",
	"func EarnPoints(amount: int) -> void:",
	"func TryAllocatePoint(target_attribute_type: int, amount: int) -> bool:",
	"func AddPermanentBonus(type: int, amount: float, source: Node = null) -> bool:",
	"func RemovePermanentBonus(type: int, amount: float, source: Node = null) -> bool:",
	"func ForceRecalculateAll(source: Node = null) -> void:",
	"func HandleStatusChangedSignal(change_event: Variant) -> void:",
	"func RequestRecalculateAttribute(",
	"func RequestRecalculateAll(",
	"func RecalculateAllDirect(",
	"func CalculateUnclampedEffectiveValue(type: int) -> float:",
	"func SynchronizeVitalMaximum(type: int, value: float, reason: int) -> void:",
	"func ClampAttributeValue(type: int, value: float) -> float:",
	"func NotifyAvailablePointsChanged() -> void:",
	"func NotifyAttributeChanged(context: RefCounted) -> void:",
]

## 必须逐字保留的日志与告警文本。
const LOG_TEXTS: Array[String] = [
	"Cannot earn non-positive attribute points.",
	"Cannot allocate non-positive attribute points.",
	"没有足够的技能点！",
	"Unhandled attribute modifier mode: %s",
	"Invalid attribute value calculated for %s on %s: %s",
	"AttributeComponent detected a possible infinite attribute recalculation loop on %s.",
	"AttributeComponent initialized with null starting stats Resource.",
]


## 返回 GodotAI 使用的稳定套件名称。
##
## @return 属性组件契约套件名。
func suite_name() -> String:
	return "attribute_component_contract"


## 验证三个数据脚本与生产脚本的形状。
##
## @return 无返回值。
func test_production_script_shape() -> void:
	for path: String in [
		COMPONENT_GD,
		ATTRIBUTE_VALUE_GD,
		CHANGE_CONTEXT_GD,
		CHANGED_EVENT_GD,
		COMPONENT_GD_UID,
	]:
		assert_true(FileAccess.file_exists(path), "生产文件必须存在：%s" % path)

	var component: String = FileAccess.get_file_as_string(COMPONENT_GD)
	assert_true(component.begins_with("extends Node"), "属性组件必须直接继承 Node。")
	assert_false(_declares_class_name(component), "属性组件不得声明 class_name，避免与兼容垫片重名。")
	assert_false(component.contains("TODO"), "生产脚本不得保留 TODO 占位。")
	assert_true(component.contains("signal AttributeChanged(change_event)"), "必须保留 AttributeChanged 信号。")
	assert_true(
		component.contains("signal AvailablePointsChanged(available_points)"),
		"必须保留 AvailablePointsChanged 信号。"
	)
	# 回归：路径常量必须是 NodePath。get_node_or_null() 只接受 NodePath，传 StringName 会在运行时
	# 触发 “Cannot pass a value of type StringName as NodePath” 的 Parser Error。
	assert_false(component.contains("_PATH: StringName = "), "节点路径常量不得声明为 StringName。")
	assert_false(component.contains("_NAME: StringName = ^"), "节点路径常量不得声明为 StringName。")
	assert_true(
		component.contains("const STATUS_COMPONENT_NAME: NodePath = ^\"StatusComponent\""),
		"状态组件查找必须用 NodePath 字面量。"
	)

	for path: String in [ATTRIBUTE_VALUE_GD, CHANGE_CONTEXT_GD, CHANGED_EVENT_GD]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_true(text.begins_with("extends RefCounted"), "属性域数据脚本必须继承 RefCounted：%s" % path)
		assert_false(_declares_class_name(text), "属性域数据脚本不得声明 class_name：%s" % path)

	for literal: String in [
		"var RawValue: float:",
		"func Initialize(",
		"func AddPoint(amount: int) -> void:",
		"func AddBonus(amount: float) -> void:",
		"func RemoveBonus(amount: float) -> void:",
		"func SetBaseValue(value: float) -> void:",
	]:
		assert_true(
			FileAccess.get_file_as_string(ATTRIBUTE_VALUE_GD).contains(literal),
			"属性值脚本必须保留字段/方法：%s" % literal
		)

	var uid_text: String = FileAccess.get_file_as_string(COMPONENT_GD_UID).strip_edges()
	assert_true(uid_text.begins_with("uid://"), "属性组件必须带 uid 旁车。")


## 验证 15 条属性枚举的顺序、名字与旧 C# AttributeType 逐项一致。
##
## @return 无返回值。
func test_attribute_enum_matches_legacy() -> void:
	## C# 垫片仍是本用例的对照对象；C# 退役后整例跳过（GDScript 侧由同套件其余用例覆盖）。
	if not CS_OPTIONAL.present(ATTRIBUTES_CS):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var component: String = FileAccess.get_file_as_string(COMPONENT_GD)
	var legacy: String = FileAccess.get_file_as_string(ATTRIBUTES_CS)
	var component_legacy: String = FileAccess.get_file_as_string(COMPONENT_CS)

	var enum_names: Array[String] = _read_legacy_attribute_type_order(legacy)
	assert_eq(enum_names.size(), 15, "旧 C# AttributeType 必须仍是 15 项。")

	for row: Array in ATTRIBUTE_ROWS:
		var value: int = int(row[0])
		var enum_name: String = str(row[1])
		var constant: String = str(row[2])
		var display_name: String = str(row[3])

		assert_eq(enum_names[value], enum_name, "枚举顺序必须与旧 C# 一致：%s" % enum_name)
		assert_true(
			component.contains("const ATTRIBUTE_%s: int = %d" % [constant, value]),
			"GDScript 必须保留同值常量：%s = %d" % [constant, value]
		)
		assert_true(
			component.contains("\"%s\"," % enum_name),
			"ATTRIBUTE_NAMES 必须保留旧枚举名：%s" % enum_name
		)
		assert_true(
			component.contains("\"%s\"" % display_name),
			"必须保留旧展示名：%s" % display_name
		)
		assert_true(
			component_legacy.contains("\"%s\"" % display_name),
			"旧 C# 垫片必须保留同一展示名：%s" % display_name
		)

	# 枚举名表下标必须等于枚举值。
	assert_true(component.contains("const ATTRIBUTE_NAMES: Array[String] = ["), "必须保留枚举名表。")


## 验证默认值、成长值与旧 C# InitializeWithData 逐行一致。
##
## @return 无返回值。
func test_default_values_match_legacy() -> void:
	## C# 垫片仍是本用例的对照对象；C# 退役后整例跳过。
	if not CS_OPTIONAL.present(COMPONENT_CS):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var component: String = FileAccess.get_file_as_string(COMPONENT_GD)
	var legacy: String = FileAccess.get_file_as_string(COMPONENT_CS)

	for literal: String in [
		"ReadStat(data, \"BasePhysAtk\", 100.0)",
		"ReadStat(data, \"PhysAtkGrowth\", 25.0)",
		"ReadStat(data, \"BasePhysDef\", 100.0)",
		"ReadStat(data, \"PhysDefGrowth\", 20.0)",
		"ReadStat(data, \"BaseMagPower\", 100.0)",
		"ReadStat(data, \"MagPowerGrowth\", 30.0)",
		"ReadStat(data, \"BaseMagResist\", 100.0)",
		"ReadStat(data, \"MagResistGrowth\", 20.0)",
		"ReadStat(data, \"BaseSpeed\", 100.0)",
		"ReadStat(data, \"SpeedGrowth\", 5.0)",
		"ReadStat(data, \"BaseMaxHealth\", 1000.0)",
		"ReadStat(data, \"BaseMaxEnergy\", 100.0)",
		"ReadStat(data, \"BaseCritDamage\", 1.5)",
	]:
		assert_true(component.contains(literal), "GDScript 必须保留旧默认值：%s" % literal)

	for literal: String in [
		"ReadStat(data, \"BasePhysAtk\", 100f)",
		"ReadStat(data, \"PhysAtkGrowth\", 25f)",
		"ReadStat(data, \"MagPowerGrowth\", 30f)",
		"ReadStat(data, \"SpeedGrowth\", 5f)",
		"ReadStat(data, \"BaseMaxHealth\", 1000f)",
		"ReadStat(data, \"BaseMaxEnergy\", 100f)",
		"ReadStat(data, \"BaseCritDamage\", 1.5f)",
	]:
		assert_true(legacy.contains(literal), "旧 C# 垫片必须保留旧默认值：%s" % literal)

	assert_true(component.contains("print(\"InitializeWithData\", data)"), "必须保留初始化打印。")
	assert_true(legacy.contains("GD.Print(\"InitializeWithData\", data);"), "旧 C# 必须保留同一打印。")
	assert_true(
		component.contains("REASON_INITIALIZATION,\n\t\tfalse,\n\t\tfalse\n\t)"),
		"初始化必须不拦截且不发事件。"
	)
	assert_true(legacy.contains("allowInterception: false,"), "旧 C# 初始化必须不拦截。")
	assert_true(legacy.contains("emitEvents: false"), "旧 C# 初始化必须不发事件。")


## 验证钳制规则、重算循环上限与关键日志文本与旧 C# 一致。
##
## @return 无返回值。
func test_clamp_and_logs_match_legacy() -> void:
	## C# 垫片仍是本用例的对照对象；C# 退役后整例跳过。
	if not CS_OPTIONAL.present(COMPONENT_CS):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var component: String = FileAccess.get_file_as_string(COMPONENT_GD)
	var legacy: String = FileAccess.get_file_as_string(COMPONENT_CS)

	assert_true(
		component.contains("const MAX_RECALCULATE_REQUESTS_PER_FLUSH: int = 64"),
		"必须保留单次刷新上限 64。"
	)
	assert_true(legacy.contains("MaxRecalculateRequestsPerFlush = 64"), "旧 C# 上限必须仍是 64。")

	for literal: String in LOG_TEXTS:
		assert_true(component.contains(literal), "生产脚本必须保留文本：%s" % literal)

	for literal: String in [
		"Cannot earn non-positive attribute points.",
		"Cannot allocate non-positive attribute points.",
		"没有足够的技能点！",
		"detected a possible infinite attribute recalculation loop on",
	]:
		assert_true(legacy.contains(literal), "旧 C# 垫片必须保留文本：%s" % literal)

	# 钳制规则：速度/生命/能量/暴击伤害下限，穿透/攻防下限，五个比率钳到 [0,1]。
	assert_true(component.contains("func ClampAttributeValue(type: int, value: float) -> float:"), "必须保留钳制入口。")
	# 速度、生命/能量上限、暴击伤害共三处返回 maxf(1.0, value)；生命与能量共用一条分支。
	assert_eq(_count_occurrences(component, "return maxf(1.0, value)"), 3, "三条下限 1 规则必须齐全。")
	assert_eq(_count_occurrences(component, "return maxf(0.0, value)"), 6, "六条下限 0 规则必须齐全。")
	assert_eq(_count_occurrences(component, "return clampf(value, 0.0, 1.0)"), 5, "五条比率钳制规则必须齐全。")
	assert_eq(_count_occurrences(component, "return value\n"), 1, "未知属性类型必须原样返回。")

	assert_true(legacy.contains("AttributeType.Speed => Mathf.Max(1f, value),"), "旧 C# 速度下限必须保留。")
	assert_true(legacy.contains("AttributeType.CritDamage => Mathf.Max(1f, value),"), "旧 C# 暴击伤害下限必须保留。")
	assert_true(legacy.contains("Mathf.Clamp(value, 0f, 1f)"), "旧 C# 比率钳制必须保留。")
	assert_true(component.contains("func _round_to_int(value: float) -> int:"), "必须保留银行家舍入，等价 Mathf.RoundToInt。")


## 验证公开方法面与旧 C# 逐字对齐。
##
## @return 无返回值。
func test_public_surface_matches_legacy() -> void:
	## C# 垫片仍是本用例的对照对象；C# 退役后整例跳过。
	if not CS_OPTIONAL.present(COMPONENT_CS):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var component: String = FileAccess.get_file_as_string(COMPONENT_GD)
	var legacy: String = FileAccess.get_file_as_string(COMPONENT_CS)

	for literal: String in PRODUCTION_METHODS:
		assert_true(component.contains(literal), "生产脚本必须保留方法：%s" % literal)

	for literal: String in [
		"public override void _Ready()",
		"public override void _ExitTree()",
		"public void InitializeWithData(Resource data)",
		"public IReadOnlyAttribute GetAttribute(AttributeType type)",
		"public IEnumerable<IReadOnlyAttribute> GetAllAttributes()",
		"public float GetRawValue(AttributeType type)",
		"public float GetEffectiveValue(AttributeType type)",
		"public void EarnPoints(int amount)",
		"public bool TryAllocatePoint(AttributeType targetAttributeType, int amount)",
		"public bool AddPermanentBonus(",
		"public bool RemovePermanentBonus(",
		"public void ForceRecalculateAll(Node source = null)",
		"private void RecalculateEffectiveAttribute(",
		"private float CalculateUnclampedEffectiveValue(AttributeType type)",
		"private static float ClampAttributeValue(AttributeType type, float value)",
		"private void NotifyAvailablePointsChanged()",
		"private void NotifyAttributeChanged(AttributeChangeContext context)",
	]:
		assert_true(legacy.contains(literal), "旧 C# 垫片必须保留方法：%s" % literal)

	# 结算顺序必须逐行等价：候选值 → Before 拦截 → 取消 → 二次钳制 → 近似短路 → 事件 → After。
	assert_true(component.contains("\"ProcessBeforeAttributeChange\""), "必须保留 Before 钩子调用。")
	assert_true(component.contains("\"ProcessAfterAttributeChanged\""), "必须保留 After 钩子调用。")
	assert_true(legacy.contains("_statusComponent?.Call(\"ProcessBeforeAttributeChange\", context);"), "旧 C# 必须保留同一 Before 钩子。")
	assert_true(component.contains("if context.IsCancelled:"), "必须保留取消短路。")
	assert_true(component.contains("if is_equal_approx(old_value, final_value):"), "必须保留近似相等短路。")
	assert_true(component.contains("(base_value + flat_add) * (1.0 + percent_add) * percent_mul"), "必须保留旧公式。")
	assert_true(legacy.contains("(baseValue + flatAdd) * (1f + percentAdd) * percentMul"), "旧 C# 公式必须不变。")


## 验证状态实例的属性修饰走跨语言字典出口，且旧 C# 读取路径未被掏空。
##
## @return 无返回值。
func test_status_modifier_bridge_boundary() -> void:
	## C# 垫片仍是本用例的对照对象；C# 退役后整例跳过。
	if not CS_OPTIONAL.present(STATUS_INSTANCE_CS):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var component: String = FileAccess.get_file_as_string(COMPONENT_GD)
	var base_status: String = FileAccess.get_file_as_string(STATUS_INSTANCE_CS)
	var protocol: String = FileAccess.get_file_as_string(MODIFIER_PROTOCOL_CS)
	var modifier_instance: String = FileAccess.get_file_as_string(MODIFIER_INSTANCE_CS)

	assert_true(
		component.contains("const STATUS_MODIFIERS_DATA_METHOD: StringName = &\"GetAttributeModifiersData\""),
		"GDScript 必须声明跨语言出口方法名。"
	)
	assert_true(
		component.contains("_status_component.call(\"GetActiveStatusesSnapshot\")"),
		"必须按方法协议读取激活状态快照。"
	)
	assert_true(component.contains("func _read_attribute_modifiers(status_variant: Variant) -> Array:"), "必须保留修饰读取入口。")

	assert_true(
		base_status.contains("public virtual Godot.Collections.Array GetAttributeModifiersData()"),
		"旧 C# 状态基类必须提供跨语言修饰出口，避免 GDScript 属性组件漏算加成。"
	)
	assert_true(
		base_status.contains("result.Add(AttributeModifierDataProtocol.ToDictionary(modifier));"),
		"跨语言出口必须由协议统一写出字典。"
	)
	assert_true(
		protocol.contains("public static Godot.Collections.Dictionary ToDictionary(AttributeModifier modifier)"),
		"协议必须提供唯一的字典写出入口。"
	)
	for key: String in ["\"Type\"", "\"Mode\"", "\"ValuePerStack\"", "\"Stacks\"", "\"SourceId\""]:
		assert_true(protocol.contains(key), "字典字段必须与旧 C# 结构一致：%s" % key)

	assert_true(
		modifier_instance.contains("public override IEnumerable<AttributeModifier> GetAttributeModifiers()"),
		"旧 C# 属性修饰状态实例必须保留强类型实现。"
	)
	assert_true(
		modifier_instance.contains("AttributeModifierDataProtocol.TryRead(modifier)"),
		"旧 C# 实例必须仍走跨语言字段协议读取条目。"
	)


## 验证玩家与怪物场景完成属性组件脚本切换。
##
## @return 无返回值。
func test_scene_switches_to_gdscript_component() -> void:
	var component_uid: String = FileAccess.get_file_as_string(COMPONENT_GD_UID).strip_edges()
	var player_scene: String = FileAccess.get_file_as_string(PLAYER_SCENE)
	var monster_scene: String = FileAccess.get_file_as_string(MONSTER_SCENE)

	assert_true(
		player_scene.contains(
			"[ext_resource type=\"Script\" uid=\"%s\" path=\"res://entities/components/attribute_component.gd\" id=\"5_k3sny\"]"
			% component_uid
		),
		"玩家场景必须复用原 ext_resource id 切到 GDScript 属性组件。"
	)
	assert_true(
		monster_scene.contains(
			"[ext_resource type=\"Script\" uid=\"%s\" path=\"res://entities/components/attribute_component.gd\" id=\"2_twjs6\"]"
			% component_uid
		),
		"怪物场景必须复用原 ext_resource id 切到 GDScript 属性组件。"
	)
	assert_true(
		monster_scene.contains("metadata/_custom_type_script = \"%s\"" % component_uid),
		"怪物场景的 custom_type_script 必须同步到新 uid。"
	)
	assert_false(player_scene.contains("AttributeComponent.cs"), "玩家场景不得再引用旧 C# 属性组件。")
	assert_false(monster_scene.contains("AttributeComponent.cs"), "怪物场景不得再引用旧 C# 属性组件。")
	assert_true(monster_scene.contains("script = ExtResource(\"2_twjs6\")"), "怪物节点必须仍绑定原 ext_resource id。")


## 验证资产侧不再引用旧 C# 属性组件脚本。
##
## @return 无返回值。
func test_no_asset_references_legacy_component_script() -> void:
	var offenders: Array[String] = []

	for root: String in ["res://scenes", "res://resources"]:
		offenders.append_array(_grep_asset_references(root, "AttributeComponent.cs"))

	assert_eq(offenders.size(), 0, "场景与资源不得引用旧 C# 属性组件：%s" % str(offenders))


## 验证 C# 状态实例的属性变化钩子已放宽为 Variant 上下文。
##
## 属性组件迁移到 GDScript 后会传入 GDScript 上下文载体；若钩子仍声明强类型
## AttributeChangeContext，Variant 调用会直接运行时报错，因此这里锁定降级结果。
##
## @return 无返回值。
func test_status_attribute_hooks_accept_variant_context() -> void:
	## 本用例整体只对照 C# 源文；C# 退役后记跳过。
	if not CS_OPTIONAL.present(STATUS_INSTANCE_CS):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var base_status: String = FileAccess.get_file_as_string(STATUS_INSTANCE_CS)
	var trigger: String = CS_OPTIONAL.read("res://core/combat/status/AttributeChangeTriggerStatusInstance.cs")
	var guard: String = CS_OPTIONAL.read("res://core/combat/status/AttributeChangeGuardStatusInstance.cs")
	var component_shim: String = CS_OPTIONAL.read(
		"res://entities/components/StatusComponent.cs"
	)

	assert_true(base_status.contains("public virtual void OnBeforeAttributeChange(Variant context) { }"), "Before 钩子必须放宽为 Variant。")
	assert_true(base_status.contains("public virtual void OnAfterAttributeChanged(Variant context) { }"), "After 钩子必须放宽为 Variant。")
	assert_false(base_status.contains("OnAfterAttributeChanged(AttributeChangeContext context)"), "After 钩子不得再声明强类型上下文。")

	assert_true(trigger.contains("public override void OnAfterAttributeChanged(Variant context)"), "触发状态实例必须同步签名。")
	assert_true(trigger.contains("contextObject.Get(\"Type\").AsInt32()"), "触发状态实例必须按字段协议读取属性类型。")
	assert_true(trigger.contains("\"MatchesDirection\""), "触发状态实例必须按方法协议判定方向。")
	assert_true(trigger.contains("contextObject.Get(\"Source\").AsGodotObject() as Node"), "触发状态实例必须按字段协议读取来源。")

	assert_true(guard.contains("public override void OnBeforeAttributeChange(Variant context)"), "防护状态实例必须同步签名。")
	assert_true(guard.contains("contextObject.Call(\"Cancel\")"), "防护状态实例必须按方法协议取消变化。")
	assert_true(guard.contains("contextObject.Set(\"NewValue\", newValue)"), "防护状态实例必须按字段协议写回新值。")
	assert_true(guard.contains("float)contextObject.Get(\"OldValue\").AsDouble()"), "防护状态实例必须按字段协议读取旧值。")

	# 旧 C# 状态组件的调用点保持不变：C# 上下文可隐式转成 Variant，无需改动调用方。
	assert_true(component_shim.contains("status.OnBeforeAttributeChange(context);"), "旧 C# 状态组件调用点必须保留。")
	assert_true(component_shim.contains("status.OnAfterAttributeChanged(context);"), "旧 C# 状态组件调用点必须保留。")


## 验证场景根脚本与存活 C# 消费者已把属性组件降级为 Node。
##
## @return 无返回值。
func test_live_consumers_downgraded_to_node() -> void:
	## C# 源文对照：C# 退役后 read() 返回空串，C# 侧断言按条件收起，下面的 GDScript 场景断言照跑。
	var monster: String = CS_OPTIONAL.read("res://entities/Monster.cs")
	var player: String = CS_OPTIONAL.read("res://entities/Player.cs")

	if not monster.is_empty():
		assert_true(monster.contains("public Node Attributes { get; private set; }"), "怪物根脚本必须持有 Node 属性组件。")
		assert_true(monster.contains("Attributes = GetNode<Node>(\"Components/AttributeComponent\");"), "怪物必须按节点名解析属性组件。")
		assert_true(monster.contains("Attributes.Call("), "怪物必须走 InitializeWithData 方法协议。")
		assert_true(monster.contains("\"InitializeWithData\","), "怪物必须调用同一初始化方法名。")
		assert_false(monster.contains("<AttributeComponent>"), "怪物根脚本不得再强类型化属性组件。")

	if not player.is_empty():
		assert_true(player.contains("public Node Attributes { get; private set; }"), "玩家根脚本必须持有 Node 属性组件。")
		assert_true(player.contains("Attributes = GetNode<Node>(\"Components/AttributeComponent\");"), "玩家必须按节点名解析属性组件。")
		assert_false(player.contains("<AttributeComponent>"), "玩家根脚本不得再强类型化属性组件。")

	# 兜底：怪物与玩家的根脚本都已是 GDScript，属性组件在运行期只能用 GDScript 脚本。
	# 怪物根脚本在 Monster 生产切换批次中改为 GDScript，这里锁定新的生产路径。
	assert_false(
		FileAccess.get_file_as_string(MONSTER_SCENE).contains("res://entities/Monster.cs"),
		"怪物场景根脚本必须已切换到 GDScript 生产实现。"
	)
	assert_true(
		FileAccess.get_file_as_string(MONSTER_SCENE).contains("res://entities/monster.gd"),
		"怪物场景根脚本必须引用 GDScript 生产实现。"
	)


## 验证主场景不再覆盖玩家根脚本为旧 C# 实现。
##
## @return 无返回值。
func test_main_scene_drops_legacy_player_override() -> void:
	var main_scene: String = FileAccess.get_file_as_string(MAIN_SCENE)

	assert_false(main_scene.contains("res://entities/Player.cs"), "主场景不得再引用旧 C# 玩家脚本。")
	assert_false(main_scene.contains("14_v0vrg"), "旧 C# 玩家脚本的 ext_resource id 必须一并移除。")
	assert_true(
		main_scene.contains("instance=ExtResource(\"8_jlsqs\")"),
		"主场景必须仍实例化玩家场景，由玩家场景自带 GDScript 根脚本。"
	)


## 验证旧 C# 属性组件垫片仍保留完整实现。
##
## @return 无返回值。
func test_legacy_shim_retained() -> void:
	## C# 垫片仍是本用例的对照对象；C# 退役后整例跳过。
	if not CS_OPTIONAL.present(COMPONENT_CS):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var legacy: String = FileAccess.get_file_as_string(COMPONENT_CS)
	var attribute_class: String = FileAccess.get_file_as_string(ATTRIBUTES_CS)

	for snippet: String in [
		"public partial class AttributeComponent : Node",
		"public override void _ValidateProperty(Godot.Collections.Dictionary property)",
		"private readonly Queue<RecalculateRequest> _recalculateQueue = [];",
		"private static IEnumerable<AttributeModifier> ReadAttributeModifiers(Variant statusVariant)",
		"statusObject.Call(\"GetAttributeModifiersData\").AsGodotArray()",
		"public void InitializeWithData(Resource data)",
		"private void FlushRecalculateQueue()",
	]:
		assert_true(legacy.contains(snippet), "旧 C# 垫片必须保留实现片段：%s" % snippet)

	assert_true(attribute_class.contains("public enum AttributeType"), "旧 C# 属性枚举必须保留。")
	assert_true(attribute_class.contains("public class Attribute(AttributeType type"), "旧 C# 属性值类型必须保留。")


## 验证数值上限同步仍走旧 C# 的相对宿主路径与方法协议。
##
## @return 无返回值。
func test_vital_max_sync_keeps_legacy_relative_paths() -> void:
	## C# 垫片仍是本用例的对照对象；C# 退役后整例跳过。
	if not CS_OPTIONAL.present(COMPONENT_CS):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var component: String = FileAccess.get_file_as_string(COMPONENT_GD)
	var legacy: String = FileAccess.get_file_as_string(COMPONENT_CS)
	var vital_base: String = FileAccess.get_file_as_string("res://entities/components/vital_component_base.gd")

	assert_true(component.contains("const HEALTH_COMPONENT_PATH: NodePath = ^\"HealthComponent\""), "生命组件必须按宿主相对路径解析。")
	assert_true(component.contains("const ENERGY_COMPONENT_PATH: NodePath = ^\"EnergyComponent\""), "能量组件必须按宿主相对路径解析。")
	assert_false(component.contains("Components/HealthComponent"), "不得顺手把生命组件路径改成组件子节点路径。")
	assert_false(component.contains("Components/EnergyComponent"), "不得顺手把能量组件路径改成组件子节点路径。")

	assert_true(legacy.contains("GetNodeOrNull<Node>(\"HealthComponent\")"), "旧 C# 生命组件查找路径必须保留。")
	assert_true(legacy.contains("GetNodeOrNull<Node>(\"EnergyComponent\")"), "旧 C# 能量组件查找路径必须保留。")

	assert_true(vital_base.contains("func InitializeMax(new_max_value: int) -> void:"), "数值组件必须保留 InitializeMax 协议。")
	assert_true(
		vital_base.contains("func SetMaxValuePreservingCurrent(new_max_value: int) -> void:"),
		"数值组件必须保留 SetMaxValuePreservingCurrent 协议。"
	)
	assert_true(component.contains("REASON_INITIALIZATION"), "初始化必须同步补满数值。")


## 验证生产脚本没有“从 Variant 推断类型”的写法。
##
## 回归：本项目把 GDScript 的 inference_on_variant 警告当作错误处理，`:= SCRIPT.new()`
## 会让游戏在启动阶段直接停在解析错误上（本批已踩过一次）。
##
## @return 无返回值。
func test_no_variant_type_inference_in_production_script() -> void:
	var component: String = FileAccess.get_file_as_string(COMPONENT_GD)

	for literal: String in [
		"= ATTRIBUTE_VALUE_SCRIPT.new() as RefCounted",
		"= ATTRIBUTE_CHANGE_CONTEXT_SCRIPT.new() as RefCounted",
		"= ATTRIBUTE_CHANGED_EVENT_SCRIPT.new() as RefCounted",
	]:
		assert_true(component.contains(literal), "脚本构造必须显式转成 RefCounted：%s" % literal)

	var pattern := RegEx.new()
	# 允许 “.new() as RefCounted” 这种显式转换写法，只拦截没有显式类型的 Variant 推断。
	assert_eq(
		pattern.compile("var\\s+\\w+\\s*:=\\s*[A-Z_][A-Z0-9_]*\\.new\\(\\)(?!\\s+as\\s)"),
		OK,
		"Variant 推断扫描正则必须能够编译。"
	)
	assert_true(
		pattern.search(component) == null,
		"生产脚本不得用 := 直接承接 SCRIPT.new() 的 Variant 返回值。"
	)


## 判断脚本全文是否声明了 class_name。
##
## @param text GDScript 全文。
## @return 声明了 class_name 时返回 true。
func _declares_class_name(text: String) -> bool:
	for raw_line: String in text.split("\n"):
		if raw_line.strip_edges().begins_with("class_name"):
			return true

	return false


## 统计子串出现次数。
##
## @param text 全文。
## @param needle 待统计子串。
## @return 出现次数。
func _count_occurrences(text: String, needle: String) -> int:
	return text.split(needle).size() - 1


## 从旧 C# 文件读取 AttributeType 的声明顺序。
##
## @param text 旧 C# Attributes.cs 全文。
## @return 枚举成员名数组。
func _read_legacy_attribute_type_order(text: String) -> Array[String]:
	var names: Array[String] = []
	var pattern := RegEx.new()
	if pattern.compile("public enum AttributeType\\s*\\{([^}]*)\\}") != OK:
		return names

	var found := pattern.search(text)
	if found == null:
		return names

	for raw_line: String in found.get_string(1).split("\n"):
		var line: String = raw_line.strip_edges()
		var comment_index: int = line.find("//")
		if comment_index >= 0:
			line = line.substr(0, comment_index).strip_edges()
		if line.is_empty():
			continue
		names.append(line.trim_suffix(","))

	return names


## 递归扫描资产目录中的旧 C# 脚本引用。
##
## @param directory 起始目录的 res:// 路径。
## @param needle 待匹配的旧脚本文件名片段。
## @return 命中的资产路径数组。
func _grep_asset_references(directory: String, needle: String) -> Array[String]:
	var offenders: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return offenders

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with("."):
				offenders.append_array(_grep_asset_references("%s/%s" % [directory, entry], needle))
		elif entry.ends_with(".tscn") or entry.ends_with(".tres"):
			var path := "%s/%s" % [directory, entry]
			if FileAccess.get_file_as_string(path).contains(needle):
				offenders.append(path)
		entry = dir.get_next()

	dir.list_dir_end()
	return offenders


## 验证属性域类型族脚本的文件形状（本批新增）。
##
## @return 无返回值。
func test_attribute_type_family_script_shape() -> void:
	for path: String in [
		ATTRIBUTES_GD,
		MODIFIER_GD,
		RECALCULATE_SCOPE_GD,
		CHANGE_DIRECTION_GD,
		CHANGE_REASON_GD,
		RECALCULATE_REQUEST_GD,
		READ_ONLY_ATTRIBUTE_GD,
	]:
		assert_true(FileAccess.file_exists(path), "生产文件必须存在：%s" % path)
		var text: String = FileAccess.get_file_as_string(path)
		assert_true(text.begins_with("extends RefCounted"), "类型族脚本必须继承 RefCounted：%s" % path)
		assert_false(_declares_class_name(text), "类型族脚本不得声明 class_name：%s" % path)
		assert_false(text.contains("TODO"), "生产脚本不得保留 TODO 占位：%s" % path)

	var request: String = FileAccess.get_file_as_string(RECALCULATE_REQUEST_GD)
	assert_true(request.contains("static func Single("), "重算请求必须保留 Single 工厂。")
	assert_true(request.contains("static func All("), "重算请求必须保留 All 工厂。")
	assert_true(request.contains("func ApplyMutation() -> void:"), "重算请求必须保留 ApplyMutation。")
	for field: String in [
		"Scope", "Type", "Source", "Reason", "AllowInterception", "EmitEvents",
	]:
		assert_true(request.contains("var %s:" % field), "重算请求必须保留字段：%s" % field)

	# 字段默认值与旧 C# 工厂的默认参数逐项一致：允许拦截、发送事件、mutation 可空。
	assert_true(request.contains("mutation: Variant = null"), "mutation 必须默认空。")
	assert_true(request.contains("allow_interception: bool = true"), "拦截必须默认允许。")
	assert_true(request.contains("emit_events: bool = true"), "事件必须默认发送。")


## 验证属性域类型族脚本的枚举与旧 C#、消费方常量逐值一致（本批新增）。
##
## @return 无返回值。
func test_attribute_type_family_mirrors_legacy_and_consumers() -> void:
	## C# 源文仍是本用例的对照对象；C# 退役后整例跳过。
	if not CS_OPTIONAL.present(ATTRIBUTES_CS):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	var attributes_gd: String = FileAccess.get_file_as_string(ATTRIBUTES_GD)
	var legacy_attributes: String = FileAccess.get_file_as_string(ATTRIBUTES_CS)
	var component: String = FileAccess.get_file_as_string(COMPONENT_GD)

	var gd_attribute_names: Array[String] = _read_gd_enum_members(attributes_gd, "AttributeType")
	var legacy_attribute_names: Array[String] = _read_legacy_enum_order(legacy_attributes, "AttributeType")
	assert_eq(gd_attribute_names, legacy_attribute_names, "GDScript AttributeType 必须与旧 C# 顺序逐项一致。")
	assert_eq(gd_attribute_names.size(), 15, "GDScript AttributeType 必须仍是 15 项。")

	for row: Array in ATTRIBUTE_ROWS:
		var value: int = int(row[0])
		var enum_name: String = str(row[1])
		var constant: String = str(row[2])
		assert_eq(
			gd_attribute_names[value], enum_name, "类型族枚举顺序必须与旧 C# 一致：%s" % enum_name
		)
		assert_true(
			component.contains("const ATTRIBUTE_%s: int = %d" % [constant, value]),
			"属性组件常量必须与新枚举同值：%s" % enum_name
		)

	# 四个小枚举：GDScript 顺序必须与旧 C# 完全一致。
	for row: Array in [
		[MODIFIER_GD, MODIFIER_CS, "AttributeModifierMode"],
		[RECALCULATE_SCOPE_GD, RECALCULATE_SCOPE_CS, "AttributeRecalculateScope"],
		[CHANGE_DIRECTION_GD, CHANGE_DIRECTION_CS, "AttributeChangeDirection"],
		[CHANGE_REASON_GD, CHANGE_REASON_CS, "AttributeChangeReason"],
	]:
		var gd_names: Array[String] = _read_gd_enum_members(
			FileAccess.get_file_as_string(str(row[0])), str(row[2])
		)
		var legacy_names: Array[String] = _read_legacy_enum_order(
			FileAccess.get_file_as_string(str(row[1])), str(row[2])
		)
		assert_true(not gd_names.is_empty(), "GDScript 枚举必须可解析：%s" % str(row[2]))
		assert_eq(gd_names, legacy_names, "枚举顺序必须与旧 C# 一致：%s" % str(row[2]))

	# 每个成员都要有同值的消费方常量，避免迁移期两侧取值漂移。
	for row: Array in TYPE_FAMILY_ROWS:
		var member: String = str(row[4])
		var value: int = int(row[5])
		var enum_names: Array[String] = _read_gd_enum_members(
			FileAccess.get_file_as_string(str(row[0])), str(row[1])
		)
		assert_true(value < enum_names.size(), "枚举值必须在范围内：%s" % member)
		assert_eq(enum_names[value], member, "枚举成员顺序必须与常量值一致：%s" % member)
		assert_true(
			FileAccess.get_file_as_string(str(row[2])).contains(
				"const %s%s: int = %d" % [str(row[3]), member.to_snake_case().to_upper(), value]
			),
			"消费方必须保留同值常量：%s" % member
		)


## 验证属性修饰条目的运行时字段协议与跨语言字典（本批新增）。
##
## @return 无返回值。
func test_attribute_modifier_runtime_protocol() -> void:
	var modifier_script: GDScript = load(MODIFIER_GD)
	assert_true(modifier_script != null, "属性修饰脚本必须可加载。")

	var modifier: RefCounted = modifier_script.new(4, 1, 0.25, 3, &"status.burn")
	assert_true(modifier != null, "属性修饰条目必须可构造。")
	assert_eq(int(modifier.get("Type")), 4, "Type 必须逐字保留。")
	assert_eq(int(modifier.get("Mode")), 1, "Mode 必须逐字保留。")
	assert_true(
		is_equal_approx(float(modifier.get("ValuePerStack")), 0.25), "ValuePerStack 必须逐字保留。"
	)
	assert_eq(int(modifier.get("Stacks")), 3, "Stacks 必须逐字保留。")
	assert_eq(String(modifier.get("SourceId")), "status.burn", "SourceId 必须逐字保留。")
	assert_true(
		is_equal_approx(float(modifier.call("TotalValue")), 0.75), "总量必须等于每层值乘层数。"
	)

	var dictionary: Dictionary = modifier.call("ToDictionary")
	assert_eq(dictionary.size(), 5, "跨语言字典必须只有五个字段。")
	for key: String in ["Type", "Mode", "ValuePerStack", "Stacks", "SourceId"]:
		assert_true(dictionary.has(key), "跨语言字典必须保留字段：%s" % key)
	assert_eq(int(dictionary.get("Type")), 4, "字典 Type 必须是枚举整数。")
	assert_eq(int(dictionary.get("Stacks")), 3, "字典 Stacks 必须是层数。")

	# 旧 C# 枚举与结构体仍必须保留，供未迁移的 C# 状态实例继续使用。
	## C# 源文对照：C# 退役后 read() 返回空串，C# 侧断言按条件收起。
	var legacy: String = CS_OPTIONAL.read(MODIFIER_CS)
	if not legacy.is_empty():
		assert_true(legacy.contains("public enum AttributeModifierMode"), "旧 C# 修饰模式枚举必须保留。")
		assert_true(
			legacy.contains("public readonly record struct AttributeModifier("), "旧 C# 修饰条目必须保留。"
		)


## 验证重算请求工厂的运行时字段、默认值与副作用语义（本批新增）。
##
## @return 无返回值。
func test_recalculate_request_runtime_protocol() -> void:
	var request_script: GDScript = load(RECALCULATE_REQUEST_GD)
	assert_true(request_script != null, "重算请求脚本必须可加载。")

	var applied: Array = []
	var single: RefCounted = request_script.Single(4, null, 4, func() -> void: applied.append(1))
	assert_true(single != null, "Single 必须能构造请求。")
	assert_eq(int(single.get("Scope")), 0, "Single 必须是单属性作用域。")
	assert_eq(int(single.get("Type")), 4, "Single 必须保留目标属性类型。")
	assert_eq(int(single.get("Reason")), 4, "Single 必须保留变化原因。")
	assert_true(bool(single.get("AllowInterception")), "默认必须允许拦截。")
	assert_true(bool(single.get("EmitEvents")), "默认必须发送事件。")
	assert_eq(single.get("Source"), null, "source 必须原样保留。")

	single.call("ApplyMutation")
	assert_eq(applied.size(), 1, "ApplyMutation 必须执行一次副作用。")

	var full: RefCounted = request_script.All(null, 5, null, false, false)
	assert_true(full != null, "All 必须能构造请求。")
	assert_eq(int(full.get("Scope")), 1, "All 必须是全量作用域。")
	assert_eq(int(full.get("Type")), 0, "全量请求必须保持旧 C# default(AttributeType) = 0。")
	assert_false(bool(full.get("AllowInterception")), "显式关闭拦截必须生效。")
	assert_false(bool(full.get("EmitEvents")), "显式关闭事件必须生效。")
	# 未提供 Callable 时 ApplyMutation 必须是空操作，且不得报错。
	full.call("ApplyMutation")

	## C# 源文对照：C# 退役后 read() 返回空串，C# 侧断言按条件收起。
	var legacy: String = CS_OPTIONAL.read(RECALCULATE_REQUEST_CS)
	if not legacy.is_empty():
		assert_true(legacy.contains("public static RecalculateRequest Single("), "旧 C# Single 必须保留。")
		assert_true(legacy.contains("public static RecalculateRequest All("), "旧 C# All 必须保留。")


## 验证只读属性视图的成员协议与生产实现（本批新增）。
##
## @return 无返回值。
func test_read_only_attribute_protocol_surface() -> void:
	## C# 源文对照：C# 退役后 read() 返回空串，C# 接口成员对照按条件收起。
	var legacy: String = CS_OPTIONAL.read(READ_ONLY_ATTRIBUTE_CS)
	var protocol_script: GDScript = load(READ_ONLY_ATTRIBUTE_GD)
	assert_true(protocol_script != null, "只读属性协议脚本必须可加载。")

	var exported: Variant = protocol_script.get_script_constant_map().get("REQUIRED_MEMBERS")
	assert_true(exported is Array, "只读属性协议必须导出成员表。")
	var required: Array = exported
	assert_eq(required.size(), 7, "只读属性协议必须是旧 C# 接口的七个成员。")
	assert_eq(String(required[0]), "Type", "成员顺序必须与旧 C# 接口一致。")
	assert_eq(String(required[6]), "RawValue", "成员顺序必须与旧 C# 接口一致。")

	if not legacy.is_empty():
		for member: Variant in required:
			assert_true(
				legacy.contains("%s { get; }" % String(member)), "旧 C# 接口必须保留成员：%s" % String(member)
			)

	# 生产实现必须真的提供这七个成员，保证跨语言只读读取形状成立。
	var value: RefCounted = load(ATTRIBUTE_VALUE_GD).new()
	value.call("Initialize", 4, "速度", 100.0, 5.0)
	var provided: Array[String] = []
	var property_list: Array[Dictionary] = value.get_property_list()
	for property: Dictionary in property_list:
		provided.append(str(property.get("name")))
	for member: Variant in required:
		assert_true(provided.has(String(member)), "只读属性实现必须提供成员：%s" % String(member))


## 从 GDScript 全文读取具名枚举的成员名顺序。
##
## @param text GDScript 全文。
## @param enum_name 枚举名。
## @return 成员名数组；解析失败时返回空数组。
func _read_gd_enum_members(text: String, enum_name: String) -> Array[String]:
	var names: Array[String] = []
	var pattern := RegEx.new()
	if pattern.compile("enum\\s+%s\\s*\\{([^}]*)\\}" % enum_name) != OK:
		return names

	var found := pattern.search(text)
	if found == null:
		return names

	for raw_line: String in found.get_string(1).split("\n"):
		var line: String = raw_line.strip_edges()
		var comment_index: int = line.find("#")
		if comment_index >= 0:
			line = line.substr(0, comment_index).strip_edges()
		if line.is_empty():
			continue
		var equal_index: int = line.find("=")
		if equal_index >= 0:
			line = line.substr(0, equal_index).strip_edges()
		names.append(line.trim_suffix(","))

	return names


## 从旧 C# 文件读取具名枚举的成员顺序（未显式赋值，顺序即取值）。
##
## @param text C# 全文。
## @param enum_name 枚举名。
## @return 成员名数组；解析失败时返回空数组。
func _read_legacy_enum_order(text: String, enum_name: String) -> Array[String]:
	var names: Array[String] = []
	var pattern := RegEx.new()
	if pattern.compile("public enum\\s+%s\\s*\\{([^}]*)\\}" % enum_name) != OK:
		return names

	var found := pattern.search(text)
	if found == null:
		return names

	for raw_line: String in found.get_string(1).split("\n"):
		var line: String = raw_line.strip_edges()
		var comment_index: int = line.find("//")
		if comment_index >= 0:
			line = line.substr(0, comment_index).strip_edges()
		if line.is_empty():
			continue
		# 显式赋值的枚举成员在这里不参与顺序对照，避免把 "Name = 0" 当成成员名。
		if line.find("=") >= 0:
			continue
		names.append(line.trim_suffix(","))

	return names
