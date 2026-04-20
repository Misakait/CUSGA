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
