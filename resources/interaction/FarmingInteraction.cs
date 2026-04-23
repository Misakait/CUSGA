using System;
using System.Collections.Generic;
using CUSGA.resources.interaction.operations;
using Godot;
using Godot.Collections;
namespace CUSGA.resources.interaction;

[GlobalClass]
public partial class FarmingInteraction : TerrainInteraction
{
    public override IReadOnlyList<TerrainOp> BuildOps(TerrainInteractionBuildContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        var ops = new List<TerrainOp>
        {
            new PassTimeOp(TimeCost)
        };

        if (!context.Terrain.IsOccupied)
        {
            ops.Add(new OpenFarmingPanelOp());
        }

        return ops;
    }
}
