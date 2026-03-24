using CUSGA.core.constants;
using Godot;

namespace CUSGA.resources.item.card;

[GlobalClass]
public partial class SkillCardData : ItemData
{
    // 基类已经有了很多字段
    [Export] public ElementType element = ElementType.None;
    [Export] public int cost = 10;
    [Export] public int damage = 10;

    // 对应 apply_effect 方法
    public void ApplyEffect(dynamic target)
    {
        GD.Print("打出了一张卡牌：" + CardName);
        if (damage > 0)
        {
            target.take_damage(damage);
            GD.Print("对目标造成了 " + damage + " 点伤害");
        }
    }
}
