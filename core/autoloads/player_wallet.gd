extends Node

## 玩家金币 Autoload 的 GDScript 并行实现，同时是「局外存档」的参与者（key = player_wallet）。
##
## 本脚本保持旧 C# PlayerWallet 的公开字段、信号和数值规则。旧 C# PlayerWallet.cs
## 继续保留为兼容垫片，生产 Autoload 通过稳定动态协议被各消费者使用。
##
## 存档为什么从 `SettingsManager` 搬到 `SaveManager`：`SettingsManager` 管的是**可丢弃的偏好**
## （操作模式、反馈强度），读坏了无痛回退默认值即可；金币是玩家资产，读坏了必须保留现场并
## 告警。两者的正确失败行为不同，混在同一个 `ConfigFile` 里会让备份与恢复策略互相牵制。
## 搬走之后本脚本不再自己写盘：`GoldChanged` 由存档层订阅，落盘时机与防抖由存档层统一决定，
## 避免「扣款成功但存档失败」这种两处状态机各自为政。

## 存档层 Autoload 路径。
##
## 用 `NodePath` + `get_node_or_null` 而不是直接写 `SaveManager.xxx`：`test_run` 环境没有
## autoload，直接引用标识符会让本脚本连同测试一起解析失败。
const SAVE_MANAGER_PATH: NodePath = ^"/root/SaveManager"

## 本参与者的存档键；发布后不可修改（改了等于玩家金币清零）。
const SAVE_KEY: String = "player_wallet"

## 本参与者的作用域字面量，与 `SaveManager.SCOPE_GLOBAL` 同值（由契约套件断言）。
const SAVE_SCOPE: String = "global"

## 金币上限，与 C# `int.MaxValue` 保持一致，避免溢出成负数。
const MaxGold: int = 2147483647

## 没有有效存档时使用的默认金币。
const DefaultGold: int = 1200

## 金币余额变化信号，参数为变化后的余额。
signal GoldChanged(gold: int)

## 当前金币余额，始终保持为非负整数。
var Gold: int = DefaultGold


## 进入场景树时把自己注册进存档层。
##
## 注册会立刻用存档内容覆盖 `Gold`，因此不需要在本方法里再读一次盘。
##
## @return 无返回值。
func _ready() -> void:
	_register_with_save_manager()


## 向存档层注册自身。
##
## @return 无返回值。
func _register_with_save_manager() -> void:
	var save_manager: Node = get_node_or_null(SAVE_MANAGER_PATH)
	if save_manager == null or not save_manager.has_method("register_participant"):
		push_error("PlayerWallet: 未找到 SaveManager，金币将不会跨运行保存。")
		return

	save_manager.call("register_participant", self)


# ── 存档参与者协议 ───────────────────────────────────────────────────────

## 返回稳定的存档键。
##
## @return `"player_wallet"`。
func save_key() -> String:
	return SAVE_KEY


## 返回本参与者的作用域。
##
## @return `"global"`。
func save_scope() -> String:
	return SAVE_SCOPE


## 返回需要触发自动存档的信号名。
##
## 只订阅 `GoldChanged`：买卖、升级扣款都经由它，是金币变化的唯一出口。
##
## @return 信号名数组。
func save_change_signals() -> Array:
	return ["GoldChanged"]


## 采集当前金币。
##
## @return `{"gold": int}`。
func capture_save_data() -> Dictionary:
	return {"gold": Gold}


## 用存档内容覆盖金币。
##
## 非法值（非数值 / 负数）回退到默认值并告警，而不是让整次读档失败：金币不是结构性数据，
## 修不好也不该连带毁掉仓库与升级等级的恢复。
##
## 结束时广播 `GoldChanged`，让 HUD 等消费方在「读档改变余额」时也能刷新；这次广播引起的
## 存档请求会被存档层在分发期间丢弃，不会造成回声落盘。
##
## @param data 本参与者的存档载荷；空字典表示「没有存档」。
## @return 恒为 true，见上面的回退说明。
func apply_save_data(data: Dictionary) -> bool:
	Gold = _sanitize_gold(data.get("gold", DefaultGold))
	GoldChanged.emit(Gold)
	return true


## 校验存档中的金币值。
##
## @param raw 存档里的原始值。
## @return 合法的非负整数余额；非数值或负数时返回 `DefaultGold` 并告警。
func _sanitize_gold(raw: Variant) -> int:
	var is_number: bool = typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT
	if not is_number:
		push_warning("PlayerWallet: 存档中的金币不是数值，已回退到默认值。")
		return DefaultGold

	var value: int = int(raw)
	if value < 0:
		push_warning("PlayerWallet: 存档中的金币为负数，已回退到默认值。")
		return DefaultGold
	return mini(MaxGold, value)


# ── 金币规则 ─────────────────────────────────────────────────────────────

## 尝试扣除指定金币。
##
## 只改内存值并广播信号；落盘由存档层按防抖统一决定。
##
## @param amount 需要扣除的正数金额。
## @return 余额足够且扣款成功时返回 true，否则余额不变并返回 false。
func TrySpend(amount: int) -> bool:
	if amount <= 0 or amount > Gold:
		return false

	Gold -= amount
	GoldChanged.emit(Gold)
	return true


## 增加金币并限制在 C# int 上限内。
##
## @param amount 需要增加的正数金额；非正数会被忽略。
## @return 无返回值。
func Add(amount: int) -> void:
	if amount <= 0:
		return

	Gold = mini(MaxGold, Gold + amount)
	GoldChanged.emit(Gold)
