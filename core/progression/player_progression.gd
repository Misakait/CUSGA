extends Node

## 玩家容量升级 Autoload 的 GDScript 并行实现，同时是「局外存档」的参与者
## （key = player_progression）。
##
## 仓库容量和带入栏规则集中在此脚本，钱包与仓库只通过 Gold/TrySpend/Add、
## SetCapacity 等稳定方法协议访问。旧 PlayerProgression.cs 仍保留为兼容垫片，
## 生产 Autoload 通过本脚本接入钱包与仓库。
##
## 存档为什么从 `SettingsManager` 搬到 `SaveManager`：升级等级是玩家花金币买来的资产，
## 读坏了必须保留现场并告警，而 `SettingsManager` 的定位是「可丢弃偏好」。搬走之后本脚本
## 只在内存里维护等级，落盘交给存档层按 `UpgradeChanged` 统一防抖处理。

## 存档层 Autoload 路径。
##
## 用 `NodePath` + `get_node_or_null` 而不是直接写 `SaveManager.xxx`：`test_run` 环境没有
## autoload，直接引用标识符会让本脚本连同测试一起解析失败。
const SAVE_MANAGER_PATH: NodePath = ^"/root/SaveManager"

## 钱包 Autoload 路径。
const WALLET_PATH: NodePath = ^"/root/PlayerWallet"

## 全局仓库 Autoload 路径。
const WAREHOUSE_PATH: NodePath = ^"/root/GlobalWarehouse"

## 本参与者的存档键；发布后不可修改（改了等于玩家升级等级清零）。
const SAVE_KEY: String = "player_progression"

## 本参与者的作用域字面量，与 `SaveManager.SCOPE_GLOBAL` 同值（由契约套件断言）。
const SAVE_SCOPE: String = "global"

## 仓库容量升级档位在存档中的键名。
const WarehouseLevelKey: String = "warehouse_level"

## 带入栏升级档位在存档中的键名。
const CarryLevelKey: String = "carry_level"

## 仓库初始槽位数。
const WarehouseBaseValue: int = 27
## 仓库每级增加的槽位数。
const WarehouseValuePerLevel: int = 9
## 仓库升级等级上限。
const WarehouseMaxLevel: int = 3
## 带入栏初始数量。
const CarryBaseValue: int = 5
## 带入栏每级增加的数量。
const CarryValuePerLevel: int = 1
## 带入栏升级等级上限。
const CarryMaxLevel: int = 5

## 仓库各级升级费用，索引为升级前等级。
const WarehouseCosts: Array = [300, 600, 1000]
## 带入栏各级升级费用，索引为升级前等级。
const CarryCosts: Array = [200, 350, 550, 800, 1100]

## 升级成功信号，参数为升级项名称和升级后的实际数值。
signal UpgradeChanged(kind: String, value: int)

## 钱包动态节点，使用 Gold/TrySpend/Add 协议。
var _wallet = null
## 仓库动态节点，使用 SetCapacity 协议。
var _warehouse = null
## 两个升级项的当前等级，索引 0=仓库，1=带入栏。
var _levels: Array[int] = [0, 0]


## 初始化依赖、注册存档参与者，并把等级同步到仓库容量。
##
## 顺序是刻意的：必须先解析 `_warehouse` 再注册，因为注册会**同步**应用存档，而应用的
## 最后一步就是把等级换算成仓库容量；仓库还没解析出来时扩容会静默不生效，表现为
## 「升级等级存下来了，但重开游戏仓库还是 27 格」。
##
## @return 无返回值。
func _ready() -> void:
	_wallet = get_node_or_null(WALLET_PATH)
	_warehouse = get_node_or_null(WAREHOUSE_PATH)
	if _wallet == null:
		push_error("PlayerProgression: 未找到 PlayerWallet，升级将无法扣款。")
	if _warehouse == null:
		push_error("PlayerProgression: 未找到 GlobalWarehouse，仓库容量升级不会生效。")

	_register_with_save_manager()


