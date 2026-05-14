using Godot;
using CUSGA.entities.components;
using CUSGA.core.combat.status;
using CUSGA.core.combat.skills;

namespace CUSGA.core.combat.effects;

[GlobalClass]
public partial class ApplyStatusCardEffect : CardEffect
{
    [Export] public StatusEffectData Status { get; set; }
    [Export]
    public SkillEffectTargetScope TargetScope { get; set; }
            = SkillEffectTargetScope.AllTargets;

    public override void Execute(SkillExecutionContext context)
    {
        if (Status == null)
        {
            GD.PushError($"{nameof(ApplyStatusCardEffect)} has no Status assigned.");
            return;
        }

        foreach (var target in SkillEffectTargetScopeUtility.SelectNodes(context, TargetScope))
        {
            var statusComponent = target.GetNodeOrNull<StatusComponent>("StatusComponent");

            if (statusComponent == null)
            {
                GD.PushError($"Target '{target.Name}' has no StatusComponent.");
                continue;
            }

            var instance = Status.CreateInstance(context.Source, target);
            statusComponent.AddStatus(instance);
        }
    }
}
