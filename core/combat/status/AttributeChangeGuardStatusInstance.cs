using Godot;
using CUSGA.core.attributes;

namespace CUSGA.core.combat.status;

public sealed partial class AttributeChangeGuardStatusInstance(
    AttributeChangeGuardStatusData data,
    Node source,
    Node owner
    ) : StatusEffectInstance(data, source, owner)
{
    private readonly AttributeChangeGuardStatusData _data = data;

    public override void OnBeforeAttributeChange(AttributeChangeContext context)
    {
        if (context.Type != _data.TargetAttribute)
            return;

        if (!context.MatchesDirection(_data.Direction))
            return;

        if (_data.CancelChange)
        {
            context.Cancel();
            return;
        }

        context.NewValue = context.OldValue + context.Delta * _data.DeltaMultiplier;

        if (_data.EnableMinValue)
            context.NewValue = Mathf.Max(context.NewValue, _data.MinValue);

        if (_data.EnableMaxValue)
            context.NewValue = Mathf.Min(context.NewValue, _data.MaxValue);
    }
}
