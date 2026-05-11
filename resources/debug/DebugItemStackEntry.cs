using Godot;
using CUSGA.core.inventory;
using CUSGA.resources.item;

namespace CUSGA.resources.debugging;

[GlobalClass]
public partial class DebugItemStackEntry : Resource
{
    [Export] public ItemData Item { get; set; }
    [Export(PropertyHint.Range, "1,999,1")] public int Amount { get; set; } = 1;
    [Export] public bool RollRandomStats { get; set; } = true;

    public ItemStack CreateStack()
    {
        if (Item == null || Amount <= 0)
        {
            return null;
        }

        ItemStack stack = new();
        stack.SetItem(Item, Amount);
        if (RollRandomStats)
        {
            stack.RollRandomStats();
        }

        return stack;
    }
}
