extends Node

## 玩家容量升级 Autoload 的 GDScript 并行实现。
##
## 仓库容量和带入栏规则集中在此脚本，钱包与仓库只通过 Gold/TrySpend/Add、
## SetCapacity 等稳定方法协议访问。旧 PlayerProgression.cs 仍保留为兼容垫片，
## 生产 Autoload 通过本脚本接入旧 C# 钱包与仓库。

## 玩家设置文件中升级数据所属的分组。
const SettingsSection: String = "player"

## 仓库容量与带入栏升级存档键。
const WarehouseLevelKey: String = "warehouse_level"
const CarryLevelKey: String = "carry_level"

## 开发期不跨运行保存，必须与 PlayerDataPolicy.cs 以及 player_wallet.gd 同步。
const PersistAcrossRuns: bool = false

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

## SettingsManager 动态节点缓存。
var _settings_manager = null
## 钱包动态节点，使用 Gold/TrySpend/Add 协议。
var _wallet = null
## 仓库动态节点，使用 SetCapacity 协议。
var _warehouse = null
## 两个升级项的当前等级，索引 0=仓库，1=带入栏。
var _levels: Array[int] = [0, 0]


## 初始化依赖并读取升级等级。
## @return void。
func _ready() -> void:
	_settings_manager = get_node_or_null("/root/SettingsManager")
	_wallet = get_node_or_null("/root/PlayerWallet")
	_warehouse = get_node_or_null("/root/GlobalWarehouse")
	if _settings_manager == null:
		push_error("PlayerProgression: 未找到 SettingsManager，升级等级将只在本次运行内有效。")
	if _wallet == null:
		push_error("PlayerProgression: 未找到 PlayerWallet，升级将无法扣款。")
	if _warehouse == null:
		push_error("PlayerProgression: 未找到 GlobalWarehouse，仓库容量升级不会生效。")
	if not PersistAcrossRuns:
		_clear_stored_levels()
	_levels[0] = _read_level(0, WarehouseLevelKey)
	_levels[1] = _read_level(1, CarryLevelKey)
	_apply_warehouse_capacity()


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


## 执行一次升级，固定遵循先校验、再扣款、最后改状态。
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
	_save_level(kind, _levels[kind])
	_apply_warehouse_capacity()
	UpgradeChanged.emit(_kind_name(kind), _get_value(kind, _levels[kind]))
	return true


## 将仓库容量同步到全局仓库。
func _apply_warehouse_capacity() -> void:
	if _warehouse == null or not (_warehouse is Object):
		return
	if not (_warehouse as Object).has_method("SetCapacity"):
		return
	(_warehouse as Object).call("SetCapacity", GetWarehouseCapacity())


## 读取并校验存档等级。
## @param kind 升级项目编号。
## @param key 存档键。
## @return 收窄到合法范围的等级。
func _read_level(kind: int, key: String) -> int:
	if not PersistAcrossRuns or _settings_manager == null or not (_settings_manager is Object):
		return 0
	if not (_settings_manager as Object).has_method("get_setting"):
		return 0
	var stored: Variant = (_settings_manager as Object).call("get_setting", SettingsSection, key, 0)
	if not (stored is int or stored is float):
		push_warning("PlayerProgression: 存档中的 %s 不是数值，已回退到 0 级。" % key)
		return 0
	var raw: int = int(stored)
	var clamped: int = _clamp_level(kind, raw)
	if clamped != raw:
		push_warning("PlayerProgression: 存档中的 %s 为 %d，已收窄到 %d。" % [key, raw, clamped])
	return clamped


## 保存一个升级等级。
## @param kind 升级项目编号。
## @param level 要保存的等级。
func _save_level(kind: int, level: int) -> void:
	if not PersistAcrossRuns or _settings_manager == null or not (_settings_manager is Object):
		return
	if not (_settings_manager as Object).has_method("set_setting"):
		return
	var saved: Variant = (_settings_manager as Object).call("set_setting", SettingsSection, _level_key(kind), level)
	if not (saved is bool) or not bool(saved):
		push_warning("PlayerProgression: %s 未能写入本地设置文件，本次运行内仍然有效。" % _level_key(kind))


## 清理开发期等级存档。
func _clear_stored_levels() -> void:
	if _settings_manager == null or not (_settings_manager is Object):
		return
	if not (_settings_manager as Object).has_method("erase_setting"):
		return
	(_settings_manager as Object).call("erase_setting", SettingsSection, WarehouseLevelKey)
	(_settings_manager as Object).call("erase_setting", SettingsSection, CarryLevelKey)


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
