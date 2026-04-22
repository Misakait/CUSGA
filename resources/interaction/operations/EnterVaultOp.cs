using CUSGA.core.constants;
using Godot;

namespace CUSGA.resources.interaction.operations;

public sealed partial class EnterVaultOp : TerrainOp
{
    public override void Apply(WorldInteractionContext context)
    {
        context.GlobalEventBus?.EmitSignal(GDSignals.OnEnteredVault);
    }
}
