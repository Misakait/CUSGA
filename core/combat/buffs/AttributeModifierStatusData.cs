using CUSGA.core.combat.status;
using Godot;
using Godot.Collections;

namespace CUSGA.core.combat.buffs;

[GlobalClass]
public partial class AttributeModifierStatusData : StatusEffectData
{
    [Export] public Array<AttributeModifierData> Modifiers { get; set; } = [];

    public override StatusEffectInstance CreateInstance(Node source, Node owner)
    {
        return new AttributeModifierStatusInstance(this, source, owner);
    }
}
