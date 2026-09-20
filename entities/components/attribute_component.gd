extends Node

## 属性组件的 GDScript 生产实现，等价迁移自 entities/components/AttributeComponent.cs。
##
## 属性域被拆成三个纯数据脚本（attribute_value / attribute_change_context /
## attribute_changed_event），字段名与旧 C# 同名类型逐字一致；状态组件、状态实例与
## 生命/能量组件全部按稳定方法协议调用，因此它们可以来自任一语言。
## 不声明 class_name，避免与仍在使用的 C# 全局类型重名。

signal AttributeChanged(change_event)
signal AvailablePointsChanged(available_points)

## 属性类型整数值，与旧 C# AttributeType 声明顺序逐项一致。
const ATTRIBUTE_PHYS_ATK: int = 0
const ATTRIBUTE_PHYS_DEF: int = 1
const ATTRIBUTE_MAG_POWER: int = 2
const ATTRIBUTE_MAG_RESIST: int = 3
const ATTRIBUTE_SPEED: int = 4
const ATTRIBUTE_MAX_HEALTH: int = 5
const ATTRIBUTE_MAX_ENERGY: int = 6
const ATTRIBUTE_FIXED_PHYS_PENETRATION: int = 7
const ATTRIBUTE_PHYS_PENETRATION_RATE: int = 8
const ATTRIBUTE_FIXED_MAGIC_PENETRATION: int = 9
const ATTRIBUTE_MAGIC_PENETRATION_RATE: int = 10
const ATTRIBUTE_CRIT_RATE: int = 11
const ATTRIBUTE_CRIT_DAMAGE: int = 12
const ATTRIBUTE_EVASION_RATE: int = 13
const ATTRIBUTE_LIFESTEAL_RATE: int = 14

## 状态修饰模式整数值，等价旧 C# AttributeModifierMode。
const MODIFIER_MODE_FLAT_ADD: int = 0
const MODIFIER_MODE_PERCENT_ADD: int = 1
const MODIFIER_MODE_PERCENT_MUL: int = 2

## 变化原因整数值，等价旧 C# AttributeChangeReason。
const REASON_INITIALIZATION: int = 0
const REASON_ALLOCATED_POINT_CHANGED: int = 1
const REASON_PERMANENT_BONUS_CHANGED: int = 2
const REASON_BASE_VALUE_CHANGED: int = 3
const REASON_STATUS_CHANGED: int = 4
const REASON_FORCED_RECALCULATION: int = 5

## 重算作用域整数值，等价旧 C# AttributeRecalculateScope。
const SCOPE_SINGLE_ATTRIBUTE: int = 0
const SCOPE_ALL_ATTRIBUTES: int = 1

## 单次刷新最多处理的重算请求数，等价旧 C# MaxRecalculateRequestsPerFlush。
const MAX_RECALCULATE_REQUESTS_PER_FLUSH: int = 64

## 属性枚举名（下标即整数值），用于保持旧 C# 枚举插值文本。
const ATTRIBUTE_NAMES: Array[String] = [
	"PhysAtk",
	"PhysDef",
	"MagPower",
	"MagResist",
	"Speed",
	"MaxHealth",
	"MaxEnergy",
	"FixedPhysPenetration",
	"PhysPenetrationRate",
	"FixedMagicPenetration",
	"MagicPenetrationRate",
	"CritRate",
	"CritDamage",
	"EvasionRate",
	"LifestealRate",
]

## 实时调试属性导出名，等价旧 C# [ExportGroup("Realtime Attributes (Debug)")] 的只读属性面。
const REALTIME_ATTRIBUTE_PROPERTIES: Array[String] = [
	"Speed",
	"MagPower",
	"MagResist",
	"PhysAtk",
	"PhysDef",
	"MaxHealth",
	"MaxEnergy",
	"FixedPhysPenetration",
	"PhysPenetrationRate",
	"FixedMagicPenetration",
	"MagicPenetrationRate",
	"CritRate",
	"CritDamage",
	"EvasionRate",
	"LifestealRate",
]

## 属性域数据脚本。
const ATTRIBUTE_VALUE_SCRIPT: GDScript = preload("res://core/attributes/attribute_value.gd")
const ATTRIBUTE_CHANGE_CONTEXT_SCRIPT: GDScript = preload(
	"res://core/attributes/attribute_change_context.gd"
)
const ATTRIBUTE_CHANGED_EVENT_SCRIPT: GDScript = preload(
	"res://core/attributes/attribute_changed_event.gd"
)

