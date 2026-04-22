using Godot;
using CUSGA.core.autoloads;

namespace CUSGA.resources.interaction.operations;

public sealed partial class CheckGatheringEncounterOp(StringName gatheringTag) : TerrainOp
{
    public StringName GatheringTag { get; } = gatheringTag;

    public override void Apply(WorldInteractionContext context)
    {
        if (GatheringTag.IsEmpty)
        {
            return;
        }

        var result = EncounterManager.Instance.ResolveGatheringEncounter(GatheringTag);
        if (!result.Triggered)
        {
            return;
        }

        context.GameplayPort.RequestEncounter(
            context.Terrain,
            result.MonsterToSpawn,
            result.SpawnMessage
        );
    }
}
