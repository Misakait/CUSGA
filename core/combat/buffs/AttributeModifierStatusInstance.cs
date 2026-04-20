using Godot;
using System.Collections.Generic;
using CUSGA.core.attributes;
using CUSGA.core.combat.status;

namespace CUSGA.core.combat.buffs;

public sealed partial class AttributeModifierStatusInstance(
    AttributeModifierStatusData data,
    Node source,
    Node owner
    ) : StatusEffectInstance(data, source, owner)
{
    private readonly AttributeModifierStatusData _data = data;

    public override IEnumerable<AttributeModifier> GetAttributeModifiers()
    {
        foreach (var modifier in _data.Modifiers)
        {
            if (modifier == null)
                continue;

            yield return new AttributeModifier(
                modifier.Type,
                modifier.Mode,
                modifier.ValuePerStack,
                CurrentStacks,
                Id
            );
        }
    }
}
