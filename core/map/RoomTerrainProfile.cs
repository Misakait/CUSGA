using CUSGA.resources.encounters;
using Godot;

namespace CUSGA.core.map;

[GlobalClass]
public partial class RoomTerrainProfile : Resource
{
    [Export] public RoomTerrainPoolEntry[] TerrainPool { get; set; } = [];

    [Export] public int MinCount { get; set; } = 1;
    [Export] public int MaxCount { get; set; } = 3;
    [Export] public int GridColumns { get; set; } = 6;
    [Export] public int GridRows { get; set; } = 4;
    [Export] public Vector2 PlacementMin { get; set; } = new(360, 220);
    [Export] public Vector2 PlacementMax { get; set; } = new(920, 560);

    [Export] public MonsterStatMultiplierRange EncounterVarianceRange { get; set; } = new();
}
