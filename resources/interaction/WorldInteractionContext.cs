using Godot;
using CUSGA.core.autoloads;
using CUSGA.core.board;
using CUSGA.entities;
using CUSGA.core.application;

namespace CUSGA.resources.interaction;

public sealed partial class WorldInteractionContext : RefCounted
{
    public required GameplayPort GameplayPort { get; init; }
    public required BoardController BoardController { get; init; }
    public required BoardCardView Card { get; init; }
    public required TerrainInstance Terrain { get; init; }
    public required Node GlobalEventBus { get; init; }
    public required Control BackpackFlyTarget { get; init; }
    public required EncounterManager EncounterManager { get; init; }
}
