using Godot;
using CUSGA.entities.components;
using CUSGA.core.combat.status;

namespace CUSGA.core.combat.effects;

[GlobalClass]
public partial class ApplyStatusCardEffect : CardEffect
{
    [Export] public StatusEffectData Status { get; set; }

    public override void Execute(Node source, Node target)
    {
        if (Status == null)
        {
            GD.PushError($"{nameof(ApplyStatusCardEffect)} has no Status assigned.");
            return;
        }

        if (target == null)
        {
            GD.PushError($"{nameof(ApplyStatusCardEffect)} target is null.");
            return;
        }

        var statusComponent = target.GetNodeOrNull<StatusComponent>("StatusComponent");

        if (statusComponent == null)
        {
            GD.PushError($"Target '{target.Name}' has no StatusComponent.");
            return;
        }

        var instance = Status.CreateInstance(source, target);
        statusComponent.AddStatus(instance);
    }
}
