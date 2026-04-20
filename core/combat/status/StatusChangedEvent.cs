using Godot;

namespace CUSGA.core.combat.status;

public sealed partial class StatusChangedEvent(StatusChangeContext context) : RefCounted
{
    public Node Owner { get; } = context.Owner;
    public Node Source { get; } = context.Source;

    public StringName StatusId { get; } = context.Status.Id;
    public int ReasonId => (int)Reason;

    public StatusChangeReason Reason { get; } = context.Reason;

    public int CurrentStacks { get; } = context.Status.CurrentStacks;

    public int OwnerTurnDuration { get; } = context.Status.OwnerTurnDuration;
    public int GlobalTurnDuration { get; } = context.Status.GlobalTurnDuration;
    public int RoundDuration { get; } = context.Status.RoundDuration;
}
