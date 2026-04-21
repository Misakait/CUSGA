using CUSGA.core.constants;
using Godot;

namespace CUSGA.core.combat.status;

[GlobalClass]
public partial class BurnStatusData : StatusEffectData
{
    [Export] public float DamagePerStack { get; set; } = 5f;

    [Export] public DamageType DamageType { get; set; } = DamageType.Magic;

    [Export] public ElementType Element { get; set; } = ElementType.Fire;

    public override StatusEffectInstance CreateInstance(Node source, Node owner)
    {
        return new BurnStatusInstance(this, source, owner);
    }
}