## 状态组件查找协议，等价旧 C# ComponentLookup.GetStatusComponentOrNull 的三段回退。
## 注意：节点查找参数必须是 NodePath，传 StringName 会在运行时触发 Parser Error。
const STATUS_COMPONENT_NAME: NodePath = ^"StatusComponent"
const STATUS_COMPONENT_IN_COMPONENTS_PATH: NodePath = ^"Components/StatusComponent"
const STATUS_COMPONENT_UNIQUE_PATH: NodePath = ^"%StatusComponent"
## 状态变化信号名。
const STATUS_CHANGED_SIGNAL: StringName = &"StatusChanged"
## 数值组件相对宿主组件的节点路径，等价旧 C# Host.GetNodeOrNull("HealthComponent")。
const HEALTH_COMPONENT_PATH: NodePath = ^"HealthComponent"
const ENERGY_COMPONENT_PATH: NodePath = ^"EnergyComponent"
## 数值组件方法协议。
const INITIALIZE_MAX_METHOD: StringName = &"InitializeMax"
const SET_MAX_PRESERVING_CURRENT_METHOD: StringName = &"SetMaxValuePreservingCurrent"
## 状态钩子读取的上下文字段名。
const CONTEXT_OLD_VALUE: StringName = &"OldValue"
const CONTEXT_DELTA: StringName = &"Delta"
const CONTEXT_NEW_VALUE: StringName = &"NewValue"
## 状态实例的属性修饰跨语言出口。
const STATUS_MODIFIERS_DATA_METHOD: StringName = &"GetAttributeModifiersData"

## 初始属性配置 Resource；旧 C# StartingStats 与 GDScript starting_stats 都可作为输入。
@export var InitialData: Resource = null
## 当前可用属性点。
var AvailablePoints: int = 0

## 属性表：整型属性类型 -> attribute_value.gd 实例。
var _attributes: Dictionary = {}
## 已提交的最终属性值缓存：整型属性类型 -> 浮点最终值。
var _effective_cache: Dictionary = {}
## 状态组件节点，可能来自 C# 垫片或 GDScript 生产实现。
var _status_component: Node = null
## 状态变化信号的稳定连接，避免重复连接与迁移期的连接泄漏。
var _status_changed_callable: Callable
## 是否由本组件建立了状态信号连接。
var _status_subscribed: bool = false
## 待处理的重算请求队列。
var _recalculate_queue: Array = []
## 是否正在刷新重算队列。
var _is_flushing_recalculate_queue: bool = false


## 属性宿主组件节点，等价旧 C# Host => GetParent()。
var Host: Node:
	get:
		return get_parent()


## 获取当前速度。
@export var Speed: float:
	get:
		return GetEffectiveValue(ATTRIBUTE_SPEED)


## 获取当前法术强度。
@export var MagPower: float:
	get:
		return GetEffectiveValue(ATTRIBUTE_MAG_POWER)


## 获取当前法术抗性。
@export var MagResist: float:
	get:
		return GetEffectiveValue(ATTRIBUTE_MAG_RESIST)


## 获取当前物理攻击。
@export var PhysAtk: float:
	get:
		return GetEffectiveValue(ATTRIBUTE_PHYS_ATK)


## 获取当前物理抗性。
@export var PhysDef: float:
	get:
		return GetEffectiveValue(ATTRIBUTE_PHYS_DEF)


## 获取当前生命上限。
@export var MaxHealth: float:
	get:
		return GetEffectiveValue(ATTRIBUTE_MAX_HEALTH)


## 获取当前能量上限。
@export var MaxEnergy: float:
	get:
		return GetEffectiveValue(ATTRIBUTE_MAX_ENERGY)


## 获取当前固定物理穿透。
@export var FixedPhysPenetration: float:
	get:
		return GetEffectiveValue(ATTRIBUTE_FIXED_PHYS_PENETRATION)


## 获取当前物理穿透率。
@export var PhysPenetrationRate: float:
	get:
		return GetEffectiveValue(ATTRIBUTE_PHYS_PENETRATION_RATE)


## 获取当前固定法术穿透。
@export var FixedMagicPenetration: float:
	get:
		return GetEffectiveValue(ATTRIBUTE_FIXED_MAGIC_PENETRATION)


## 获取当前法术穿透率。
@export var MagicPenetrationRate: float:
	get:
		return GetEffectiveValue(ATTRIBUTE_MAGIC_PENETRATION_RATE)


## 获取当前暴击率。
@export var CritRate: float:
	get:
		return GetEffectiveValue(ATTRIBUTE_CRIT_RATE)


## 获取当前暴击伤害倍率。
@export var CritDamage: float:
	get:
		return GetEffectiveValue(ATTRIBUTE_CRIT_DAMAGE)


