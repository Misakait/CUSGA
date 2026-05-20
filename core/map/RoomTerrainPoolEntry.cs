using CUSGA.resources.interaction;
using Godot;

namespace CUSGA.core.map;

[GlobalClass]
public partial class RoomTerrainPoolEntry : Resource
{
    [Export] public TerrainCardData TerrainData { get; set; }
    [Export] public float Weight { get; set; } = 1f;
}
