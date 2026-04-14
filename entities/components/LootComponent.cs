using Godot;
using CUSGA.resources.loot;
using CUSGA.core.inventory;
using CUSGA.core.constants;
using Godot.Collections;

namespace CUSGA.entities.components;

[GlobalClass]
public partial class LootComponent : Node
{
    [Export] public LootTable DropTable { get; set; }

    public void TriggerDrop(Vector2 globalPosition, int yiledGrowth)
    {
        if (DropTable == null) return;

        Array<ItemStack> rolledLoots = DropTable.RollLoot(yiledGrowth);

        var globalEventBus = GetNode<Node>("/root/GlobalEventBus");
        globalEventBus.EmitSignal(GDSignals.OnEntityDropped, globalPosition, rolledLoots);
    }
}
