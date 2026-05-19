using System;

namespace CUSGA.resources.interaction.operations;

public sealed partial class EnterVaultOp : TerrainOp
{
    public override void Apply(WorldInteractionContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        context.GameplayPort.RequestOpenWarehouse();
    }
}
