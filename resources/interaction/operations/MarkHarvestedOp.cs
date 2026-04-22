namespace CUSGA.resources.interaction.operations;

public sealed partial class MarkHarvestedOp : TerrainOp
{
    public override void Apply(WorldInteractionContext context)
    {
        context.Terrain.IsHarvested = true;
    }
}
