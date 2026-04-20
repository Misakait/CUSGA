using Godot;

namespace CUSGA.core.combat.skills;

public sealed partial class SkillTarget(Node unit, SkillTargetRole role) : RefCounted
{
    public Node Unit { get; } = unit;
    public SkillTargetRole Role { get; } = role;

    public int RoleId => (int)Role;

    public bool IsPrimary => Role == SkillTargetRole.Primary;
    public bool IsSecondary => Role == SkillTargetRole.Secondary;
}
