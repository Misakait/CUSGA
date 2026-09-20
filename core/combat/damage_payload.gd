extends RefCounted

## 伤害载荷的生产 GDScript 实现，等价迁移自 core/combat/DamagePayload.cs。
##
## 载荷是伤害管线的跨语言信封：由伤害效果/灼烧状态构造，交给目标上的伤害接收组件结算，
## 结算过程中由状态 Hook 写入护盾吸收与单次扣血上限。字段名、方法名与默认值必须与旧 C#
## 逐字一致，因为读取方既有 GDScript 组件（按字段协议读 Source / Target / Damage /
## Type / Element / DamageModifiers 与三个结算元数据转发字段），也有仍在使用的 C# 垫片。
##
## 旧 C# 的 `ResolutionTrace` 是纯 CLR 类，GDScript 既读不到也写不到；本实现把那三个数值
## 直接落在载荷字段上，对外仍以 `RecordShieldAbsorption` / `RecordDamageCap` 方法协议写入、
## 以只读属性协议读取，因此两种载荷实现的行为完全等价。
## 不声明 class_name，避免与仍在使用的 C# 全局类型重名。

## 伤害修饰位标记，取值与旧 C# DamageModifierFlags 逐字一致。
const MODIFIER_NONE: int = 0
const MODIFIER_EVASION: int = 1
const MODIFIER_CRITICAL: int = 2
const MODIFIER_RANDOM_VARIANCE: int = 4
const MODIFIER_LIFESTEAL: int = 8
## 普通直接攻击默认启用的修饰集合（Evasion | Critical | RandomVariance | Lifesteal）。
const MODIFIER_DEFAULT_COMBAT: int = (
	MODIFIER_EVASION | MODIFIER_CRITICAL | MODIFIER_RANDOM_VARIANCE | MODIFIER_LIFESTEAL
)

## 伤害基础公式类型，取值与旧 C# DamageType 逐字一致。
const DAMAGE_TYPE_PHYSICAL: int = 0
const DAMAGE_TYPE_MAGIC: int = 1
const DAMAGE_TYPE_REAL: int = 2

## 五行属性取值，与旧 C# ElementType 逐字一致，仅用于协议与日志文本。
const ELEMENT_NONE: int = 0
const ELEMENT_WOOD: int = 1
const ELEMENT_METAL: int = 2
const ELEMENT_WATER: int = 3
const ELEMENT_EARTH: int = 4
const ELEMENT_FIRE: int = 5

## 造成伤害的来源节点。
var Source: Node = null
## 接收伤害的目标节点。
var Target: Node = null
## 伤害类型，决定基础伤害是否经过物理、防御或真实伤害公式。
var Type: int = DAMAGE_TYPE_PHYSICAL
## 伤害基础数值。
var Damage: int = 0
## 伤害五行属性。
var Element: int = ELEMENT_NONE
## 本次伤害启用的直接攻击修饰集合，沿用旧 C# 默认值 DefaultCombat。
var DamageModifiers: int = MODIFIER_DEFAULT_COMBAT
## 标记本次伤害是否属于额外伤害，沿用旧 C# 默认值 false。
var IsExtraDamage: bool = false
## 本段伤害在所属伤害效果内的从零开始索引，沿用旧 C# 默认值 0。
var HitIndex: int = 0
## 所属伤害效果本次实际执行的总段数，沿用旧 C# 默认值 1。
var HitCount: int = 1
## 目标在技能目标选择中的角色枚举整数，沿用旧 C# 默认值 0（主目标）。
var TargetRoleId: int = 0

## 本次伤害被护盾实际吸收的总量。
var _shield_absorbed_damage: int = 0
## 本次结算是否耗尽了参与吸收的护盾。
var _shield_was_broken: bool = false
## 本次伤害因单次伤害上限而被削减的总量。
var _capped_damage: int = 0


## 获取本次伤害被护盾实际吸收的总量。
##
## 旧 C# 由 ResolutionTrace 提供同一数值，这里直接读载荷字段，字段名与旧 C# 转发属性一致。
##
## @return 护盾本次吸收的总伤害（非负整数）。
var ShieldAbsorbedDamage: int:
	get:
		return _shield_absorbed_damage


## 获取本次结算是否耗尽了参与吸收的护盾。
##
## @return 护盾被击破时返回 true。
var ShieldWasBroken: bool:
	get:
		return _shield_was_broken


## 获取本次伤害因单次伤害上限而被削减的总量。
##
## @return 被上限削掉的伤害总量（非负整数）。
var CappedDamage: int:
	get:
		return _capped_damage


## 判断本次伤害是否启用指定修饰。
##
## @param modifier 需要判断的伤害修饰位标记。
## @return 启用该修饰时返回 true；标记为 None 时恒为 false。
func HasDamageModifier(modifier: int) -> bool:
	return modifier != MODIFIER_NONE and (DamageModifiers & modifier) == modifier


## 记录护盾吸收结果。
##
## 旧 C# 语义：先按四舍五入把浮点吸收量规整为非负整数，吸收量不大于 0 时整条记录被忽略
## （既不累加吸收值，也不更新击破标记）；击破标记只做或运算，不因后续未击破而回退。
##
## @param absorbed_damage 护盾本次实际吸收的伤害（浮点）。
## @param was_broken 护盾是否在本次吸收后耗尽。
## @return 无返回值。
func RecordShieldAbsorption(absorbed_damage: float, was_broken: bool) -> void:
	var normalized_absorption: int = maxi(0, int(round(absorbed_damage)))
	if normalized_absorption <= 0:
		return

	_shield_absorbed_damage += normalized_absorption
	_shield_was_broken = _shield_was_broken or was_broken


## 记录单次伤害上限削减的伤害量。
##
## 旧 C# 语义：按四舍五入规整为非负整数后累加，不设忽略分支。
##
## @param reduced_damage 因为上限而未进入后续结算的伤害量（浮点）。
## @return 无返回值。
func RecordDamageCap(reduced_damage: float) -> void:
	_capped_damage += maxi(0, int(round(reduced_damage)))
