using CUSGA.core.combat.effects;
using CUSGA.core.combat.skills;
using CUSGA.core.constants;
using Godot;
using Godot.Collections;

namespace CUSGA.resources.item.card;

[GlobalClass]
public partial class SkillCardData : ItemData
{
    [Export] public CombatSkillData Skill { get; set; } = null!;
    [Export] public int cost = 10;

    public override int ActualMaxStackSize => 1;

    public override string DisplayName
    {
        get
        {
            if (!string.IsNullOrWhiteSpace(CardName))
            {
                return CardName;
            }

            return Skill?.DisplayName ?? "";
        }
    }

    public override string DisplayDescription
    {
        get
        {
            if (!string.IsNullOrWhiteSpace(Description))
            {
                return Description;
            }

            return Skill?.DisplayDescription ?? "";
        }
    }

    public override Texture2D DisplayIcon
    {
        get
        {
            if (CardIcon != null)
            {
                return CardIcon;
            }

            return Skill?.DisplayIcon;
        }
    }

    public ElementType Element => Skill?.Element ?? ElementType.None;

    public void ApplyEffect(SkillExecutionContext context)
    {
        if (Skill == null)
        {
            GD.PushError($"{nameof(SkillCardData)} '{CardName}' has no CombatSkillData assigned.");
            return;
        }

        if (context == null)
        {
            GD.PushError($"{nameof(SkillCardData)} '{CardName}' executed with null context.");
            return;
        }

        GD.Print($"打出了卡牌：{CardName}");
        Skill.Execute(context);
    }
}
