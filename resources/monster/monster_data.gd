extends Resource

## 保存怪物的初始属性、外观、掉落和战斗配置。
##
## 迁移说明：GDScript 无法继承 C# 的 MonsterData，因此生产实现改用原生 Resource 基类，
## 并保持与旧 C# 完全相同的字段名、默认值与序列化形式；旧 C# MonsterData.cs 继续作为兼容垫片保留，
## 两侧字段统一由 MonsterDataProtocol 与同名属性读取，任何一侧改名都会破坏既有 .tres 反序列化。

## 怪物在 UI 中显示的名称。
@export var MonsterName: String = "未知怪物"

## 怪物初始属性资源；允许旧 C# StartingStats 与迁移后的 GDScript starting_stats.gd 并存。
@export var InitialAttributes: Resource

## 怪物默认的五行属性，取值与 ElementType 枚举一致。
@export var ElementalProperty: int = 0

## 怪物的外观预制体。
@export var ModelScene: PackedScene

## 怪物使用的掉落表资源；随机掉落仍由资源自身的 RollLoot 协议负责。
@export var LootTable: Resource

## 怪物行为树预制体。
@export var BehaviorTreeScene: PackedScene

## 阵营，取值与 MonsterFaction 枚举一致：0=Hostile，1=PlayerSummon，2=Neutral。
@export var Faction: int = 0

## 怪物只配置战斗技能集合，玩家卡牌资源只在玩家牌组和 UI 表现边界使用。
@export var SkillSet: Resource
