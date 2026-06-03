using Godot;
using System.Collections.Generic;

namespace CUSGA.core.combat.skills;

/// <summary>
/// 表示整张技能执行期间供状态 Hook 读取和标记消费的上下文。
/// </summary>
/// <param name="source">本次技能的施放者。</param>
/// <param name="skill">本次执行的技能数据。</param>
/// <param name="skillContext">本次技能执行上下文。</param>
/// <param name="hasDamageEffect">本次技能是否包含至少一个伤害效果。</param>
public sealed class SkillExecutionModifierContext(
    Node source,
    CombatSkillData skill,
    SkillExecutionContext skillContext,
    bool hasDamageEffect
)
{
    private readonly HashSet<StringName> _statusIdsMarkedForConsumption = [];

    /// <summary>
    /// 获取本次技能的施放者。
    /// </summary>
    public Node Source { get; } = source;

    /// <summary>
    /// 获取本次执行的技能数据。
    /// </summary>
    public CombatSkillData Skill { get; } = skill;

    /// <summary>
    /// 获取本次技能执行上下文。
    /// </summary>
    public SkillExecutionContext SkillContext { get; } = skillContext;

    /// <summary>
    /// 获取本次技能是否包含至少一个伤害效果。
    /// </summary>
    public bool HasDamageEffect { get; } = hasDamageEffect;

    /// <summary>
    /// 获取本次技能是否应视为攻击技能。
    /// </summary>
    public bool IsAttackSkill => HasDamageEffect;

    /// <summary>
    /// 获取本次技能执行后需要扣减使用次数的状态 Id 集合。
    /// </summary>
    public IReadOnlyCollection<StringName> StatusIdsMarkedForConsumption =>
        _statusIdsMarkedForConsumption;

    /// <summary>
    /// 标记指定状态在整张攻击技能完成后扣减一次使用次数。
    /// </summary>
    /// <param name="statusId">需要扣减使用次数的状态唯一标识。</param>
    public void MarkStatusForConsumption(StringName statusId)
    {
        if (statusId == default)
        {
            return;
        }

        _statusIdsMarkedForConsumption.Add(statusId);
    }
}
