using Godot;
using CUSGA.resources.interaction;

namespace CUSGA.core.map;

[GlobalClass]
public partial class TerrainSpawnPoint : Marker2D
{
    [Export] public TerrainCardData TerrainData { get; set; }

    // 房间内局部格子坐标
    [Export] public Vector2I LocalGridPos { get; set; }

    [Export] public bool SpawnOnEnter { get; set; } = true;
}
