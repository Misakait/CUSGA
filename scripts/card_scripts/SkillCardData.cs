using Godot;

// 对应 extends Resource + class_name SkillCardData
[GlobalClass]
public partial class SkillCardData : Resource
{
	// 对应 enum Element
	public enum Element
	{
		NONE,
		METAL,
		WOOD,
		WATER,
		FIRE,
		EARTH
	}

	// 对应 @export 变量（保持默认值与原代码一致）
	[Export] public string name = "卡牌基类";
	[Export] public Element element = Element.NONE;
	[Export] public int cost = 10;
	[Export] public int damage = 10;
	[Export] public string description = "这是一张卡牌基类，并且这里是卡牌的效果描述。";

	// 对应 apply_effect 方法
	public void ApplyEffect(dynamic target)
	{
		GD.Print("打出了一张卡牌：" + name);
		if (damage > 0)
		{
			target.take_damage(damage);
			GD.Print("对目标造成了 " + damage + " 点伤害");
		}
	}
}
