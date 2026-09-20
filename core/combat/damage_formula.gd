extends RefCounted

## 伤害基础公式的 GDScript 生产实现，等价旧 core/combat/DamageFormula.cs。
##
## 该脚本只做纯数学计算，不依赖场景树，因此编辑器与运行时都能复用同一份实现。
## 静态函数与旧 C# 保持同名 PascalCase，方便逐项对照与后续收敛；
## 不声明 class_name，避免与仍在使用的 C# 全局类型重名。

## 伤害公式常数，等价旧 C# CombatConstants.DamageFormulaConstant。
const DAMAGE_FORMULA_CONSTANT: float = 100.0


## 根据技能威力、攻击者物攻、防御方物抗和物理穿透计算物理基础伤害。
##
## @param skill_power 技能威力，负数会按 0 处理。
## @param attacker_phys_atk 攻击者有效物理攻击，负数会按 0 处理。
## @param defender_phys_def 防御方有效计算前的物理抗性，负数会按 0 处理。
## @param physical_penetration_rate 攻击者物理穿透率，取值会限制在 0 到 1。
## @param fixed_physical_penetration 攻击者固定物理穿透，负数会按 0 处理。
## @return 返回套用物理攻防比值后的基础伤害。
static func CalculatePhysicalBaseDamage(
	skill_power: float,
	attacker_phys_atk: float,
	defender_phys_def: float,
	physical_penetration_rate: float,
	fixed_physical_penetration: float = 0.0
) -> float:
	var effective_defense: float = CalculateEffectiveResistance(
		defender_phys_def,
		physical_penetration_rate,
		fixed_physical_penetration
	)

	return _calculate_base_damage(skill_power, attacker_phys_atk, effective_defense)


## 根据技能威力、攻击者法强、防御方法抗和法术穿透计算法术基础伤害。
##
## @param skill_power 技能威力，负数会按 0 处理。
## @param attacker_mag_power 攻击者有效法术强度，负数会按 0 处理。
## @param defender_mag_resist 防御方有效计算前的法术抗性，负数会按 0 处理。
## @param magic_penetration_rate 攻击者法术穿透率，取值会限制在 0 到 1。
## @param fixed_magic_penetration 攻击者固定法术穿透，负数会按 0 处理。
## @return 返回套用法术攻防比值后的基础伤害。
static func CalculateMagicBaseDamage(
	skill_power: float,
	attacker_mag_power: float,
	defender_mag_resist: float,
	magic_penetration_rate: float,
	fixed_magic_penetration: float = 0.0
) -> float:
	var effective_resistance: float = CalculateEffectiveResistance(
		defender_mag_resist,
		magic_penetration_rate,
		fixed_magic_penetration
	)

	return _calculate_base_damage(skill_power, attacker_mag_power, effective_resistance)


## 根据原始抗性、百分比穿透和固定穿透计算参与伤害公式的有效抗性。
##
## @param raw_resistance 防御方原始抗性，负数会按 0 处理。
## @param penetration_rate 攻击者百分比穿透率，取值会限制在 0 到 1。
## @param fixed_penetration 攻击者固定穿透，负数会按 0 处理。
## @return 返回不会低于 0 的有效抗性。
static func CalculateEffectiveResistance(
	raw_resistance: float,
	penetration_rate: float,
	fixed_penetration: float
) -> float:
	var normalized_resistance: float = maxf(0.0, raw_resistance)
	var normalized_rate: float = clampf(penetration_rate, 0.0, 1.0)
	var normalized_fixed_penetration: float = maxf(0.0, fixed_penetration)

	return maxf(
		normalized_resistance * (1.0 - normalized_rate) - normalized_fixed_penetration,
		0.0
	)


## 根据闪避率和本次随机值判断是否闪避。
##
## @param evasion_rate 闪避率，取值会限制在 0 到 1。
## @param evasion_roll 本次随机值，取值会限制在 0 到 1。
## @return 触发闪避时返回 true。
static func ShouldEvade(evasion_rate: float, evasion_roll: float) -> bool:
	return clampf(evasion_roll, 0.0, 1.0) < clampf(evasion_rate, 0.0, 1.0)


## 根据暴击率和本次随机值判断是否暴击。
##
## @param crit_rate 暴击率，取值会限制在 0 到 1。
## @param crit_roll 本次随机值，取值会限制在 0 到 1。
## @return 触发暴击时返回 true。
static func ShouldCrit(crit_rate: float, crit_roll: float) -> bool:
	return clampf(crit_roll, 0.0, 1.0) < clampf(crit_rate, 0.0, 1.0)


## 计算本次伤害使用的暴击修正系数。
##
## @param is_critical 本次是否暴击。
## @param crit_damage 暴击伤害倍率，低于 1 时按 1 处理。
## @return 返回暴击或非暴击对应的倍率。
static func CalculateCriticalModifier(is_critical: bool, crit_damage: float) -> float:
	if is_critical:
		return maxf(1.0, crit_damage)
	return 1.0


## 根据配置范围和本次随机值计算随机浮动系数。
##
## @param minimum 随机浮动下限。
## @param maximum 随机浮动上限。
## @param roll 本次随机值，取值会限制在 0 到 1。
## @return 返回线性插值后的随机浮动倍率。
static func CalculateRandomVariance(minimum: float, maximum: float, roll: float) -> float:
	var lower_bound: float = minf(minimum, maximum)
	var upper_bound: float = maxf(minimum, maximum)
	var normalized_roll: float = clampf(roll, 0.0, 1.0)

	return lower_bound + (upper_bound - lower_bound) * normalized_roll


## 根据理论最终伤害和防御方当前生命计算实际扣血量。
##
## @param final_damage 理论最终伤害。
## @param defender_current_health 防御方当前生命值。
## @return 返回不会超过当前生命值的实际扣血量。
static func CalculateActualDamage(final_damage: int, defender_current_health: int) -> int:
	return mini(maxi(0, final_damage), maxi(0, defender_current_health))


## 根据实际伤害和吸血率计算恢复生命值。
##
## @param final_actual_damage 最终实际扣血量。
## @param lifesteal_rate 吸血率，取值会限制在 0 到 1。
## @return 返回取整后的吸血治疗量。
static func CalculateLifestealAmount(final_actual_damage: int, lifesteal_rate: float) -> int:
	var normalized_damage: float = maxf(0.0, float(final_actual_damage))
	var normalized_rate: float = clampf(lifesteal_rate, 0.0, 1.0)

	# 旧 C# 使用 MidpointRounding.AwayFromZero，GDScript 的 roundi 采用同一舍入规则。
	return roundi(normalized_damage * normalized_rate)


## 按攻防比值计算基础伤害，保留旧 C# 的 0 下限与公式常数。
##
## @param skill_power 技能威力。
## @param attacker_power 攻击方对应攻击属性。
## @param effective_resistance 防御方有效抗性。
## @return 返回不会低于 0 的基础伤害。
static func _calculate_base_damage(
	skill_power: float,
	attacker_power: float,
	effective_resistance: float
) -> float:
	return (
		maxf(0.0, skill_power)
		* (maxf(0.0, attacker_power) + DAMAGE_FORMULA_CONSTANT)
		/ (maxf(0.0, effective_resistance) + DAMAGE_FORMULA_CONSTANT)
	)