## 获取当前闪避率。
@export var EvasionRate: float:
	get:
		return GetEffectiveValue(ATTRIBUTE_EVASION_RATE)


## 获取当前吸血率。
@export var LifestealRate: float:
	get:
		return GetEffectiveValue(ATTRIBUTE_LIFESTEAL_RATE)


## 把实时调试属性标记为只读，等价旧 C# _ValidateProperty。
##
## @param property 编辑器传入的属性描述字典。
## @return 无返回值。
func _validate_property(property: Dictionary) -> void:
	var prop_name: String = str(property.get("name", ""))
	if not REALTIME_ATTRIBUTE_PROPERTIES.has(prop_name):
		return

	property["usage"] = int(property.get("usage", 0)) | PROPERTY_USAGE_READ_ONLY


## 节点进入场景树时连接状态组件信号，并按初始配置初始化属性。
##
## @return 无返回值。
func _ready() -> void:
	_subscribe_status_component()

	if InitialData != null:
		InitializeWithData(InitialData)


## 节点离开场景树时解除状态组件连接，避免迁移期重复连接泄漏。
##
## @return 无返回值。
func _exit_tree() -> void:
	if (
		_status_subscribed
		and _status_component != null
		and _status_component.is_connected(STATUS_CHANGED_SIGNAL, _status_changed_callable)
	):
		_status_component.disconnect(STATUS_CHANGED_SIGNAL, _status_changed_callable)

	_status_subscribed = false


## 查找同宿主上的状态组件并连接 StatusChanged。
##
## 三段回退顺序与旧 C# ComponentLookup.GetStatusComponentOrNull 完全一致，返回通用
## Node：状态组件可以来自 C# 垫片或 GDScript 生产实现，调用统一走方法协议。
##
## @return 无返回值。
func _subscribe_status_component() -> void:
	var host := Host
	if host == null:
		return

	_status_component = host.get_node_or_null(STATUS_COMPONENT_NAME)
	if _status_component == null:
		_status_component = host.get_node_or_null(STATUS_COMPONENT_IN_COMPONENTS_PATH)
	if _status_component == null:
		_status_component = host.get_node_or_null(STATUS_COMPONENT_UNIQUE_PATH)

	if _status_component == null:
		return

	_status_changed_callable = Callable(self, "HandleStatusChangedSignal")

	if not _status_component.is_connected(STATUS_CHANGED_SIGNAL, _status_changed_callable):
		_status_component.connect(STATUS_CHANGED_SIGNAL, _status_changed_callable)
		_status_subscribed = true


## 使用初始属性配置重建全部属性并立刻重算一次。
##
## 数据资源可能是旧 C# StartingStats 垫片，也可能是 GDScript 生产实现，因此字段
## 统一按同名属性协议读取。
##
## @param data 提供 Base* / *Growth 字段的属性配置资源。
## @return 无返回值。
func InitializeWithData(data: Resource) -> void:
	if data == null:
		push_error("AttributeComponent initialized with null starting stats Resource.")
		return

	InitialData = data

	_attributes.clear()
	_effective_cache.clear()
	_recalculate_queue.clear()

	SetAttribute(
		ATTRIBUTE_PHYS_ATK, "物理攻击", ReadStat(data, "BasePhysAtk", 100.0), ReadStat(data, "PhysAtkGrowth", 25.0)
	)
	SetAttribute(
		ATTRIBUTE_PHYS_DEF, "物理抗性", ReadStat(data, "BasePhysDef", 100.0), ReadStat(data, "PhysDefGrowth", 20.0)
	)
	SetAttribute(
		ATTRIBUTE_MAG_POWER, "法术强度", ReadStat(data, "BaseMagPower", 100.0), ReadStat(data, "MagPowerGrowth", 30.0)
	)
	SetAttribute(
		ATTRIBUTE_MAG_RESIST, "法术抗性", ReadStat(data, "BaseMagResist", 100.0), ReadStat(data, "MagResistGrowth", 20.0)
	)
	SetAttribute(
		ATTRIBUTE_SPEED, "速度", ReadStat(data, "BaseSpeed", 100.0), ReadStat(data, "SpeedGrowth", 5.0)
	)
	SetAttribute(
		ATTRIBUTE_MAX_HEALTH, "生命上限", ReadStat(data, "BaseMaxHealth", 1000.0), ReadStat(data, "MaxHealthGrowth")
	)
	SetAttribute(
		ATTRIBUTE_MAX_ENERGY, "能量上限", ReadStat(data, "BaseMaxEnergy", 100.0), ReadStat(data, "MaxEnergyGrowth")
	)
	SetAttribute(
		ATTRIBUTE_FIXED_PHYS_PENETRATION,
		"固定物理穿透",
		ReadStat(data, "BaseFixedPhysPenetration"),
		ReadStat(data, "FixedPhysPenetrationGrowth")
	)
	SetAttribute(
		ATTRIBUTE_PHYS_PENETRATION_RATE,
		"物理穿透率",
		ReadStat(data, "BasePhysPenetrationRate"),
		ReadStat(data, "PhysPenetrationRateGrowth")
	)
	SetAttribute(
		ATTRIBUTE_FIXED_MAGIC_PENETRATION,
		"固定法术穿透",
		ReadStat(data, "BaseFixedMagicPenetration"),
		ReadStat(data, "FixedMagicPenetrationGrowth")
	)
	SetAttribute(
		ATTRIBUTE_MAGIC_PENETRATION_RATE,
		"法术穿透率",
		ReadStat(data, "BaseMagicPenetrationRate"),
		ReadStat(data, "MagicPenetrationRateGrowth")
	)
	SetAttribute(ATTRIBUTE_CRIT_RATE, "暴击率", ReadStat(data, "BaseCritRate"), ReadStat(data, "CritRateGrowth"))
	SetAttribute(
		ATTRIBUTE_CRIT_DAMAGE,
		"暴击伤害",
		ReadStat(data, "BaseCritDamage", 1.5),
		ReadStat(data, "CritDamageGrowth")
	)
	SetAttribute(
		ATTRIBUTE_EVASION_RATE, "闪避率", ReadStat(data, "BaseEvasionRate"), ReadStat(data, "EvasionRateGrowth")
	)
	SetAttribute(
		ATTRIBUTE_LIFESTEAL_RATE,
		"吸血率",
		ReadStat(data, "BaseLifestealRate"),
		ReadStat(data, "LifestealRateGrowth")
	)

	print("InitializeWithData", data)

	RecalculateAllDirect(
		Host,
		REASON_INITIALIZATION,
		false,
		false
	)


