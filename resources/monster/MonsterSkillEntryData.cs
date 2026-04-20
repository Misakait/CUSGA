using Godot;
using CUSGA.core.combat.skills;

namespace CUSGA.resources.monster;

[GlobalClass]
public partial class MonsterSkillEntryData : Resource
{
    [Export] public CombatSkillData Skill { get; set; }

    [Export] public bool VisibleInPreview { get; set; } = true;

    [Export(PropertyHint.MultilineText)]
    public string PreviewDescriptionOverride { get; set; } = "";

    public string GetPreviewDescription()
    {
        if (!string.IsNullOrWhiteSpace(PreviewDescriptionOverride))
            return PreviewDescriptionOverride;

        return Skill?.Description ?? "";
    }
}
