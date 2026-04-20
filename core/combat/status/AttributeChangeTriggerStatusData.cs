using Godot;
using Godot.Collections;
using CUSGA.core.attributes;
using CUSGA.core.combat.effects;

namespace CUSGA.core.combat.status;

// 属性变化后触发效果
[GlobalClass]
public partial class AttributeChangeTriggerStatusData : StatusEffectData
{
    [Export] public AttributeType TargetAttribute { get; set; }
    [Export] public AttributeChangeDirection Direction { get; set; } = AttributeChangeDirection.Any;

    [Export] public Array<CardEffect> Effects { get; set; } = [];

    public override StatusEffectInstance CreateInstance(Node source, Node owner)
    {
        return new AttributeChangeTriggerStatusInstance(this, source, owner);
    }
}
