using System;
using System.Collections.Generic;
using CUSGA.resources.interaction.operations;
using Godot;

namespace CUSGA.resources.interaction;

[GlobalClass]
public partial class VaultInteraction : TerrainInteraction
{
    public override IReadOnlyList<TerrainOp> BuildOps(TerrainInteractionBuildContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        return
        [
            new PassTimeOp(TimeCost),
            new EnterVaultOp()
        ];
    }
}
