using CUSGA.core.combat.status;
using Godot;

namespace CUSGA.core.combat.buffs;

/// <summary>
/// 配置用于修正伤害效果段数的状态数据。
/// </summary>
[GlobalClass]
public partial class HitCountModifierStatusData : StatusEffectData
{
    /// <summary>
    /// 每层为伤害段数提供的固定加成。
    /// </summary>
    [Export] public int FlatHitCountBonusPerStack { get; set; } = 0;

    /// <summary>
    /// 可影响的攻击技能次数；0 表示持续期间不限次数。
    /// </summary>
    [Export] public int AttackSkillUses { get; set; } = 0;

    /// <summary>
    /// 创建运行时段数修正状态实例。
    /// </summary>
    /// <param name="source">施加状态的来源节点。</param>
    /// <param name="owner">拥有状态的目标节点。</param>
    /// <returns>返回运行时状态实例。</returns>
    public override StatusEffectInstance CreateInstance(Node source, Node owner)
    {
        return new HitCountModifierStatusInstance(this, source, owner);
    }
}
