using CUSGA.core.combat.skills;
using Godot;

namespace CUSGA.core.combat.effects;

/// <summary>
/// 提供伤害段数修正 Hook 所需的技能和伤害效果上下文。
/// </summary>
/// <param name="source">本次技能的施放者。</param>
/// <param name="skillContext">本次技能执行上下文。</param>
/// <param name="effect">正在计算段数的伤害效果。</param>
/// <param name="baseHitCount">伤害效果资源上配置的原始段数。</param>
public sealed class DamageEffectHitCountContext(
    Node source,
    SkillExecutionContext skillContext,
    DamageEffect effect,
    int baseHitCount
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
    /// 获取正在计算段数的伤害效果。
    /// </summary>
    public DamageEffect Effect { get; } = effect;

    /// <summary>
    /// 获取伤害效果资源上配置的原始段数。
    /// </summary>
    public int BaseHitCount { get; } = baseHitCount;
}
