using System;
using CUSGA.resources.monsters;
using Godot;
namespace CUSGA.resources.interaction.operations;

public sealed partial class MonsterSpawnOpOp(MonsterData Monster) : TerrainOp
{
    public override void Apply(WorldInteractionContext context)
    {
        context.GameplayPort.RequestEncounter(context.Terrain, Monster, "Boss Battle!");
    }
}
