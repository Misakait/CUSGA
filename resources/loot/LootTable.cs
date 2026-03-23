using Godot;
using Godot.Collections;
using CUSGA.core.inventory;

namespace CUSGA.resources.loot;

[GlobalClass]
public partial class LootTable : Resource
{
    [Export] public Array<LootDrop> Drops { get; set; } = [];

    public Array<ItemStack> RollLoot(int yieldGrowth)
    {
        Array<ItemStack> generatedLoot = [];

        foreach (var drop in Drops)
        {
            if (drop.Item == null) continue;
            float roll = GD.Randf() * 100f;

            if (roll <= drop.DropChance)
            {
                int baseAmount = GD.RandRange(drop.MinAmount, drop.MaxAmount);
                int finalAmount = baseAmount + yieldGrowth;

                if (finalAmount > 0)
                {
                    ItemStack stack = new();
                    stack.SetItem(drop.Item, finalAmount);
                    generatedLoot.Add(stack);
                }
            }
        }

        return generatedLoot;
    }
}
