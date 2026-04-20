using Godot;
using CUSGA.core.combat.skills;
using CUSGA.core.constants;

namespace CUSGA.core.combat.monster;

public sealed partial class MonsterSkillPreview(CombatSkillData skill, string description) : RefCounted
{
    public StringName SkillId { get; } = skill.CardId;
    public string DisplayName { get; } = skill.CardName;
    public string Description { get; } = description;
    public Texture2D Icon { get; } = skill.CardIcon;

    public ElementType Element { get; } = skill.Element;
    public int ElementId => (int)Element;

    public SkillTargetingType TargetingType { get; } = skill.TargetingType;
    public int TargetingTypeId => (int)TargetingType;
}
