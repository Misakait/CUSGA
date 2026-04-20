using Godot;

namespace CUSGA.core.combat.status;

[GlobalClass]
public partial class BossDamageCapStatusData : StatusEffectData
{
    [Export(PropertyHint.Range, "0,1,0.01")]
    public float MaxHealthDamageRatio { get; set; } = 0.10f;

    public override StatusEffectInstance CreateInstance(Node source, Node owner)
    {
        return new BossDamageCapStatusInstance(this, source, owner);
    }
}
