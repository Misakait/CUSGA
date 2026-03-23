using Godot;

namespace CUSGA.resources.item.interaction;

[GlobalClass]
public partial class TerrainCardData : BaseCardData
{
    [Export] public TerrainInteraction InteractionBehavior { get; set; }
}
