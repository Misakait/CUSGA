namespace CUSGA.resources.interaction.operations;

public sealed partial class RemoveSourceCardOp : TerrainOp
{
    public override void Apply(WorldInteractionContext context)
    {
        context.Board.RemoveSourceCard();
    }
}
