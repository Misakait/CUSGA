using System.Collections.Generic;
using CUSGA.core.combat.skills;
using Godot;

namespace CUSGA.core.combat.effects;

public static class SkillEffectTargetScopeUtility
{
    public static IEnumerable<SkillEffectTargetSelection> SelectTargets(
        SkillExecutionContext context,
        SkillEffectTargetScope scope
    )
    {
        if (context == null)
        {
            yield break;
        }

        if (scope == SkillEffectTargetScope.Source)
        {
            if (context.Source != null)
            {
                yield return SkillEffectTargetSelection.FromSource(context.Source);
            }

            yield break;
        }

        foreach (var target in context.Targets)
        {
            if (target?.Unit == null)
            {
                continue;
            }

            var matched = scope switch
            {
                SkillEffectTargetScope.AllTargets => true,
                SkillEffectTargetScope.PrimaryOnly => target.IsPrimary,
                SkillEffectTargetScope.SecondaryOnly => target.IsSecondary,
                _ => false
            };

            if (matched)
            {
                yield return SkillEffectTargetSelection.FromTarget(target);
            }
        }
    }

    public static IEnumerable<Node> SelectNodes(
        SkillExecutionContext context,
        SkillEffectTargetScope scope
    )
    {
        foreach (var target in SelectTargets(context, scope))
        {
            yield return target.Unit;
        }
    }
}
