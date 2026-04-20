using Godot;
using System.Collections.Generic;
using CUSGA.core.attributes;

namespace CUSGA.core.combat.status;

public abstract partial class StatusEffectInstance : RefCounted
{
    public StatusEffectData Data { get; }

    public StringName Id => Data.Id;
    public int MaxStacks => Data.MaxStacks;
    public StackPolicy Policy => Data.Policy;
    public DurationExpirePolicy ExpirePolicy => Data.ExpirePolicy;

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
        if (CurrentStacks >= MaxStacks)
            return false;

        CurrentStacks++;
        OnStackIncreased(CurrentStacks);
        return true;
    }

    public bool TryRemoveStack()
    {
        if (CurrentStacks <= 1)
            return false;

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
        if (OwnerTurnDuration <= 0)
            return false;

        OnOwnerTurnStart();
        OwnerTurnDuration--;
        return true;
    }

    public bool TickGlobalTurn(Node currentActor)
    {
        if (GlobalTurnDuration <= 0)
            return false;

        OnGlobalTurnStart(currentActor);
        GlobalTurnDuration--;
        return true;
    }

    public bool TickRound()
    {
        if (RoundDuration <= 0)
            return false;

        OnRoundStart();
        RoundDuration--;
        return true;
    }

    public bool IsExpired()
    {
        if (!Data.HasFiniteDuration)
            return false;

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

    public virtual void OnApply() { }
    public virtual void OnRemove() { }
    public virtual void OnReapplied(StatusEffectInstance incoming) { }

    public virtual void OnStackIncreased(int currentStacks) { }
    public virtual void OnStackRemoved(int currentStacks) { }

    public virtual void OnOwnerTurnStart() { }
    public virtual void OnGlobalTurnStart(Node currentActor) { }
    public virtual void OnRoundStart() { }

    public virtual void OnBeforeAttributeChange(AttributeChangeContext context) { }
    public virtual void OnAfterAttributeChanged(AttributeChangeContext context) { }

    // 攻击方 Buff 修正
    public virtual void OnModifyOutgoingDamage(DamagePayload payload, ref float damage) { }
    // 防御方防御前 Buff 修正
    public virtual void OnModifyIncomingDamageBeforeMitigation(DamagePayload payload, ref float damage) { }
    //防御方防御后 Buff 修正
    public virtual void OnModifyIncomingDamageAfterMitigation(DamagePayload payload, ref float damage) { }
    // 扣血前最终处理
    public virtual void OnBeforeHealthDamage(DamagePayload payload, ref float damage) { }

    public virtual IEnumerable<AttributeModifier> GetAttributeModifiers()
    {
        yield break;
    }
}
