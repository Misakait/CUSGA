using Godot;
using CUSGA.entities;

namespace CUSGA.resources.interaction;
// 以后最好把player去掉改成完全只读的record
public partial class TerrainInteractionBuildContext : RefCounted
{
    public required Player Player { get; init; }
    public required BoardCardView Card { get; init; }
    public required TerrainInstance Terrain { get; init; }
}
