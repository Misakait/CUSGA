using CUSGA.core.combat.effects;
using CUSGA.core.combat.skills;
using CUSGA.core.constants;
using Godot;
using Godot.Collections;
using System.Collections.Generic;

namespace CUSGA.resources.item.card;

[GlobalClass]
public partial class SkillCardData : ItemData
{
    [Export] public CombatSkillData Skill { get; set; } = null!;
    [Export] public int cost = 10;
    [Export] public Array<string> CardTags { get; set; } = [];

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

    public string DisplayTag
    {
        get
        {
            if (CardTags == null || CardTags.Count == 0)
            {
                return "";
            }

            List<string> tags = new();
            foreach (var tag in CardTags)
            {
                if (string.IsNullOrWhiteSpace(tag))
                {
                    continue;
                }

                tags.Add(tag);
            }

            return tags.Count == 0 ? "" : string.Join("\n", tags);
        }
    }

    public ElementType Element => Skill?.Element ?? ElementType.None;

    /// <summary>
    /// 执行卡牌效果结算。
    /// </summary>
    /// <param name="context">技能执行上下文，包含施放者与目标。</param>
    /// <returns>无返回值。</returns>
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

        var logName = !string.IsNullOrWhiteSpace(DisplayName) ? DisplayName : CardName;
        if (string.IsNullOrWhiteSpace(logName))
        {
            logName = CardId.ToString();
        }

        GD.Print($"玩家打出了卡牌：{logName}");
        Skill.Execute(context);
    }
}
