using Godot;
using CUSGA.core.inventory;

namespace CUSGA.resources.interaction.operations;

public sealed partial class SpawnLootOp(Godot.Collections.Array<ItemStack> drops) : TerrainOp
{
    public Godot.Collections.Array<ItemStack> Drops { get; } = drops ?? [];

    public override void Apply(WorldInteractionContext context)
    {
        if (Drops.Count == 0)
        {
            return;
        }

        context.Board.SpawnLootCards(Drops, context.SourceGlobalPosition);
    }
}
