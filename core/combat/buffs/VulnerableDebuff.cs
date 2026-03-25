using Godot;

namespace CUSGA.core.combat.buffs;

public class VulnerableDebuff(Node source) : StatusEffect(source)
{
    public override StringName Id => new("Debuff_Vulnerable");

    public override void OnReceiveDamage(DamagePayload payload, ref float currentDamage)
    {
        if (payload.Type == DamageType.Physical)
        {
            currentDamage *= 1.5f;
        }
    }
}
