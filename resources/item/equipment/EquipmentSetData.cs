using CUSGA.core.constants;
using Godot;

namespace CUSGA.resources.item.equipment;

[GlobalClass]
public partial class EquipmentSetData : Resource
{
	// 代表的套装
	[Export] public EquipmentSet SetType { get; set; }

	// 包含的所有阶级效果
	[Export] public Godot.Collections.Array<SetBonusTier> Tiers { get; set; } = [];
}
