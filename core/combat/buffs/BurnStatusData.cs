using CUSGA.core.constants;
using Godot;

namespace CUSGA.core.combat.status;

[GlobalClass]
public partial class BurnStatusData : StatusEffectData
{
    [Export] public float DamagePerStack { get; set; } = 5f;

    [Export] public DamageType DamageType { get; set; } = DamageType.Magic;

    [Export] public ElementType Element { get; set; } = ElementType.Fire;

    /// <summary>
    /// 灼烧每回合伤害启用的直接攻击修饰。默认不启用，避免持续伤害被闪避、暴击、浮动或吸血。
    /// </summary>
    [Export] public DamageModifierFlags DamageModifiers { get; set; } = DamageModifierFlags.None;

    public override StatusEffectInstance CreateInstance(Node source, Node owner)
    {
        return new BurnStatusInstance(this, source, owner);
    }
}