## 从 C# 或 GDScript Resource 读取同名浮点字段。
##
## @param data 提供初始属性字段的 Resource。
## @param property_name 要读取的字段名。
## @param fallback 字段缺失或类型不匹配时使用的旧默认值。
## @return 字段值或兼容默认值。
func ReadStat(data: Resource, property_name: String, fallback: float = 0.0) -> float:
	var value: Variant = data.get(property_name)
	var value_type := typeof(value)
	if value_type == TYPE_INT or value_type == TYPE_FLOAT:
		return float(value)
	return fallback


## 新建一条属性值并写入属性表。
##
## @param type 属性类型整数值。
## @param display_name 展示名。
## @param base_value 基础值。
## @param growth 每点投入的成长值。
## @return 无返回值。
func SetAttribute(type: int, display_name: String, base_value: float, growth: float) -> void:
	# GDScript.new() 返回 Variant：本项目把“从 Variant 推断类型”视为错误，必须显式转成 RefCounted。
	var attribute := ATTRIBUTE_VALUE_SCRIPT.new() as RefCounted
	attribute.Initialize(type, display_name, base_value, growth)
	_attributes[type] = attribute


## 读取单条属性值数据。
##
## @param type 属性类型整数值。
## @return 属性值数据；不存在时返回 null。
func GetAttribute(type: int) -> RefCounted:
	return _attributes.get(type, null)


## 读取全部属性值数据，顺序与初始化写入顺序一致。
##
## @return 属性值数据数组。
func GetAllAttributes() -> Array:
	return _attributes.values()


## 读取属性原始值（基础值 + 固定加成 + 投入成长），不含状态修饰。
##
## @param type 属性类型整数值。
## @return 原始值；属性不存在时返回 0。
func GetRawValue(type: int) -> float:
	var attribute: RefCounted = _attributes.get(type, null)
	if attribute == null:
		return 0.0
	return float(attribute.RawValue)


## 读取最终属性值，带缓存。
##
## @param type 属性类型整数值。
## @return 钳制后的最终值。
func GetEffectiveValue(type: int) -> float:
	if _effective_cache.has(type):
		return float(_effective_cache[type])

	var calculated := CalculateUnclampedEffectiveValue(type)
	var clamped := ClampAttributeValue(type, calculated)

	_effective_cache[type] = clamped
	return clamped


## 发放属性点。
##
## @param amount 发放数量，必须为正数。
## @return 无返回值。
func EarnPoints(amount: int) -> void:
	if amount <= 0:
		push_warning("Cannot earn non-positive attribute points.")
		return

	AvailablePoints += amount
	NotifyAvailablePointsChanged()


