using Godot;

namespace CUSGA.resources.interaction.operations;

public sealed partial class OpenFarmingPanelOp : TerrainOp
{
    public override void Apply(WorldInteractionContext context)
    {
        context.GameplayPort.RequestOpenFarmingPanel(context.Terrain);
    }
}
