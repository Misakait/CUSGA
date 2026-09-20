extends RefCounted

## 战斗公式共享常数的 GDScript 等价实现，等价迁移自 core/constants/CombatConstants.cs。
##
## 旧 C# 是 static class，只提供一个常量：伤害公式的全局常数 C，同时用于攻击侧分子与
## 防御侧分母。GDScript 没有静态类，这里用 RefCounted + const 表达同一取值面。
## 生产消费方 core/combat/damage_formula.gd 自带同值常量 DAMAGE_FORMULA_CONSTANT，
## 两侧一致性由 tests/godot/test_core_constants_contract.gd 逐值锁定（避免为纯常量改动战斗脚本）。

## 伤害公式中的全局常数 C；旧 C# CombatConstants.DamageFormulaConstant = 100f。
const DAMAGE_FORMULA_CONSTANT: float = 100.0
