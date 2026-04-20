using System;
using Godot;

namespace CUSGA.core.attributes;

public sealed class RecalculateRequest
{
    public AttributeRecalculateScope Scope { get; }
    public AttributeType Type { get; }
    public Node Source { get; }
    public AttributeChangeReason Reason { get; }
    public bool AllowInterception { get; }
    public bool EmitEvents { get; }

    private readonly Action _mutation;

    private RecalculateRequest(
        AttributeRecalculateScope scope,
        AttributeType type,
        Node source,
        AttributeChangeReason reason,
        Action mutation,
        bool allowInterception,
        bool emitEvents
    )
    {
        Scope = scope;
        Type = type;
        Source = source;
        Reason = reason;
        _mutation = mutation;
        AllowInterception = allowInterception;
        EmitEvents = emitEvents;
    }

    public static RecalculateRequest Single(
        AttributeType type,
        Node source,
        AttributeChangeReason reason,
        Action mutation = null,
        bool allowInterception = true,
        bool emitEvents = true
    )
    {
        return new RecalculateRequest(
            scope: AttributeRecalculateScope.SingleAttribute,
            type: type,
            source: source,
            reason: reason,
            mutation: mutation,
            allowInterception: allowInterception,
            emitEvents: emitEvents
        );
    }

    public static RecalculateRequest All(
        Node source,
        AttributeChangeReason reason,
        Action mutation = null,
        bool allowInterception = true,
        bool emitEvents = true
    )
    {
        return new RecalculateRequest(
            scope: AttributeRecalculateScope.AllAttributes,
            type: default,
            source: source,
            reason: reason,
            mutation: mutation,
            allowInterception: allowInterception,
            emitEvents: emitEvents
        );
    }

    public void ApplyMutation()
    {
        _mutation?.Invoke();
    }
}
