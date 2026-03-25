using CUSGA.core.attributes;
using CUSGA.entities.components;
using Godot;

namespace CUSGA.core.combat.buffs;

public class BossDamageCapPassive(Node source) : StatusEffect(source)
{
    public override StringName Id => new("Passive_Boss_Damage_Cap");

    public override void OnReceiveDamage(DamagePayload payload, ref float currentDamage)
    {
        float maxAllowedDamage = Owner.GetNode<HealthComponent>("HealthComponent").MaxValue * 0.10f;

        if (currentDamage > maxAllowedDamage)
        {
            currentDamage = maxAllowedDamage;

        }
    }
}
