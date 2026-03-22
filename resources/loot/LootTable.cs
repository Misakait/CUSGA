using Godot;
using Godot.Collections;
using CUSGA.core.inventory;

namespace CUSGA.resources.loot;

[GlobalClass]
public partial class LootTable : Resource
{
	[Export] public Array<LootDrop> Drops { get; set; } = [];

	public Array<ItemStack> RollLoot()
	{
		Array<ItemStack> generatedLoot = [];

		foreach (var drop in Drops)
		{
			if (drop.Item == null) continue;
			float roll = GD.Randf() * 100f;

			if (roll <= drop.DropChance)
			{
				int amount = GD.RandRange(drop.MinAmount, drop.MaxAmount);
				if (amount > 0)
				{
					ItemStack stack = new();
					stack.SetItem(drop.Item, amount);
					generatedLoot.Add(stack);
				}
			}
		}

		return generatedLoot;
	}
}
