using CUSGA.core.constants;
using Godot;

namespace CUSGA.resources.item.card;

[GlobalClass]
public partial class SkillCardData : ItemData
{
    [Export] public StringName Name { get; set; } = "卡牌基类";
    [Export] public int EnergyCost { get; set; } = 1;
    [Export] public float BaseDamage { get; set; } = 10f;
    [Export] public string Description { get; set; } = "这是一张卡牌基类，并且这里是卡牌的效果描述。";
    [Export] public ElementType ElementProperty { get; set; } = ElementType.None;
}
