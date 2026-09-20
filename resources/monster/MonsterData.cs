using Godot;
using Godot.Collections;
using CUSGA.core.constants;
using CUSGA.resources.monster;
using CUSGA.resources.stats;

namespace CUSGA.resources.monsters;

public enum MonsterFaction { Hostile, PlayerSummon, Neutral }

/// <summary>
/// 保存怪物的初始属性、外观、掉落和战斗配置。
/// </summary>
[GlobalClass]
public partial class MonsterData : Resource
{
    [Export] public string MonsterName { get; set; } = "未知怪物";
    // 资源字段允许旧 C# StartingStats 与迁移后的 GDScript starting_stats.gd 并存。
    [Export] public Resource InitialAttributes { get; set; } = new StartingStats();
    // 怪物默认的五行属性
    [Export] public ElementType ElementalProperty { get; set; } = ElementType.None;
    // 怪物的外观预制体
    [Export] public PackedScene ModelScene { get; set; }
    /// <summary>
    /// 获取或设置怪物使用的掉落表资源。
    /// </summary>
    /// <remarks>
    /// 使用通用 Resource 允许生产 GDScript LootTable 与旧 C# LootTable 在迁移期并存；
    /// 随机掉落仍由资源自身的 RollLoot 协议负责。
    /// </remarks>
    [Export] public Resource LootTable { get; set; }
    [Export] public PackedScene BehaviorTreeScene { get; set; }
    [Export] public MonsterFaction Faction { get; set; }

    // 怪物只配置战斗技能集合，玩家卡牌资源只在玩家牌组和 UI 表现边界使用。
    // 使用通用 Resource 允许 GDScript MonsterSkillSetData 在迁移期间被场景序列化，
    // 同时保留 MonsterSkillSetData 作为 C# 兼容实现供旧测试和调用方继续使用。
    [Export] public Resource SkillSet { get; set; }
}
