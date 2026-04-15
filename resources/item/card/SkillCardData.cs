using CUSGA.core.combat.effects;
using CUSGA.core.constants;
using Godot;
using Godot.Collections;

namespace CUSGA.resources.item.card;

[GlobalClass]
public partial class SkillCardData : ItemData
{
    [Export] public Array<CardEffect> Effects { get; set; } = [];
    // 基类已经有了很多字段
    [Export] public ElementType element = ElementType.None;
    [Export] public int cost = 10;

    public override int ActualMaxStackSize => 1;

    // 对应 apply_effect 方法
    public void ApplyEffect(Node source, Node target)
    {
        GD.Print($"打出了卡牌：{CardName}");
        foreach (var effect in Effects)
        {
            if (effect != null)
            {
                effect.Execute(source, target);
            }
        }
    }
}
