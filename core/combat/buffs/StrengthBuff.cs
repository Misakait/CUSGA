using CUSGA.core.attributes;
using CUSGA.entities.components;
using Godot;

namespace CUSGA.core.combat.buffs;

public class StrengthBuff(Node source) : StatusEffect(source)
{
    public override StringName Id => new("Buff_Strength");
    private readonly float _bonusAmount = 2f;

    public override void OnApply()
    {
        var attributes = Owner.GetNode<AttributeComponent>("AttributeComponent");
        attributes.GetAttribute(AttributeType.PhysAtk)?.AddBonus(_bonusAmount);
    }

    public override void OnRemove()
    {
        var attributes = Owner.GetNode<AttributeComponent>("AttributeComponent");
        attributes.GetAttribute(AttributeType.PhysAtk)?.RemoveBonus(_bonusAmount);
    }
}
