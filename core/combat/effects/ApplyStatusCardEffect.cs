using Godot;
using CUSGA.entities.components;
using CUSGA.core.combat.status;
using CUSGA.core.combat.skills;

namespace CUSGA.core.combat.effects;

[GlobalClass]
public partial class ApplyStatusCardEffect : CardEffect
{
    [Export] public StatusEffectData Status { get; set; }
    [Export] public SkillEffectTargetFilter TargetFilter { get; set; } = SkillEffectTargetFilter.AllTargets;

    public override void Execute(SkillExecutionContext context)
    {
        if (Status == null)
        {
            GD.PushError($"{nameof(ApplyStatusCardEffect)} has no Status assigned.");
            return;
        }

        foreach (var targetInfo in context.Targets)
        {
            if (!SkillEffectTargetFilterUtility.Matches(TargetFilter, targetInfo))
                continue;

            if (targetInfo.Unit == null)
                continue;

            var statusComponent = targetInfo.Unit.GetNodeOrNull<StatusComponent>("StatusComponent");

            if (statusComponent == null)
            {
                GD.PushError($"Target '{targetInfo.Unit.Name}' has no StatusComponent.");
                continue;
            }

            var instance = Status.CreateInstance(context.Source, targetInfo.Unit);
            statusComponent.AddStatus(instance);
        }
    }
}
