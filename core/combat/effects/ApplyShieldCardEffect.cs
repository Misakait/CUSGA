using CUSGA.entities.components;
using CUSGA.core.combat.status;
using Godot;

namespace CUSGA.core.combat.effects;

[GlobalClass]
public partial class ApplyShieldCardEffect : CardEffect
{
    [Export] public ShieldStatusData ShieldStatus { get; set; }

    public override void Execute(Node source, Node target)
    {
        if (target == null)
        {
            GD.PushError($"{nameof(ApplyShieldCardEffect)} target is null.");
            return;
        }

        if (ShieldStatus == null)
        {
            GD.PushError($"{nameof(ApplyShieldCardEffect)} has no ShieldStatus assigned.");
            return;
        }

        var statusComponent = target.GetNodeOrNull<StatusComponent>("StatusComponent");

        if (statusComponent == null)
        {
            GD.PushError($"Target '{target.Name}' has no StatusComponent.");
            return;
        }

        var instance = ShieldStatus.CreateInstance(
            source: source,
            owner: target,
            shieldAmount: ShieldStatus.DefaultShieldAmount
        );

        statusComponent.AddStatus(instance);
    }
}
