using Godot;

namespace CUSGA.core.combat.status;

[GlobalClass]
public partial class VulnerableStatusData : StatusEffectData
{
    [Export] public DamageType TargetDamageType { get; set; } = DamageType.Physical;

    [Export] public float DamageMultiplier { get; set; } = 1.5f;

    public override StatusEffectInstance CreateInstance(Node source, Node owner)
    {
        return new VulnerableStatusInstance(this, source, owner);
    }
}
