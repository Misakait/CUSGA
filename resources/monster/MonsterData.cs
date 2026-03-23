using Godot;
using CUSGA.resources.loot;
using CUSGA.core.constants;
using CUSGA.entities.components;
using CUSGA.resources.stats; // 引用掉落表 Resource

namespace CUSGA.resources.monsters;

// 定义派系：决定谁打谁
public enum MonsterFaction { Hostile, PlayerSummon, Neutral }

[GlobalClass]
public partial class MonsterData : Resource
{
	[Export] public string MonsterName { get; set; } = "未知怪物";
	[Export] public StartingStats InitialAttributes { get; set; }
	// 怪物默认的五行属性
	[Export] public ElementType ElementalProperty { get; set; } = ElementType.None;
	// 怪物的外观预制体
	[Export] public PackedScene ModelScene { get; set; }
	[Export] public LootTable LootTable { get; set; }
	[Export] public PackedScene BehaviorTreeScene { get; set; }
	[Export] public MonsterFaction Faction { get; set; }
	[Export] public int MaxHealth { get; set; }
}