## 消耗属性点提升指定属性。
##
## @param target_attribute_type 目标属性类型整数值。
## @param amount 投入点数，必须为正数。
## @return 成功投入返回 true。
func TryAllocatePoint(target_attribute_type: int, amount: int) -> bool:
	if amount <= 0:
		push_warning("Cannot allocate non-positive attribute points.")
		return false

	if AvailablePoints < amount:
		print("没有足够的技能点！")
		return false

	if not _attributes.has(target_attribute_type):
		push_warning(
			"Attribute %s does not exist on %s."
			% [_attribute_name(target_attribute_type), _host_name()]
		)
		return false

	AvailablePoints -= amount
	NotifyAvailablePointsChanged()

	RequestRecalculateAttribute(
		target_attribute_type,
		Host,
		REASON_ALLOCATED_POINT_CHANGED,
		func() -> void:
			_attributes[target_attribute_type].AddPoint(amount)
	)

	return true


## 增加永久固定加成（天赋 / 装备等）。
##
## @param type 属性类型整数值。
## @param amount 增加的固定值。
## @param source 变化来源节点，可为 null。
## @return 成功入队重算返回 true。
func AddPermanentBonus(type: int, amount: float, source: Node = null) -> bool:
	if not _attributes.has(type):
		push_warning("Attribute %s does not exist on %s." % [_attribute_name(type), _host_name()])
		return false

	if is_zero_approx(amount):
		return false

	var resolved_source: Node = source if source != null else Host
	RequestRecalculateAttribute(
		type,
		resolved_source,
		REASON_PERMANENT_BONUS_CHANGED,
		func() -> void:
			_attributes[type].AddBonus(amount)
	)

	return true


## 移除永久固定加成（天赋 / 装备等）。
##
## @param type 属性类型整数值。
## @param amount 移除的固定值。
## @param source 变化来源节点，可为 null。
## @return 成功入队重算返回 true。
func RemovePermanentBonus(type: int, amount: float, source: Node = null) -> bool:
	if not _attributes.has(type):
		push_warning("Attribute %s does not exist on %s." % [_attribute_name(type), _host_name()])
		return false

	if is_zero_approx(amount):
		return false

	var resolved_source: Node = source if source != null else Host
	RequestRecalculateAttribute(
		type,
		resolved_source,
		REASON_PERMANENT_BONUS_CHANGED,
		func() -> void:
			_attributes[type].RemoveBonus(amount)
	)

	return true


## 强制重算全部属性。
##
## @param source 变化来源节点，可为 null。
## @return 无返回值。
func ForceRecalculateAll(source: Node = null) -> void:
	var resolved_source: Node = source if source != null else Host
	RequestRecalculateAll(resolved_source, REASON_FORCED_RECALCULATION)


## 状态添加、移除、叠层、持续时间变化时的回调。
##
## 状态可能影响任意属性，所以这里重算全部属性；状态变化事件可能来自 C# 垫片或
## GDScript 生产实现，因此统一从事件载体的稳定跨语言入口读取实体字段。
##
## @param change_event 状态变化事件载荷。
## @return 无返回值。
func HandleStatusChangedSignal(change_event: Variant) -> void:
	var source: Node = null
	var owner: Node = null

	var change_object := change_event as Object
	if change_object != null and change_object.has_method("GetFeedbackNode"):
		source = change_object.call("GetFeedbackNode", "Source") as Node
		owner = change_object.call("GetFeedbackNode", "Owner") as Node

	var resolved_source: Node = source
	if resolved_source == null:
		resolved_source = owner
	if resolved_source == null:
		resolved_source = Host

	RequestRecalculateAll(resolved_source, REASON_STATUS_CHANGED)


## 入队一次单属性重算请求。
##
## @param type 属性类型整数值。
## @param source 变化来源节点。
## @param reason 变化原因整数值。
## @param mutation 在重算前先执行的属性值变更回调，可为空。
## @param allow_interception 是否允许状态实例拦截本次变化。
## @param emit_events 是否发出 AttributeChanged 信号与 After 钩子。
## @return 无返回值。
func RequestRecalculateAttribute(
	type: int,
	source: Node,
	reason: int,
	mutation: Callable = Callable(),
	allow_interception: bool = true,
	emit_events: bool = true
) -> void:
	var resolved_source: Node = source if source != null else Host
	_enqueue_recalculate(
		{
			"Scope": SCOPE_SINGLE_ATTRIBUTE,
			"Type": type,
			"Source": resolved_source,
			"Reason": reason,
			"Mutation": mutation,
			"AllowInterception": allow_interception,
			"EmitEvents": emit_events,
		}
	)


