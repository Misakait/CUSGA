using CUSGA.core.combat.effects;
using CUSGA.core.combat.skills;
using CUSGA.core.combat.status;
using Godot;
using System;

namespace CUSGA.core.combat.buffs;

/// <summary>
/// 运行时每段基础伤害修正状态，负责在伤害载荷创建前调整本段伤害。
/// </summary>
public sealed partial class NextAttackDamageBonusStatusInstance(
    NextAttackDamageBonusStatusData data,
    Node source,
    Node owner
) : StatusEffectInstance(data, source, owner)
{
    private readonly NextAttackDamageBonusStatusData _data = data;
    private int _remainingAttackSkillUses = Math.Max(0, data.AttackSkillUses);

    /// <summary>
    /// 获取限次模式下剩余可影响的攻击技能次数。
    /// </summary>
    public int RemainingAttackSkillUses => _remainingAttackSkillUses;

    /// <summary>
    /// 重新施加同一状态时，刷新限次状态的剩余攻击技能次数。
    /// </summary>
    /// <param name="incoming">新施加进来的同 Id 状态。</param>
    public override void OnReapplied(StatusEffectInstance incoming)
    {
        if (_data.AttackSkillUses <= 0)
        {
            return;
        }

        _remainingAttackSkillUses = Math.Max(
            _remainingAttackSkillUses,
            _data.AttackSkillUses
        );
    }

    /// <summary>
    /// 根据当前层数修正单段伤害载荷中的基础伤害。
    /// </summary>
    /// <param name="context">单段伤害修正上下文。</param>
    /// <param name="damage">当前本段基础伤害候选值。</param>
    public override void OnModifyDamageEffectSegmentDamage(
        DamageEffectSegmentContext context,
        ref int damage
    )
    {
        if (_data.FlatSegmentDamageBonusPerStack == 0)
        {
            return;
        }

        if (_data.AttackSkillUses > 0 && _remainingAttackSkillUses <= 0)
        {
            return;
        }

        damage += _data.FlatSegmentDamageBonusPerStack * CurrentStacks;
    }

    /// <summary>
    /// 攻击技能完整执行后标记限次基础伤害状态需要扣减一次。
    /// </summary>
    /// <param name="context">本次技能执行修正上下文。</param>
    public override void OnAfterSkillExecution(SkillExecutionModifierContext context)
    {
        if (_data.AttackSkillUses <= 0 || !context.IsAttackSkill)
        {
            return;
        }

        context.MarkStatusForConsumption(Id);
    }

    /// <summary>
    /// 扣减一次限次基础伤害状态，并在剩余次数归零时要求移除状态。
    /// </summary>
    /// <returns>如果剩余次数归零，返回 true；否则返回 false。</returns>
    public override bool ConsumeMarkedSkillExecutionUse()
    {
        if (_data.AttackSkillUses <= 0)
        {
            return false;
        }

        _remainingAttackSkillUses = Math.Max(0, _remainingAttackSkillUses - 1);
        return _remainingAttackSkillUses <= 0;
    }
}
