using Godot;
using Godot.Collections;
using CUSGA.core.combat.monster;
using CUSGA.resources.monster;

namespace CUSGA.entities.components;

[GlobalClass]
public partial class MonsterSkillComponent : Node
{
    [Export] public MonsterSkillSetData SkillSet { get; set; }

    public Node Host => GetParent();

    public override void _Ready()
    {
        ValidateSkillSet();
    }

    private void ValidateSkillSet()
    {
        if (SkillSet == null)
        {
            GD.PushWarning($"{Host?.Name} has no MonsterSkillSetData.");
            return;
        }

        foreach (var entry in SkillSet.Skills)
        {
            if (entry == null)
            {
                GD.PushWarning($"{Host?.Name} has null skill entry in MonsterSkillSetData.");
                continue;
            }

            if (entry.Skill == null)
            {
                GD.PushWarning($"{Host?.Name} has MonsterSkillEntryData with null CombatSkillData.");
            }
        }
    }

    public Array<MonsterSkillPreview> GetSkillPreviews()
    {
        var result = new Array<MonsterSkillPreview>();

        if (SkillSet == null)
            return result;

        foreach (var entry in SkillSet.Skills)
        {
            if (entry == null)
                continue;

            if (!entry.VisibleInPreview)
                continue;

            if (entry.Skill == null)
                continue;

            result.Add(
                new MonsterSkillPreview(
                    skill: entry.Skill,
                    description: entry.GetPreviewDescription()
                )
            );
        }

        return result;
    }
}
