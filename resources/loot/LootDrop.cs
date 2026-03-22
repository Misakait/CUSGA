using Godot;
using CUSGA.resources.item;

namespace CUSGA.resources.loot;

[GlobalClass]
public partial class LootDrop : Resource
{
	// 掉落的物品
	[Export] public ItemData Item { get; set; }

	// 掉落概率
	[Export(PropertyHint.Range, "0,100,0.1")]
	public float DropChance { get; set; } = 100f;

	// 最少掉几个
	[Export] public int MinAmount { get; set; } = 1;

	// 最多掉几个
	[Export] public int MaxAmount { get; set; } = 1;
}
