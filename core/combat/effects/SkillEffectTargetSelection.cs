using Godot;
using CUSGA.core.combat.skills;

namespace CUSGA.core.combat.effects;

public readonly struct SkillEffectTargetSelection
{
    public Node Unit { get; }
    public SkillTargetRole Role { get; }
    public bool IsSource { get; }

    public bool IsPrimary => !IsSource && Role == SkillTargetRole.Primary;
    public bool IsSecondary => !IsSource && Role == SkillTargetRole.Secondary;

    private SkillEffectTargetSelection(Node unit, SkillTargetRole role, bool isSource)
    {
        Unit = unit;
        Role = role;
        IsSource = isSource;
    }

    public static SkillEffectTargetSelection FromSource(Node source)
    {
        return new SkillEffectTargetSelection(
            source,
            SkillTargetRole.Primary,
            true
        );
    }

    public static SkillEffectTargetSelection FromTarget(SkillTarget target)
    {
        return new SkillEffectTargetSelection(
            target.Unit,
            target.Role,
            false
        );
    }
}
