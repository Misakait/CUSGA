extends "res://core/combat/status/status_effect_data.gd"

## 护盾状态数据的生产 GDScript 实现（旧 C# ShieldStatusData 的等价实现）。
##
## 护盾的吸收、破盾与表现逻辑由 GDScript ShieldStatusInstance 完成；本资源只提供
## 初始护盾量与继承自基类的持续/叠加配置。旧 C# 实例保留为兼容垫片。

## 运行时状态实例脚本路径；实例已是 GDScript 生产实现，旧 C# 实例保留为兼容垫片。
const INSTANCE_SCRIPT_PATH: String = "res://core/combat/buffs/shield_status_instance.gd"

## 未显式传入护盾量时使用的默认护盾值，沿用旧 C# 默认值 0。
@export var DefaultShieldAmount: float = 0.0


## 创建运行时护盾状态实例。
##
## 旧 C# 提供 (source, owner) 与 (source, owner, shieldAmount) 两个重载，这里用带默认值
## 的单方法保持两种调用都可用的语义。
##
## @param source 施加状态的来源节点。
## @param owner 拥有护盾的目标节点。
## @param shield_amount 本次实际护盾量；缺省时使用 DefaultShieldAmount。
## @return 对应的 GDScript 护盾状态实例。
func CreateInstance(source: Node, owner: Node, shield_amount: Variant = null) -> RefCounted:
	var amount: float = DefaultShieldAmount
	if shield_amount != null:
		amount = float(shield_amount)
	return load(INSTANCE_SCRIPT_PATH).new(self, source, owner, amount)
