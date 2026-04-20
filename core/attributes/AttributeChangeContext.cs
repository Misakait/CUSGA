using Godot;

namespace CUSGA.core.attributes;

public sealed class AttributeChangeContext(
    Node owner,
    Node source,
    AttributeType type,
    AttributeChangeReason reason,
    float oldValue,
    float newValue
    )
{
    public Node Owner { get; } = owner;
    public Node Source { get; } = source;

    public AttributeType Type { get; } = type;
    public AttributeChangeReason Reason { get; } = reason;

    public int TypeId => (int)Type;
    public int ReasonId => (int)Reason;

    public float OldValue { get; } = oldValue;
    public float OriginalNewValue { get; } = newValue;
    public float NewValue { get; set; } = newValue;

    public bool IsCancelled { get; private set; }

    public float Delta => NewValue - OldValue;
    public bool IsIncrease => Delta > 0f;
    public bool IsDecrease => Delta < 0f;

    public void Cancel()
    {
        IsCancelled = true;
    }

    public bool MatchesDirection(AttributeChangeDirection direction)
    {
        return direction switch
        {
            AttributeChangeDirection.Any => true,
            AttributeChangeDirection.Increase => IsIncrease,
            AttributeChangeDirection.Decrease => IsDecrease,
            _ => false
        };
    }
}
