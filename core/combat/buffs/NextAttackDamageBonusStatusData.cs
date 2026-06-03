using CUSGA.core.combat.status;
using Godot;

namespace CUSGA.core.combat.buffs;

/// <summary>
/// 配置用于修正接下来若干张攻击牌每段基础伤害的状态数据。
/// </summary>
[GlobalClass]
public partial class NextAttackDamageBonusStatusData : StatusEffectData
{
    /// <summary>
    /// 每层为每段基础伤害提供的固定加成。
    /// </summary>
    [Export] public int FlatSegmentDamageBonusPerStack { get; set; } = 0;

    /// <summary>
    /// 可影响的攻击技能次数；0 表示持续期间不限次数。
    /// </summary>
    [Export] public int AttackSkillUses { get; set; } = 1;

    /// <summary>
    /// 创建运行时每段基础伤害修正状态实例。
    /// </summary>
    /// <param name="source">施加状态的来源节点。</param>
    /// <param name="owner">拥有状态的目标节点。</param>
    /// <returns>返回运行时状态实例。</returns>
    public override StatusEffectInstance CreateInstance(Node source, Node owner)
    {
        return new NextAttackDamageBonusStatusInstance(this, source, owner);
    }
}
