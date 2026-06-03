using Godot;
using System.Collections.Generic;
using CUSGA.core.attributes;
using CUSGA.core.combat.effects;
using CUSGA.core.combat.skills;

namespace CUSGA.core.combat.status;

public abstract partial class StatusEffectInstance : RefCounted
{
    public StatusEffectData Data { get; }

    public StringName Id => Data.Id;
    public int MaxStacks => Data.MaxStacks;
    public StackPolicy Policy => Data.Policy;
    public DurationExpirePolicy ExpirePolicy => Data.ExpirePolicy;
    public DurationTickTiming TickTiming => Data.DurationTickTiming;

    public int InitOwnerTurnDuration => Data.InitOwnerTurnDuration;
    public int InitGlobalTurnDuration => Data.InitGlobalTurnDuration;
    public int InitRoundDuration => Data.InitRoundDuration;

    public Node Source { get; }
    // 这个buff的拥有者
    public Node Owner { get; }

    public int CurrentStacks { get; private set; } = 1;

    public int OwnerTurnDuration { get; private set; }
    public int GlobalTurnDuration { get; private set; }
    public int RoundDuration { get; private set; }

    protected StatusEffectInstance(
        StatusEffectData data,
        Node source,
        Node owner
    )
    {
        Data = data;
        Source = source;
        Owner = owner;

        ResetDurations();
    }

    public bool TryIncreaseStack()
    {
        if (MaxStacks > 0 && CurrentStacks >= MaxStacks)
        {
            return false;
        }

        CurrentStacks++;
        OnStackIncreased(CurrentStacks);
        return true;
    }

    public bool TryRemoveStack()
    {
        if (CurrentStacks <= 1)
        {
            return false;
        }

        CurrentStacks--;
        OnStackRemoved(CurrentStacks);
        return true;
    }

    public void ResetDurations()
    {
        OwnerTurnDuration = InitOwnerTurnDuration;
        GlobalTurnDuration = InitGlobalTurnDuration;
        RoundDuration = InitRoundDuration;
    }

    public void AddDurationsFrom(StatusEffectInstance other)
    {
        OwnerTurnDuration += other.InitOwnerTurnDuration;
        GlobalTurnDuration += other.InitGlobalTurnDuration;
        RoundDuration += other.InitRoundDuration;
    }

    public bool TickOwnerTurn()
    {
        OnOwnerTurnStart();
        return TickOwnerTurnDuration(DurationTickTiming.Start);
    }

    public bool TickGlobalTurn(Node currentActor)
    {
        OnGlobalTurnStart(currentActor);
        return TickGlobalTurnDuration(DurationTickTiming.Start);
    }

    public bool TickRound()
    {
        OnRoundStart();
        return TickRoundDuration(DurationTickTiming.Start);
    }

    public bool TickOwnerTurnDuration(DurationTickTiming timing)
    {
        if (!ShouldTickDuration(timing) || OwnerTurnDuration <= 0)
        {
            return false;
        }

        OwnerTurnDuration--;
        return true;
    }

    public bool TickGlobalTurnDuration(DurationTickTiming timing)
    {
        if (!ShouldTickDuration(timing) || GlobalTurnDuration <= 0)
        {
            return false;
        }

        GlobalTurnDuration--;
        return true;
    }

    public bool TickRoundDuration(DurationTickTiming timing)
    {
        if (!ShouldTickDuration(timing) || RoundDuration <= 0)
        {
            return false;
        }

        RoundDuration--;
        return true;
    }

    private bool ShouldTickDuration(DurationTickTiming timing)
    {
        return TickTiming == timing;
    }

    public bool IsExpired()
    {
        if (!Data.HasFiniteDuration)
        {
            return false;
        }

        bool ownerExpired = InitOwnerTurnDuration > 0 && OwnerTurnDuration <= 0;
        bool globalExpired = InitGlobalTurnDuration > 0 && GlobalTurnDuration <= 0;
        bool roundExpired = InitRoundDuration > 0 && RoundDuration <= 0;

        return ExpirePolicy switch
        {
            DurationExpirePolicy.FirstExpired =>
                ownerExpired || globalExpired || roundExpired,

            DurationExpirePolicy.AllExpired =>
                IsConfiguredDurationExpiredOrUnused(InitOwnerTurnDuration, OwnerTurnDuration) &&
                IsConfiguredDurationExpiredOrUnused(InitGlobalTurnDuration, GlobalTurnDuration) &&
                IsConfiguredDurationExpiredOrUnused(InitRoundDuration, RoundDuration),

            _ => ownerExpired || globalExpired || roundExpired
        };
    }