## 入队一次全属性重算请求。
##
## @param source 变化来源节点。
## @param reason 变化原因整数值。
## @param mutation 在重算前先执行的属性值变更回调，可为空。
## @param allow_interception 是否允许状态实例拦截本次变化。
## @param emit_events 是否发出 AttributeChanged 信号与 After 钩子。
## @return 无返回值。
func RequestRecalculateAll(
	source: Node,
	reason: int,
	mutation: Callable = Callable(),
	allow_interception: bool = true,
	emit_events: bool = true
) -> void:
	var resolved_source: Node = source if source != null else Host
	_enqueue_recalculate(
		{
			"Scope": SCOPE_ALL_ATTRIBUTES,
			"Type": 0,
			"Source": resolved_source,
			"Reason": reason,
			"Mutation": mutation,
			"AllowInterception": allow_interception,
			"EmitEvents": emit_events,
		}
	)


## 把重算请求加入队列，并在非重入状态下立即刷新。
##
## @param request 重算请求字典。
## @return 无返回值。
func _enqueue_recalculate(request: Dictionary) -> void:
	_recalculate_queue.append(request)

	if _is_flushing_recalculate_queue:
		return

	_flush_recalculate_queue()


## 顺序刷新重算队列；超过上限判定为循环触发并清空队列。
##
## @return 无返回值。
func _flush_recalculate_queue() -> void:
	_is_flushing_recalculate_queue = true
	var processed_count := 0

	while not _recalculate_queue.is_empty():
		processed_count += 1

		if processed_count > MAX_RECALCULATE_REQUESTS_PER_FLUSH:
			_recalculate_queue.clear()

			push_error(
				"AttributeComponent detected a possible infinite attribute recalculation loop on %s."
				% _host_name()
			)

			_is_flushing_recalculate_queue = false
			return

		var request: Dictionary = _recalculate_queue.pop_front()
		_process_recalculate_request(request)

	_is_flushing_recalculate_queue = false


## 执行单条重算请求：先应用属性值变更，再重算单属性或全部属性。
##
## @param request 重算请求字典。
## @return 无返回值。
func _process_recalculate_request(request: Dictionary) -> void:
	var mutation: Callable = request.get("Mutation", Callable())
	if mutation.is_valid():
		mutation.call()

	var source: Node = request.get("Source", null)
	var reason := int(request.get("Reason", 0))
	var allow_interception := bool(request.get("AllowInterception", true))
	var emit_events := bool(request.get("EmitEvents", true))

	if int(request.get("Scope", SCOPE_SINGLE_ATTRIBUTE)) == SCOPE_ALL_ATTRIBUTES:
		for type in _attributes.keys().duplicate():
			_recalculate_effective_attribute(
				int(type), source, reason, allow_interception, emit_events
			)
		return

	_recalculate_effective_attribute(
		int(request.get("Type", 0)), source, reason, allow_interception, emit_events
	)


## 直接重算全部属性，不经过队列（初始化路径专用）。
##
## @param source 变化来源节点。
## @param reason 变化原因整数值。
## @param allow_interception 是否允许状态实例拦截。
## @param emit_events 是否发出事件。
## @return 无返回值。
func RecalculateAllDirect(
	source: Node, reason: int, allow_interception: bool, emit_events: bool
) -> void:
	for type in _attributes.keys().duplicate():
		_recalculate_effective_attribute(
			int(type), source, reason, allow_interception, emit_events
		)


