extends Node

## 玩家实体根节点的 GDScript 生产实现，等价迁移自 entities/Player.cs。
##
## 脚本只做组件定位、信号转发与稳定方法协议调用：生命、能量、饱食、状态、装备、卡组、
## 标签与库存组件都可能来自任一语言，因此全部按节点名解析、按字段/方法协议读取。
## 不声明 class_name，避免与仍在使用的 C# 全局类型重名。

## 生命与饱食组件共用的归零信号名，与旧 C# 字面量一致。
const DEPLETED_SIGNAL: StringName = &"Depleted"
## 全局事件总线节点路径。
const GLOBAL_EVENT_BUS_PATH: NodePath = ^"/root/GlobalEventBus"
## 等级系统 Autoload 节点路径；解析失败时只影响属性点发放，玩家其余行为不受影响。
const PLAYER_LEVEL_PATH: NodePath = ^"/root/PlayerLevel"
## 天赋事件名，等价旧 C# GDSignals.OnPlayerAcquiredTalent。
const ON_PLAYER_ACQUIRED_TALENT: StringName = &"on_player_acquired_talent"
## 玩家死亡事件名。
const PLAYER_DIED_SIGNAL: StringName = &"player_died"
## 生命组件节点路径。
const HEALTH_COMPONENT_PATH: NodePath = ^"Components/HealthComponent"
## 饱食组件节点路径。
const SATIETY_COMPONENT_PATH: NodePath = ^"Components/SatietyComponent"
## 能量组件节点路径。
const ENERGY_COMPONENT_PATH: NodePath = ^"Components/EnergyComponent"
## 装备组件节点路径。
const EQUIPMENT_COMPONENT_PATH: NodePath = ^"Components/EquipmentComponent"
## 属性组件节点路径。
const ATTRIBUTE_COMPONENT_PATH: NodePath = ^"Components/AttributeComponent"
## 标签组件节点路径。
const TAG_COMPONENT_PATH: NodePath = ^"Components/TagComponent"
## 状态组件唯一名路径，与旧 C# %StatusComponent 写法一致。
const STATUS_COMPONENT_UNIQUE_PATH: NodePath = ^"%StatusComponent"
## 库存组件节点路径。
const INVENTORY_COMPONENT_PATH: NodePath = ^"Components/InventoryComponent"
## 出战卡组组件节点路径。
const BATTLE_DECK_COMPONENT_PATH: NodePath = ^"Components/BattleDeckComponent"
## ElementType.None 的整数值，等价旧 C# (int)ElementType.None。
const ELEMENT_NONE: int = 0
## 饥饿归零时每秒承受的伤害，与旧 C# 一致。
const SATIETY_DEPLETED_DAMAGE: int = 5

## 能量组件节点。
var Energy: Node = null
## 属性组件节点，消费方按稳定属性名读取。
var Attributes: Node = null
## 出战卡组组件节点。
var BattleDeck: Node = null
## 装备组件节点。
var Equipment: Node = null
## 状态组件节点；行为统一走方法协议。
var Status: Node = null
## 标签组件节点。
var TagComponent: Node = null

## 生命组件节点，等价旧 C# 私有字段 _health。
var _health: Node = null
## 饱食组件节点，等价旧 C# 私有字段 _satiety。
var _satiety: Node = null
## 库存组件节点，只依赖稳定方法协议。
var _inventory: Node = null
## 全局事件总线节点。
var _global_event_bus: Node = null
## 等级系统节点，只按稳定方法与信号协议访问，不假设其语言实现。
var _player_level: Node = null
## 饱食归零回调，缓存用于退出时精确断开。
var _satiety_depleted_callable: Callable
## 生命归零回调，缓存用于退出时精确断开。
var _health_depleted_callable: Callable


## 组件进入场景树时解析全部组件引用并连接归零信号。
##
## @return 无返回值。
func _ready() -> void:
	_health = get_node(HEALTH_COMPONENT_PATH)
	_satiety = get_node(SATIETY_COMPONENT_PATH)
	Energy = get_node(ENERGY_COMPONENT_PATH)
	Equipment = get_node(EQUIPMENT_COMPONENT_PATH)
	Attributes = get_node(ATTRIBUTE_COMPONENT_PATH)
	TagComponent = get_node(TAG_COMPONENT_PATH)
	Status = get_node(STATUS_COMPONENT_UNIQUE_PATH)
	_inventory = get_node(INVENTORY_COMPONENT_PATH)
	BattleDeck = get_node(BATTLE_DECK_COMPONENT_PATH)
	_satiety_depleted_callable = OnSatietyDepleted
	_health_depleted_callable = OnPlayerDied
	_satiety.connect(DEPLETED_SIGNAL, _satiety_depleted_callable)
	_health.connect(DEPLETED_SIGNAL, _health_depleted_callable)

	_global_event_bus = get_node(GLOBAL_EVENT_BUS_PATH)
	_global_event_bus.connect(ON_PLAYER_ACQUIRED_TALENT, _absorb_talent)

	# 等级系统由 Autoload 提供，必定先于玩家场景树就绪；这里仍按可空方式绑定，
	# 使玩家在缺少该系统的裁剪环境里也能照常启动。
	_player_level = get_node_or_null(PLAYER_LEVEL_PATH)
	_bind_player_level()


## 订阅等级系统的属性点发放信号，并补领进入场景前已经累积的挂起点数。
##
## 补领是必需的：玩家可能在升级发生之后才进入场景（场景切换、重载、死亡后重建），
## 若只依赖信号，这段窗口期内发放的点数将永远收不到。
##
## @return 无返回值。
func _bind_player_level() -> void:
	if _player_level == null:
		return

	# 固定回调身份用于去重连接与精确断开。
	var granted_callback := Callable(self, "_on_attribute_points_granted")
	if (
		_player_level.has_signal(&"AttributePointsGranted")
		and not _player_level.is_connected(&"AttributePointsGranted", granted_callback)
	):
		_player_level.connect(&"AttributePointsGranted", granted_callback)

	_grant_pending_attribute_points()


