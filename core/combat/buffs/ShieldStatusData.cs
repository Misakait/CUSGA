using Godot;

namespace CUSGA.core.combat.status;

[GlobalClass]
public partial class ShieldStatusData : StatusEffectData
{
    [Export] public float DefaultShieldAmount { get; set; } = 0f;

    public override StatusEffectInstance CreateInstance(Node source, Node owner)
    {
        return new ShieldStatusInstance(
            data: this,
            source: source,
            owner: owner,
            shieldAmount: DefaultShieldAmount
        );
    }

    public ShieldStatusInstance CreateInstance(
        Node source,
        Node owner,
        float shieldAmount
    )
    {
        return new ShieldStatusInstance(
            data: this,
            source: source,
            owner: owner,
            shieldAmount: shieldAmount
        );
    }
}
