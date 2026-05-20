using CUSGA.resources.encounters;
using Godot;

namespace CUSGA.resources.interaction;

public partial class TerrainInstance : RefCounted
{
    public Vector2I LocalGridPos { get; set; }
    public Vector2 BoardPosition { get; set; }
    public MonsterStatMultiplier EncounterVarianceMultiplier { get; set; } =
        MonsterStatMultiplier.Identity;

    public TerrainCardData TerrainData { get; set; }
    public bool IsOccupied { get; set; }
    public bool IsHarvested { get; set; }
    public int GrowthStage { get; set; }
}