## 重算单个属性的最终值，并推进拦截、缓存、上限同步与事件链路。
##
## 结算顺序与旧 C# 逐行一致：候选值 → Before 拦截 → 取消判定 → 二次钳制 → 非法值
## 判定 → 近似相等短路 → 写缓存 → 同步数值上限 → AttributeChanged → After 钩子。
##
## @param type 属性类型整数值。
## @param source 变化来源节点。
## @param reason 变化原因整数值。
## @param allow_interception 是否允许状态实例拦截本次变化。
## @param emit_events 是否发出 AttributeChanged 信号与 After 钩子。
## @return 无返回值。
func _recalculate_effective_attribute(
	type: int, source: Node, reason: int, allow_interception: bool, emit_events: bool
) -> void:
	if not _attributes.has(type):
		return

	var old_value: float
	if _effective_cache.has(type):
		old_value = float(_effective_cache[type])
	else:
		old_value = ClampAttributeValue(type, CalculateUnclampedEffectiveValue(type))

	var attempted_value := ClampAttributeValue(type, CalculateUnclampedEffectiveValue(type))

	# 同上：显式转成 RefCounted，避免 Variant 推断在游戏启动时被当作解析错误。
	var context := ATTRIBUTE_CHANGE_CONTEXT_SCRIPT.new() as RefCounted
	context.Initialize(
		Host,
		source if source != null else Host,
		type,
		reason,
		old_value,
		attempted_value
	)

	if allow_interception and _status_component != null:
		_status_component.call("ProcessBeforeAttributeChange", context)

	if context.IsCancelled:
		# 被拦截取消，最终值保持 oldValue。
		_effective_cache[type] = old_value
		SynchronizeVitalMaximum(type, old_value, reason)
		return

	var final_value := ClampAttributeValue(type, float(context.NewValue))

	if is_nan(final_value) or is_inf(final_value):
		push_error(
			"Invalid attribute value calculated for %s on %s: %s"
			% [_attribute_name(type), _host_name(), _format_invalid_value(final_value)]
		)
		return

	if is_equal_approx(old_value, final_value):
		# 缓存原本不存在时需要补缓存；BeforeAttributeChange 把降低量抵消成 0；
		# 浮点近似相等。不发事件，不触发 After。
		_effective_cache[type] = final_value
		SynchronizeVitalMaximum(type, final_value, reason)
		return

	context.NewValue = final_value
	_effective_cache[type] = final_value
	SynchronizeVitalMaximum(type, final_value, reason)

	if not emit_events:
		return

	NotifyAttributeChanged(context)

	# After 触发的新属性变化会重新进入队列。
	if _status_component != null:
		_status_component.call("ProcessAfterAttributeChanged", context)


## 计算未钳制的最终属性值：原始值经全部激活状态的三种修饰模式叠加。
##
## @param type 属性类型整数值。
## @return 未钳制的最终值；属性不存在时返回 0。
func CalculateUnclampedEffectiveValue(type: int) -> float:
	var attribute: RefCounted = _attributes.get(type, null)
	if attribute == null:
		return 0.0

	var base_value := float(attribute.RawValue)

	var flat_add := 0.0
	var percent_add := 0.0
	var percent_mul := 1.0

	if _status_component != null:
		var snapshot: Array = _status_component.call("GetActiveStatusesSnapshot")

		for status_variant in snapshot:
			for modifier in _read_attribute_modifiers(status_variant):
				if int(modifier.get("Type", -1)) != type:
					continue

				var mode := int(modifier.get("Mode", -1))
				var value_per_stack := float(modifier.get("ValuePerStack", 0.0))
				var stacks := int(modifier.get("Stacks", 0))

				match mode:
					MODIFIER_MODE_FLAT_ADD:
						flat_add += value_per_stack * stacks
					MODIFIER_MODE_PERCENT_ADD:
						percent_add += value_per_stack * stacks
					MODIFIER_MODE_PERCENT_MUL:
						percent_mul *= pow(1.0 + value_per_stack, stacks)
					_:
						push_warning("Unhandled attribute modifier mode: %s" % mode)

	return (base_value + flat_add) * (1.0 + percent_add) * percent_mul


## 读取一个状态实例的属性修饰条目。
##
## 状态实例可能来自 C# 垫片或 GDScript 生产实现，因此统一调用跨语言出口
## GetAttributeModifiersData，条目字段为 Type / Mode / ValuePerStack / Stacks。
##
## @param status_variant 状态实例（任意语言）。
## @return 属性修饰条目字典数组；不支持时返回空数组。
func _read_attribute_modifiers(status_variant: Variant) -> Array:
	var status := status_variant as Object
	if status == null or not status.has_method(STATUS_MODIFIERS_DATA_METHOD):
		return []

	var data: Variant = status.call(STATUS_MODIFIERS_DATA_METHOD)
	if data is Array:
		return data

	return []


## 把属性算出的上限同步到生命 / 能量数值组件。
##
## @param type 属性类型整数值。
## @param value 属性算出的最终值。
## @param reason 变化原因整数值。
## @return 无返回值。
func SynchronizeVitalMaximum(type: int, value: float, reason: int) -> void:
	var max_value := maxi(1, _round_to_int(value))
	var should_refill := reason == REASON_INITIALIZATION

	var host := Host
	if host == null:
		return

	match type:
		ATTRIBUTE_MAX_HEALTH:
			_synchronize_vital_maximum(
				host.get_node_or_null(HEALTH_COMPONENT_PATH), max_value, should_refill
			)
		ATTRIBUTE_MAX_ENERGY:
			# 怪物等无能量单位不会挂载 EnergyComponent；这里允许缺失。
			_synchronize_vital_maximum(
				host.get_node_or_null(ENERGY_COMPONENT_PATH), max_value, should_refill
			)


