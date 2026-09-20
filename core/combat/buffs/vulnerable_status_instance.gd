extends "res://core/combat/status/status_effect_instance.gd"

## 脆弱状态实例的生产 GDScript 实现，等价迁移自 C# VulnerableStatusInstance。
##
## 保持旧 C# 的既有行为：只对物理伤害生效，且在减伤前把伤害乘以 1.5，
## 让“增伤 +50%”先于防御减伤参与结算。脚本不声明 class_name，避免与 C# 全局类型重名。

## 物理伤害枚举整数（DamageType.Physical），与旧 C# 比较逐字一致。
const DAMAGE_TYPE_PHYSICAL: int = 0

## 伤害载荷上的伤害类型字段名。
const FIELD_DAMAGE_TYPE: StringName = &"Type"

## 脆弱增伤倍率，与旧 C# 硬编码值逐字一致。
const VULNERABLE_DAMAGE_MULTIPLIER: float = 1.5


## 防御方减伤前修正：物理伤害按 1.5 倍放大。
##
## @param payload 本次伤害载荷（旧 C# DamagePayload）。
## @param damage 进入修正前的伤害值。
## @return 修正后的伤害值；非物理伤害原样返回。
func OnModifyIncomingDamageBeforeMitigation(payload: Variant, damage: float) -> float:
	if _field_int(payload, FIELD_DAMAGE_TYPE) != DAMAGE_TYPE_PHYSICAL:
		return damage

	return damage * VULNERABLE_DAMAGE_MULTIPLIER
