extends "res://entities/components/vital_component_base.gd"

## 生命值组件的 GDScript 生产实现，等价迁移自 HealthComponent.cs。
##
## 在数值组件之上补充伤害入口与受伤信号；生命上限的同步仍由属性组件负责，
## 伤害公式、护盾、减伤与死亡流程都不在本文件内，避免复制战斗规则。

## 受到有效伤害时发出；元素类型沿用旧 C# ElementType 的整数取值。
signal DamageTaken(amount: int, element_type: int)


## 扣除生命值并返回实际受到的伤害。
##
## @param amount 尝试造成的伤害量。
## @param element_type 伤害五行属性，取值与旧 C# ElementType 一致。
## @return 受当前生命值限制后的实际扣血量。
func TakeDamage(amount: int, element_type: int) -> int:
	var actual_damage: int = Subtract(amount)

	if actual_damage > 0:
		DamageTaken.emit(actual_damage, element_type)

	return actual_damage