## 按方法协议把上限写入数值组件。
##
## 数值组件已迁移到 GDScript，因此这里只按 InitializeMax / SetMaxValuePreservingCurrent
## 方法协议调用，兼容 C# 与 GDScript 两种实现，且不复制上限钳制规则。
##
## @param vital 生命或能量等数值组件节点，可为 null。
## @param max_value 属性算出的新上限。
## @param should_refill 是否为初始化，初始化时把当前值补满。
## @return 无返回值。
func _synchronize_vital_maximum(vital: Node, max_value: int, should_refill: bool) -> void:
	if vital == null:
		return

	if should_refill:
		vital.call(INITIALIZE_MAX_METHOD, max_value)
		return

	vital.call(SET_MAX_PRESERVING_CURRENT_METHOD, max_value)


## 按属性类型钳制最终值，规则与旧 C# ClampAttributeValue 逐项一致。
##
## @param type 属性类型整数值。
## @param value 待钳制的值。
## @return 钳制后的值。
func ClampAttributeValue(type: int, value: float) -> float:
	match type:
		ATTRIBUTE_SPEED:
			return maxf(1.0, value)

		ATTRIBUTE_PHYS_ATK:
			return maxf(0.0, value)

		ATTRIBUTE_PHYS_DEF:
			return maxf(0.0, value)

		ATTRIBUTE_MAG_POWER:
			return maxf(0.0, value)

		ATTRIBUTE_MAG_RESIST:
			return maxf(0.0, value)

		ATTRIBUTE_FIXED_PHYS_PENETRATION:
			return maxf(0.0, value)

		ATTRIBUTE_FIXED_MAGIC_PENETRATION:
			return maxf(0.0, value)

		ATTRIBUTE_MAX_HEALTH, ATTRIBUTE_MAX_ENERGY:
			return maxf(1.0, value)

		ATTRIBUTE_PHYS_PENETRATION_RATE:
			return clampf(value, 0.0, 1.0)

		ATTRIBUTE_MAGIC_PENETRATION_RATE:
			return clampf(value, 0.0, 1.0)

		ATTRIBUTE_CRIT_RATE:
			return clampf(value, 0.0, 1.0)

		ATTRIBUTE_EVASION_RATE:
			return clampf(value, 0.0, 1.0)

		ATTRIBUTE_LIFESTEAL_RATE:
			return clampf(value, 0.0, 1.0)

		ATTRIBUTE_CRIT_DAMAGE:
			return maxf(1.0, value)

	return value


## 等价旧 C# Mathf.RoundToInt 的银行家舍入（四舍六入五成双）。
##
## @param value 待取整的值。
## @return 取整结果。
func _round_to_int(value: float) -> int:
	var floored := floorf(value)
	var fraction := value - floored

	if is_equal_approx(fraction, 0.5):
		var candidate := int(floored)
		return candidate if candidate % 2 == 0 else candidate + 1

	return roundi(value)


## 还原旧 C# 浮点插值文本，用于非法值诊断。
##
## @param value 非法浮点值。
## @return 与 C# float.ToString() 一致的字面量。
func _format_invalid_value(value: float) -> String:
	if is_nan(value):
		return "NaN"
	if is_inf(value):
		return "Infinity" if value > 0.0 else "-Infinity"
	return str(value)


## 读取属性枚举名，保持旧 C# 枚举插值文本。
##
## @param type 属性类型整数值。
## @return 枚举名字符串。
func _attribute_name(type: int) -> String:
	if type >= 0 and type < ATTRIBUTE_NAMES.size():
		return ATTRIBUTE_NAMES[type]
	return str(type)


## 读取宿主节点名，等价旧 C# Host?.Name（宿主为空时为空串）。
##
## @return 宿主节点名。
func _host_name() -> String:
	var host := Host
	if host == null:
		return ""
	return host.name


## 发出可用属性点变化信号。
##
## @return 无返回值。
func NotifyAvailablePointsChanged() -> void:
	AvailablePointsChanged.emit(AvailablePoints)


## 发出属性变化信号，载荷为新旧字段面一致的属性变化事件。
##
## @param context 本次属性变化上下文。
## @return 无返回值。
func NotifyAttributeChanged(context: RefCounted) -> void:
	# 同上：显式转成 RefCounted，避免 Variant 推断在游戏启动时被当作解析错误。
	var change_event := ATTRIBUTE_CHANGED_EVENT_SCRIPT.new() as RefCounted
	change_event.Initialize(context)

	AttributeChanged.emit(change_event)
