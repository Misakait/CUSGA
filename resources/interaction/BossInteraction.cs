using Godot;
using System;
using CUSGA.resources.interaction.operations;
using System.Collections.Generic;
using CUSGA.resources.monsters;

namespace CUSGA.resources.interaction;

[GlobalClass]
public partial class BossInteraction : TerrainInteraction
{
    [Export] public MonsterData Monster { get; set; } = null!;
    public override IReadOnlyList<TerrainOp> BuildOps(TerrainInteractionBuildContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        var ops = new List<TerrainOp>
        {
            new PassTimeOp(TimeCost),
            new MonsterSpawnOpOp(Monster),
            new RemoveSourceCardOp()
        };

        return ops;
    }
}
