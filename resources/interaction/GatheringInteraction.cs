using Godot;
using System;

using CUSGA.resources.loot;
using CUSGA.resources.interaction.operations;
using System.Collections.Generic;

namespace CUSGA.resources.interaction;

[GlobalClass]
public partial class GatheringInteraction : TerrainInteraction
{
    [Export] public StringName GatheringTag { get; set; }
    [Export] public LootTable DropTable { get; set; }

    public override IReadOnlyList<TerrainOp> BuildOps(TerrainInteractionBuildContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        var ops = new List<TerrainOp>
        {
            new PassTimeOp(TimeCost),
            new MarkHarvestedOp()
        };
        if (context.Terrain.IsHarvested)
        {
            int extraYield = context.Player.Equipment.GetGatheringYieldBonus(GatheringTag);
            var loots = DropTable?.RollLoot(extraYield) ?? [];

            if (loots.Count > 0)
            {
                ops.Add(new SpawnLootOp(loots));
            }
        }
        ops.Add(new CheckGatheringEncounterOp(GatheringTag));
        ops.Add(new RemoveSourceCardOp());

        return ops;
    }
}