## 向存档层注册自身。
##
## @return 无返回值。
func _register_with_save_manager() -> void:
	var save_manager: Node = get_node_or_null(SAVE_MANAGER_PATH)
	if save_manager == null or not save_manager.has_method("register_participant"):
		push_error("PlayerProgression: 未找到 SaveManager，升级等级将不会跨运行保存。")
		return

	save_manager.call("register_participant", self)


# ── 存档参与者协议 ───────────────────────────────────────────────────────

## 返回稳定的存档键。
##
## @return `"player_progression"`。
func save_key() -> String:
	return SAVE_KEY


## 返回本参与者的作用域。
##
## @return `"global"`。
func save_scope() -> String:
	return SAVE_SCOPE


## 返回需要触发自动存档的信号名。
##
## 只订阅 `UpgradeChanged`：它是升级成功后的唯一出口，且发射时等级已经落定，采集到的
## 一定是新等级。
##
## @return 信号名数组。
func save_change_signals() -> Array:
	return ["UpgradeChanged"]


## 采集两个升级项的当前等级。
##
## 采集的是**收窄后**的等级（`GetLevel` 会 clamp），保证「存档里的等级一定合法」这条不变量，
## 避免越界值在文件里越滚越大。
##
## @return `{"warehouse_level": int, "carry_level": int}`。
func capture_save_data() -> Dictionary:
	return {
		WarehouseLevelKey: GetWarehouseLevel(),
		CarryLevelKey: GetCarryLevel(),
	}


## 用存档内容覆盖升级等级，并把新等级同步到仓库容量。
##
## 非法值（非数值 / 越界）按收窄处理而不是让整次读档失败：等级有明确的合法区间，
## 收窄是唯一合理的解释，且收窄结果会被重新采集回存档，不会每次读档都重复收窄。
##
## @param data 本参与者的存档载荷；空字典表示「没有存档」，此时回到 0 级。
## @return 恒为 true，见上面的收窄说明。
func apply_save_data(data: Dictionary) -> bool:
	_levels[0] = _sanitize_level(0, data.get(WarehouseLevelKey, 0))
	_levels[1] = _sanitize_level(1, data.get(CarryLevelKey, 0))
	_apply_warehouse_capacity()
	UpgradeChanged.emit(_kind_name(0), _get_value(0, _levels[0]))
	return true


## 校验存档中的等级值。
##
## @param kind 0 表示仓库，1 表示带入栏。
## @param raw 存档里的原始值。
## @return 收窄到合法区间的等级；非数值时返回 0 并告警。
func _sanitize_level(kind: int, raw: Variant) -> int:
	if not (typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT):
		push_warning(
			"PlayerProgression: 存档中的 %s 不是数值，已回退到 0 级。" % _level_key(kind)
		)
		return 0

	var value: int = int(raw)
	var clamped: int = _clamp_level(kind, value)
	if clamped != value:
		push_warning(
			"PlayerProgression: 存档中的 %s 为 %d，已收窄到 %d。"
			% [_level_key(kind), value, clamped]
		)
	return clamped


# ── 公开查询面 ───────────────────────────────────────────────────────────

## 读取仓库容量等级。
## @return 当前仓库等级。
func GetWarehouseLevel() -> int:
	return GetLevel(0)

## 读取当前仓库槽位数。
## @return 当前仓库容量。
func GetWarehouseCapacity() -> int:
	return _get_value(0, GetWarehouseLevel())

## 读取仓库下一级升级费用。
## @return 升级费用；满级时为 0。
func GetWarehouseNextCost() -> int:
	return _get_cost(0, GetWarehouseLevel())

## 判断仓库是否满级。
## @return 满级时返回 true。
func IsWarehouseMaxLevel() -> bool:
	return _is_max_level(0, GetWarehouseLevel())

## 尝试升级仓库容量。
## @return 扣款并升级成功时返回 true。
func TryUpgradeWarehouse() -> bool:
	return _try_upgrade(0)

## 读取带入栏等级。
## @return 当前带入栏等级。
func GetCarryLevel() -> int:
	return GetLevel(1)

## 读取当前带入栏数量。
## @return 当前可用带入栏数量。
func GetCarrySlotCount() -> int:
	return _get_value(1, GetCarryLevel())

