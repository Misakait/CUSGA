using Godot;
using CUSGA.entities;
using CUSGA.resources.interaction.operations;
using System.Collections.Generic;

namespace CUSGA.resources.interaction;

[GlobalClass]
public abstract partial class TerrainInteraction : Resource
{
    [Export] public int TimeCost { get; set; } = 20;

    public abstract IReadOnlyList<TerrainOp> BuildOps(TerrainInteractionBuildContext context);
}
