using Godot;

namespace CUSGA.core.combat;

public enum StackPolicy
{
    ResetDuration,
    AddDuration,
    AddEffect
}

public abstract class StatusEffect
{
    public abstract StringName Id { get; }
    public Node Source { get; internal set; }
    public Node Owner { get; internal set; }

    public virtual int MaxStacks => 1;
    public virtual StackPolicy Policy => StackPolicy.ResetDuration;
    public virtual bool IsAllPhase => false;

    public virtual int InitRoundDuration => 0;
    public virtual int InitPhaseDuration => 0;

    public int CurrentStacks { get; set; } = 1;
    public int RoundDuration { get; set; }
    public int PhaseDuration { get; set; }

    public StatusEffect(Node source)
    {
        Source = source;
        RoundDuration = InitRoundDuration;
        PhaseDuration = InitPhaseDuration;
    }

    public virtual void OnApply() { }
    public virtual void OnRemove() { }
    public virtual void OnStackIncreased(int currentStacks) { }
    public virtual void OnStackRemoved(int currentStacks) { }


    public virtual void OnRoundStart() { }
    public virtual void OnPhaseStart() { }

    public virtual void OnReceiveDamage(DamagePayload payload, ref float currentDamage) { }
    public virtual void OnDealDamage(DamagePayload payload, ref float currentDamage) { }
}