## 读取带入栏下一级升级费用。
## @return 升级费用；满级时为 0。
func GetCarryNextCost() -> int:
	return _get_cost(1, GetCarryLevel())

## 判断带入栏是否满级。
## @return 满级时返回 true。
func IsCarryMaxLevel() -> bool:
	return _is_max_level(1, GetCarryLevel())

## 尝试升级带入栏。
## @return 扣款并升级成功时返回 true。
func TryUpgradeCarrySlots() -> bool:
	return _try_upgrade(1)

## 读取指定升级项等级。
## @param kind 0 表示仓库，1 表示带入栏。
## @return 当前等级；未知项目回退为 0。
func GetLevel(kind: int) -> int:
	if kind < 0 or kind >= _levels.size():
		return 0
	return _clamp_level(kind, _levels[kind])


# ── 内部规则 ─────────────────────────────────────────────────────────────

## 执行一次升级，固定遵循先校验、再扣款、最后改状态。
##
## 扣款成功后才改等级：反过来的话扣款失败会留下「等级涨了但没付钱」的状态。
## 落盘不在这里做——`UpgradeChanged` 与钱包的 `GoldChanged` 都由存档层订阅并防抖合并，
## 因此一次升级只会产生一次磁盘写入。
##
## @param kind 0 表示仓库，1 表示带入栏。
## @return 升级成功时返回 true。
func _try_upgrade(kind: int) -> bool:
	var level: int = GetLevel(kind)
	if _is_max_level(kind, level):
		return false
	var cost: int = _get_cost(kind, level)
	if cost <= 0:
		push_error("PlayerProgression: 无效升级项目或费用表。")
		return false
	if _wallet == null or not (_wallet is Object) or not (_wallet as Object).has_method("TrySpend"):
		return false
	if not bool((_wallet as Object).call("TrySpend", cost)):
		return false
	_levels[kind] = level + 1
	_apply_warehouse_capacity()
	UpgradeChanged.emit(_kind_name(kind), _get_value(kind, _levels[kind]))
	return true


## 将仓库容量同步到全局仓库。
##
## 依赖 `SetCapacity` 的「只增不减」语义：仓库存档可能在升级等级之前就水合了槽位，
## 这里只做扩容，绝不回收槽位，否则玩家已经放进高序号槽位的物品会变成「存在但看不见」。
##
## @return 无返回值。
func _apply_warehouse_capacity() -> void:
	if _warehouse == null or not (_warehouse is Object):
		return
	if not (_warehouse as Object).has_method("SetCapacity"):
		return
	(_warehouse as Object).call("SetCapacity", GetWarehouseCapacity())


## 将等级收窄到合法范围。
func _clamp_level(kind: int, level: int) -> int:
	return clampi(level, 0, _get_max_level(kind))

## 读取升级上限。
func _get_max_level(kind: int) -> int:
	return WarehouseMaxLevel if kind == 0 else CarryMaxLevel if kind == 1 else 0

## 计算等级对应的实际数值。
func _get_value(kind: int, level: int) -> int:
	var clamped: int = _clamp_level(kind, level)
	if kind == 0:
		return WarehouseBaseValue + WarehouseValuePerLevel * clamped
	if kind == 1:
		return CarryBaseValue + CarryValuePerLevel * clamped
	return 0

## 判断等级是否满级。
func _is_max_level(kind: int, level: int) -> bool:
	return _clamp_level(kind, level) >= _get_max_level(kind)

## 读取下一级费用。
func _get_cost(kind: int, level: int) -> int:
	var clamped: int = _clamp_level(kind, level)
	if _is_max_level(kind, clamped):
		return 0
	var costs: Array = WarehouseCosts if kind == 0 else CarryCosts if kind == 1 else []
	return int(costs[clamped]) if clamped < costs.size() else 0

## 返回稳定的升级项名称。
func _kind_name(kind: int) -> String:
	return "warehouse_capacity" if kind == 0 else "carry_slots" if kind == 1 else "unknown"

## 返回稳定的升级存档键。
func _level_key(kind: int) -> String:
	return WarehouseLevelKey if kind == 0 else CarryLevelKey if kind == 1 else "unknown"
