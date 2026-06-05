using CUSGA.entities.components;
using Godot;

namespace CUSGA.core.combat.status;

public sealed partial class BurnStatusInstance(
    BurnStatusData data,
    Node source,
    Node owner
) : StatusEffectInstance(data, source, owner)
{
    private readonly BurnStatusData _data = data;

    public override void OnOwnerTurnStart()
    {
        if (_data.DamagePerStack <= 0f)
        {
            return;
        }

        var receiver = Owner.GetNodeOrNull<DamageReceiverComponent>("Components/DamageReceiverComponent");

        if (receiver == null)
        {
            GD.PushWarning($"{Owner?.Name} has Burn status but no DamageReceiverComponent.");
            return;
        }

        float damage = _data.DamagePerStack * CurrentStacks;

        var payload = new DamagePayload
        {
            Source = Source ?? Owner,
            Target = Owner,
            Damage = (int)damage,
            Type = _data.DamageType,
            Element = _data.Element,
            DamageModifiers = _data.DamageModifiers
        };

        receiver.ReceiveDamage(payload);

        GD.Print($"[Burn] {Owner.Name} takes {damage} burn damage. Stacks={CurrentStacks}");
    }
}
