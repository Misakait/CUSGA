extends Node

## 玩家金币 Autoload 的 GDScript 并行实现。
##
## 本脚本保持旧 C# PlayerWallet 的公开字段、信号和数值规则，
## 通过 SettingsManager 的动态方法访问持久化层。旧 C# PlayerWallet.cs
## 继续保留为兼容垫片，生产 Autoload 通过稳定动态协议被各消费者使用。

## 本地设置文件中的分组名，必须与旧 C# 存档键保持一致。
const SettingsSection: String = "player"

## 本地设置文件中的金币键名，发布后不可随意修改。
const SettingsKey: String = "gold"

## 没有有效存档时使用的默认金币。
const DefaultGold: int = 1200

## 当前开发阶段是否跨运行保存玩家数据；必须与 PlayerDataPolicy.cs 同步。
const PersistAcrossRuns: bool = false

## 金币余额变化信号，参数为变化后的余额。
signal GoldChanged(gold: int)

## 当前金币余额，始终保持为非负整数。
var Gold: int = DefaultGold

## SettingsManager Autoload 缓存；缺失时仅影响跨运行保存，不阻断本次运行。
var _settings_manager: Node = null


## 初始化设置服务并读取已保存金币。
## @return void。
func _ready() -> void:
	_settings_manager = get_node_or_null("/root/SettingsManager")
	if _settings_manager == null:
		push_error("PlayerWallet: 未找到 SettingsManager，金币将只在本次运行内有效。")

	if not PersistAcrossRuns:
		_clear_stored_value()

	Gold = _read_stored_gold()


## 尝试扣除指定金币。
## @param amount 需要扣除的正数金额。
## @return 余额足够且扣款成功时返回 true，否则余额不变并返回 false。
func TrySpend(amount: int) -> bool:
	if amount <= 0 or amount > Gold:
		return false

	Gold -= amount
	_persist_gold()
	GoldChanged.emit(Gold)
	return true


## 增加金币并限制在 C# int 上限内。
## @param amount 需要增加的正数金额；非正数会被忽略。
## @return void。
func Add(amount: int) -> void:
	if amount <= 0:
		return

	Gold = mini(2147483647, Gold + amount)
	_persist_gold()
	GoldChanged.emit(Gold)


## 从 SettingsManager 读取并校验金币。
## @return 非负整数存档值；缺失、类型错误或负数时返回 DefaultGold。
func _read_stored_gold() -> int:
	if not PersistAcrossRuns or _settings_manager == null:
		return DefaultGold
	if not _settings_manager.has_method("get_setting"):
		return DefaultGold

	var stored: Variant = _settings_manager.call("get_setting", SettingsSection, SettingsKey, DefaultGold)
	if not (stored is int or stored is float):
		push_warning("PlayerWallet: 存档中的金币不是数值，已回退到默认值。")
		return DefaultGold
	var value: int = int(stored)
	if value < 0:
		push_warning("PlayerWallet: 存档中的金币为负数，已回退到默认值。")
		return DefaultGold
	return value


## 将当前金币写回 SettingsManager。
## 失败只记录警告，内存余额仍然有效。
func _persist_gold() -> void:
	if not PersistAcrossRuns or _settings_manager == null:
		return
	if not _settings_manager.has_method("set_setting"):
		push_warning("PlayerWallet: SettingsManager 缺少 set_setting，金币未持久化。")
		return
	var saved: Variant = _settings_manager.call("set_setting", SettingsSection, SettingsKey, Gold)
	if not (saved is bool) or not bool(saved):
		push_warning("PlayerWallet: 金币未能写入本地设置文件，本次运行内仍然有效。")


## 清理开发期遗留的金币存档。
func _clear_stored_value() -> void:
	if _settings_manager != null and _settings_manager.has_method("erase_setting"):
		_settings_manager.call("erase_setting", SettingsSection, SettingsKey)