## 等级系统发出属性点发放信号后的回调。
##
## @param _pending_points 当前挂起属性点总数；实际领取数量由领取接口返回，因此回调本身不使用该参数。
## @return 无返回值。
func _on_attribute_points_granted(_pending_points: int) -> void:
	_grant_pending_attribute_points()


## 领取挂起的属性点并写入属性组件。
##
## 领取顺序刻意设计为「先探测能力、再领取」：若先领取后才发现属性组件不支持发点，
## 就必须再设计一套退点接口来补漏；先探测则让不支持的组合退化为「点数继续挂起」，
## 用更少的代码彻底消除丢点的可能。
##
## @return 无返回值。
func _grant_pending_attribute_points() -> void:
	if _player_level == null or Attributes == null:
		return
	if not _player_level.has_method("ClaimPendingAttributePoints"):
		return
	if not Attributes.has_method("EarnPoints"):
		return

	var claimed: int = int(_player_level.call("ClaimPendingAttributePoints"))
	if claimed <= 0:
		return

	Attributes.call("EarnPoints", claimed)


## 吸收一个天赋资源，逐条应用其中的效果。
##
## @param new_talent 携带 TalentName 与 Effects 字段的天赋资源。
## @return 无返回值。
func _absorb_talent(new_talent: Resource) -> void:
	var raw_name: Variant = new_talent.get("TalentName")
	var talent_name: String = str(raw_name) if raw_name != null else ""
	print("主角感受到神秘力量涌入：%s！" % talent_name)

	var effects_value: Variant = new_talent.get("Effects")
	if typeof(effects_value) != TYPE_ARRAY:
		return

	for effect_value: Variant in effects_value:
		if effect_value is Resource and (effect_value as Resource).has_method("Apply"):
			# 效果可能来自任一语言，通过稳定方法名保留同一个 Resource 实例。
			(effect_value as Resource).call("Apply", self)


## 饥饿归零时按固定数值扣除生命。
##
## @return 无返回值。
func OnSatietyDepleted() -> void:
	print("主角：我太饿了！开始掉血！")

	# 伤害入口使用稳定方法协议，同时兼容 C# 与 GDScript 生命组件。
	_health.call("TakeDamage", SATIETY_DEPLETED_DAMAGE, ELEMENT_NONE)


## 生命归零时广播玩家死亡事件。
##
## @return 无返回值。
func OnPlayerDied() -> void:
	_global_event_bus.emit_signal(PLAYER_DIED_SIGNAL)
	print("主角死亡，游戏结束！")


## 退出场景树时断开全部信号连接，避免跨场景残留回调。
##
## @return 无返回值。
func _exit_tree() -> void:
	if _satiety != null and _satiety.is_connected(DEPLETED_SIGNAL, _satiety_depleted_callable):
		_satiety.disconnect(DEPLETED_SIGNAL, _satiety_depleted_callable)

	if _health != null and _health.is_connected(DEPLETED_SIGNAL, _health_depleted_callable):
		_health.disconnect(DEPLETED_SIGNAL, _health_depleted_callable)

	if (
		_global_event_bus != null
		and _global_event_bus.is_connected(ON_PLAYER_ACQUIRED_TALENT, _absorb_talent)
	):
		_global_event_bus.disconnect(ON_PLAYER_ACQUIRED_TALENT, _absorb_talent)

	if (
		_player_level != null
		and _player_level.is_connected(&"AttributePointsGranted", Callable(self, "_on_attribute_points_granted"))
	):
		_player_level.disconnect(&"AttributePointsGranted", Callable(self, "_on_attribute_points_granted"))


## 尝试把一个完整物品堆叠加入玩家库存。
##
## @param stack 通过 Item、Amount 与 IsEmpty 属性提供数据的旧 C# 或 GDScript 物品堆叠。
## @return 库存完整接收堆叠时返回 true；容量不足或堆叠无效时返回 false。
func TryAddItemToInventory(stack: RefCounted) -> bool:
	var fields: Dictionary = _read_item_stack(stack)
	if fields.is_empty():
		return false

	# AddItem 的返回值是未放入数量；动态调用使同一路径兼容 C# 与 GDScript InventoryComponent。
	return int(_inventory.call("AddItem", fields["item"], fields["amount"])) == 0


## 读取跨语言物品堆叠的稳定字段，等价旧 C# ItemStackProtocol.TryRead。
##
## @param stack 待检查的旧 C# 或 GDScript RefCounted。
## @return 含 item 与 amount 的字典；协议缺失、空堆叠或数量非正时返回空字典。
func _read_item_stack(stack: RefCounted) -> Dictionary:
	if stack == null or not is_instance_valid(stack):
		return {}
	if not stack.has_method("SetItem") or not stack.has_method("Clear"):
		return {}

	var raw_item: Variant = stack.get("Item")
	var item: Resource = raw_item if raw_item is Resource else null
	var amount_value: Variant = stack.get("Amount")
	var amount: int = int(amount_value) if _is_number(amount_value) else 0
	var is_empty: bool = bool(stack.get("IsEmpty"))

	if is_empty or item == null or amount <= 0:
		return {}

	return {"item": item, "amount": amount}


## 判断跨语言字段是否为可参与整数运算的数值。
##
## @param value 待判断的 Variant。
## @return 整数或浮点数时返回 true。
func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