    private static bool IsConfiguredDurationExpiredOrUnused(int initial, int current)
    {
        return initial <= 0 || current <= 0;
    }
    public long AppliedSequence { get; internal set; } = -1;

    public virtual int GetHookPriority(StatusHookPhase phase)
    {
        return Data.DefaultHookPriority;
    }
    public virtual void OnApply() { }
    public virtual void OnRemove() { }
    public virtual void OnReapplied(StatusEffectInstance incoming) { }

    public virtual void OnStackIncreased(int currentStacks) { }
    public virtual void OnStackRemoved(int currentStacks) { }

    public virtual void OnOwnerTurnStart() { }
    public virtual void OnGlobalTurnStart(Node currentActor) { }
    public virtual void OnRoundStart() { }

    public virtual void OnOwnerTurnEnd() { }
    public virtual void OnGlobalTurnEnd(Node currentActor) { }
    public virtual void OnRoundEnd() { }

    /// <summary>
    /// 在整张技能开始执行前调用，用于初始化技能级状态作用域。
    /// </summary>
    /// <param name="context">本次技能执行修正上下文。</param>
    public virtual void OnBeforeSkillExecution(SkillExecutionModifierContext context) { }

    /// <summary>
    /// 在整张技能全部效果执行后调用，用于标记限次状态消费。
    /// </summary>
    /// <param name="context">本次技能执行修正上下文。</param>
    public virtual void OnAfterSkillExecution(SkillExecutionModifierContext context) { }

    public virtual void OnBeforeAttributeChange(AttributeChangeContext context) { }
    public virtual void OnAfterAttributeChanged(AttributeChangeContext context) { }

    /// <summary>
    /// 在伤害效果进入段数循环前修正有效段数。
    /// </summary>
    /// <param name="context">伤害段数修正上下文。</param>
    /// <param name="hitCount">当前有效段数候选值。</param>
    public virtual void OnModifyDamageHitCount(
        DamageEffectHitCountContext context,
        ref int hitCount
    ) { }

    /// <summary>
    /// 在单段伤害创建伤害载荷前修正本段基础伤害。
    /// </summary>
    /// <param name="context">单段伤害修正上下文。</param>
    /// <param name="damage">当前本段基础伤害候选值。</param>
    public virtual void OnModifyDamageEffectSegmentDamage(
        DamageEffectSegmentContext context,
        ref int damage
    ) { }

    // 攻击方 Buff 修正
    public virtual void OnModifyOutgoingDamage(DamagePayload payload, ref float damage) { }
    // 防御方防御前 Buff 修正
    public virtual void OnModifyIncomingDamageBeforeMitigation(DamagePayload payload, ref float damage) { }
    //防御方防御后 Buff 修正
    public virtual void OnModifyIncomingDamageAfterMitigation(DamagePayload payload, ref float damage) { }
    // 扣血前最终处理
    public virtual void OnBeforeHealthDamage(DamagePayload payload, ref float damage) { }

    /// <summary>
    /// 获取状态在 UI 悬停提示中显示的运行时描述文本。
    /// </summary>
    /// <returns>优先返回状态数据配置的描述；特殊状态可重写以展示运行时数值。</returns>
    public virtual string DisplayDescription => Data.Description;

    /// <summary>
    /// 扣减一次技能级限次状态使用次数，并返回是否应移除该状态。
    /// </summary>
    /// <returns>如果状态应被移除，返回 true；否则返回 false。</returns>
    public virtual bool ConsumeMarkedSkillExecutionUse()
    {
        return true;
    }

    public virtual IEnumerable<AttributeModifier> GetAttributeModifiers()
    {
        yield break;
    }
}
