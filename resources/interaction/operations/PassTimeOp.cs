using Godot;
using CUSGA.core.autoloads;

namespace CUSGA.resources.interaction.operations;

public sealed partial class PassTimeOp(int minutes) : TerrainOp
{
    public int Amount { get; } = minutes;

    public override void Apply(WorldInteractionContext context)
    {
        if (Amount > 0)
        {
            TimeSystem.Instance.PassTime(Amount);
        }
    }
}
