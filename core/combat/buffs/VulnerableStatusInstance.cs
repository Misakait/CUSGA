using Godot;

namespace CUSGA.core.combat.status;

// 受到物理伤害 +50%，然后还能被防御减伤
public sealed partial class VulnerableStatusInstance(
    VulnerableStatusData data,
    Node source,
    Node owner
    ) : StatusEffectInstance(data, source, owner)
{
    private readonly VulnerableStatusData _data = data;

    public override void OnModifyIncomingDamageBeforeMitigation(
        DamagePayload payload,
        ref float damage
    )
    {
        if (payload.Type != DamageType.Physical)
            return;

        damage *= 1.5f;
    }
}
