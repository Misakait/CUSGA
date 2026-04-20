using Godot;

namespace CUSGA.core.attributes;

public sealed partial class AttributeChangedEvent(AttributeChangeContext context) : RefCounted
{
    public Node Owner { get; } = context.Owner;
    public Node Source { get; } = context.Source;

    public AttributeType Type { get; } = context.Type;
    public int TypeId => (int)Type;

    public AttributeChangeReason Reason { get; } = context.Reason;
    public int ReasonId => (int)Reason;

    public float OldValue { get; } = context.OldValue;
    public float NewValue { get; } = context.NewValue;
    public float Delta => NewValue - OldValue;

    public bool IsIncrease => Delta > 0f;
    public bool IsDecrease => Delta < 0f;
}
