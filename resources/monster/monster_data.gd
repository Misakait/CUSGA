@tool
extends Resource

## 保存怪物的初始属性、外观、掉落和战斗配置。
##
## 掉落池与技能集合分离；每个数据资源默认创建自己的空池，方便在检查器中独立配置。
## 启用工具模式使默认池在编辑器中也能创建和保存，而不只是运行游戏时出现。

## 怪物在 UI 中显示的名称。
@export var MonsterName: String = "未知怪物"

## 怪物初始属性资源；允许旧 C# StartingStats 与迁移后的 GDScript starting_stats.gd 并存。
@export var InitialAttributes: Resource

## 怪物默认的五行属性，取值与 ElementType 枚举一致。
@export var ElementalProperty: int = 0

## 怪物的外观预制体。
@export var ModelScene: PackedScene

## 怪物专属掉落池；默认独立空池，可在检查器设置抽取次数及物品权重。
@export var drop_pool: MonsterDropPool = MonsterDropPool.new()

## 怪物行为树预制体。
@export var BehaviorTreeScene: PackedScene

## 阵营，取值与 MonsterFaction 枚举一致：0=Hostile，1=PlayerSummon，2=Neutral。
@export var Faction: int = 0

## 怪物只配置战斗技能集合，玩家卡牌资源只在玩家牌组和 UI 表现边界使用。
@export var SkillSet: Resource
