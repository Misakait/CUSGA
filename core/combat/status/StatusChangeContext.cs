using Godot;

namespace CUSGA.core.combat.status;

public sealed class StatusChangeContext(
    Node owner,
    Node source,
    StatusEffectInstance status,
    StatusChangeReason reason
    )
{
    public Node Owner { get; } = owner;
    public Node Source { get; } = source;
    public StatusEffectInstance Status { get; } = status;
    public StatusChangeReason Reason { get; } = reason;
}
