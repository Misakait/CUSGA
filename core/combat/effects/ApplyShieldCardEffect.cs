using CUSGA.entities.components;
using CUSGA.core.combat.status;
using Godot;
using CUSGA.core.combat.skills;

namespace CUSGA.core.combat.effects;

[GlobalClass]
public partial class ApplyShieldCardEffect : CardEffect
{
    [Export] public ShieldStatusData ShieldStatus { get; set; }
    [Export] public SkillEffectTargetFilter TargetFilter { get; set; } = SkillEffectTargetFilter.AllTargets;

    public override void Execute(SkillExecutionContext context)
    {
        if (context == null)
        {
            GD.PushError($"{nameof(ApplyShieldCardEffect)} executed with null context.");
            return;
        }

        if (ShieldStatus == null)
        {
            GD.PushError($"{nameof(ApplyShieldCardEffect)} has no ShieldStatus assigned.");
            return;
        }

        foreach (var targetInfo in context.Targets)
        {
            if (!SkillEffectTargetFilterUtility.Matches(TargetFilter, targetInfo))
                continue;

            var target = targetInfo.Unit;

            if (target == null)
                continue;

            var statusComponent = target.GetNodeOrNull<StatusComponent>("StatusComponent");

            if (statusComponent == null)
            {
                GD.PushError($"Target '{target.Name}' has no StatusComponent.");
                continue;
            }

            var instance = ShieldStatus.CreateInstance(
                source: context.Source,
                owner: target,
                shieldAmount: ShieldStatus.DefaultShieldAmount
            );

            statusComponent.AddStatus(instance);
        }
    }
}
