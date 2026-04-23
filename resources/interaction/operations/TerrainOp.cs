using Godot;

namespace CUSGA.resources.interaction.operations;

public abstract partial class TerrainOp : RefCounted
{
    public abstract void Apply(WorldInteractionContext context);
}
