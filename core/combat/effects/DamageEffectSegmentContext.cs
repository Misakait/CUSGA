using CUSGA.core.combat.skills;
using Godot;

namespace CUSGA.core.combat.effects;

/// <summary>
/// 提供单段伤害进入接收者前的修正上下文。
/// </summary>
/// <param name="source">本次技能的施放者。</param>
/// <param name="skillContext">本次技能执行上下文。</param>
/// <param name="effect">正在结算的伤害效果。</param>
/// <param name="target">本段伤害选中的目标。</param>
/// <param name="hitIndex">本段伤害的零基序号。</param>
/// <param name="effectiveHitCount">本次伤害效果修正后的总段数。</param>
public sealed class DamageEffectSegmentContext(
    Node source,
    SkillExecutionContext skillContext,
    DamageEffect effect,
    SkillEffectTargetSelection target,
    int hitIndex,
    int effectiveHitCount
)
{
    /// <summary>
    /// 获取本次技能的施放者。
    /// </summary>
    public Node Source { get; } = source;

    /// <summary>
    /// 获取本次技能执行上下文。
    /// </summary>
    public SkillExecutionContext SkillContext { get; } = skillContext;

    /// <summary>
    /// 获取正在结算的伤害效果。
    /// </summary>
    public DamageEffect Effect { get; } = effect;

    /// <summary>
    /// 获取本段伤害选中的目标。
    /// </summary>
    public SkillEffectTargetSelection Target { get; } = target;

    /// <summary>
    /// 获取本段伤害的零基序号。
    /// </summary>
    public int HitIndex { get; } = hitIndex;

    /// <summary>
    /// 获取本次伤害效果修正后的总段数。
    /// </summary>
    public int EffectiveHitCount { get; } = effectiveHitCount;
}
