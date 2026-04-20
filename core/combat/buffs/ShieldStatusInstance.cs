using CUSGA.entities.components;
using Godot;

namespace CUSGA.core.combat.status;

public sealed partial class ShieldStatusInstance(
    ShieldStatusData data,
    Node source,
    Node owner,
    float shieldAmount
    ) : StatusEffectInstance(data, source, owner)
{
    private readonly ShieldStatusData _data = data;

    public float ShieldAmount { get; private set; } = Mathf.Max(0f, shieldAmount);
    public override void OnBeforeHealthDamage(DamagePayload payload, ref float damage)
    {
        if (damage <= 0f)
            return;

        if (ShieldAmount <= 0f)
            return;

        float absorbed = Mathf.Min(ShieldAmount, damage);

        ShieldAmount -= absorbed;
        damage -= absorbed;

        if (ShieldAmount <= 0f)
        {
            Owner.GetNodeOrNull<StatusComponent>("StatusComponent")
                ?.RemoveStatus(Id);
        }
    }

    public override void OnReapplied(StatusEffectInstance incoming)
    {
        if (incoming is not ShieldStatusInstance shield)
            return;

        ShieldAmount += shield.ShieldAmount;
    }
}
