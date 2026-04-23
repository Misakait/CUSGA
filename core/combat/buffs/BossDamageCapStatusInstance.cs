using CUSGA.entities.components;
using Godot;

namespace CUSGA.core.combat.status;

public sealed partial class BossDamageCapStatusInstance(
    BossDamageCapStatusData data,
    Node source,
    Node owner
    ) : StatusEffectInstance(data, source, owner)
{
    private readonly BossDamageCapStatusData _data = data;

    public override int GetHookPriority(StatusHookPhase phase)
    {
        return phase == StatusHookPhase.BeforeHealthDamage
            ? 1000
            : base.GetHookPriority(phase);
    }

    public override void OnBeforeHealthDamage(DamagePayload payload, ref float damage)
    {
        if (damage <= 0f)
        {
            return;
        }

        var health = Owner.GetNodeOrNull<HealthComponent>("HealthComponent");
        if (health == null)
        {
            GD.PushWarning($"{Owner?.Name} has BossDamageCap but no HealthComponent.");
            return;
        }
        float maxAllowedDamage = health.MaxValue * _data.MaxHealthDamageRatio;
        damage = Mathf.Min(damage, maxAllowedDamage);
    }
}
