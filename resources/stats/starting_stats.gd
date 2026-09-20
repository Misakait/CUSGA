extends Resource

## 角色或怪物进入战斗时使用的战斗初始属性配置。
##
## 字段名刻意保留 C# Resource 的 PascalCase 形式，确保已有 .tres/.tscn
## 序列化值可以在迁移期间原样读取。旧 StartingStats.cs 仍可作为兼容输入。

## 基础物理攻击，默认值沿用旧数值体系的基准。
@export var BasePhysAtk: float = 100.0
## 每级物理攻击成长值。
@export var PhysAtkGrowth: float = 25.0
## 基础物理抗性。
@export var BasePhysDef: float = 100.0
## 每级物理抗性成长值。
@export var PhysDefGrowth: float = 20.0
## 基础法术强度。
@export var BaseMagPower: float = 100.0
## 每级法术强度成长值。
@export var MagPowerGrowth: float = 30.0
## 基础法术抗性。
@export var BaseMagResist: float = 100.0
## 每级法术抗性成长值。
@export var MagResistGrowth: float = 20.0
## 基础速度。
@export var BaseSpeed: float = 100.0
## 每级速度成长值。
@export var SpeedGrowth: float = 5.0
## 基础生命上限。
@export var BaseMaxHealth: float = 1000.0
## 每级生命上限成长值。
@export var MaxHealthGrowth: float = 0.0
## 基础能量上限。
@export var BaseMaxEnergy: float = 100.0
## 每级能量上限成长值。
@export var MaxEnergyGrowth: float = 0.0
## 基础固定物理穿透。
@export var BaseFixedPhysPenetration: float = 0.0
## 每级固定物理穿透成长值。
@export var FixedPhysPenetrationGrowth: float = 0.0
## 基础物理穿透率。
@export var BasePhysPenetrationRate: float = 0.0
## 每级物理穿透率成长值。
@export var PhysPenetrationRateGrowth: float = 0.0
## 基础固定法术穿透。
@export var BaseFixedMagicPenetration: float = 0.0
## 每级固定法术穿透成长值。
@export var FixedMagicPenetrationGrowth: float = 0.0
## 基础法术穿透率。
@export var BaseMagicPenetrationRate: float = 0.0
## 每级法术穿透率成长值。
@export var MagicPenetrationRateGrowth: float = 0.0
## 基础暴击率。
@export var BaseCritRate: float = 0.0
## 每级暴击率成长值。
@export var CritRateGrowth: float = 0.0
## 基础暴击伤害倍率。
@export var BaseCritDamage: float = 1.5
## 每级暴击伤害倍率成长值。
@export var CritDamageGrowth: float = 0.0
## 基础闪避率。
@export var BaseEvasionRate: float = 0.0
## 每级闪避率成长值。
@export var EvasionRateGrowth: float = 0.0
## 基础吸血率。
@export var BaseLifestealRate: float = 0.0
## 每级吸血率成长值。
@export var LifestealRateGrowth: float = 0.0
