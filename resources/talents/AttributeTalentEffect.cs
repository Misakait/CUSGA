using Godot;
using CUSGA.core.attributes;
using CUSGA.entities.components;
using CUSGA.entities;
namespace CUSGA.resources.talents;

[GlobalClass]
public partial class AttributeTalentEffect : TalentEffect
{
	[Export] public AttributeType TargetAttribute { get; set; }
	[Export] public float BonusValue { get; set; }

	public override void Apply(Player targetPlayer)
	{
		var attrComp = targetPlayer.GetNodeOrNull<AttributeComponent>("AttributeComponent");

		if (attrComp != null)
		{
			var attribute = attrComp.GetAttribute(TargetAttribute);
			if (attribute != null)
			{
				attribute.AddBonus(BonusValue);
				GD.Print($"天赋生效：{TargetAttribute} 永久增加了 {BonusValue}！");
			}
		}
	}
}
