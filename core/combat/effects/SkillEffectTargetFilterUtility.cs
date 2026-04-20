using CUSGA.core.combat.skills;

namespace CUSGA.core.combat.effects;


public static class SkillEffectTargetFilterUtility
{
    public static bool Matches(
        SkillEffectTargetFilter filter,
        SkillTarget target
    )
    {
        return filter switch
        {
            SkillEffectTargetFilter.AllTargets => true,
            SkillEffectTargetFilter.PrimaryOnly => target.IsPrimary,
            SkillEffectTargetFilter.SecondaryOnly => target.IsSecondary,
            _ => true
        };
    }
}
