using Godot;
using CUSGA.core.attributes;
using CUSGA.core.combat.skills;

namespace CUSGA.core.combat.status;

public sealed partial class AttributeChangeTriggerStatusInstance(
    AttributeChangeTriggerStatusData data,
    Node source,
    Node owner
    ) : StatusEffectInstance(data, source, owner)
{
    private readonly AttributeChangeTriggerStatusData _data = data;

    private bool _isExecuting;

    public override void OnAfterAttributeChanged(AttributeChangeContext context)
    {
        if (_isExecuting)
            return;

        if (context.Type != _data.TargetAttribute)
            return;

        if (!context.MatchesDirection(_data.Direction))
            return;

        if (_data.Effects.Count == 0)
            return;

        _isExecuting = true;

        try
        {
            foreach (var effect in _data.Effects)
            {
                if (effect == null)
                    continue;
                SkillExecutionContext effectContext = SkillExecutionContext.FromSingleTarget(context.Source ?? Source ?? Owner, Owner);
                effect.Execute(effectContext);
            }
        }
        finally
        {
            _isExecuting = false;
        }
    }
}
