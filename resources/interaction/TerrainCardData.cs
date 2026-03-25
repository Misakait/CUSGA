using Godot;
using CUSGA.resources.item;
namespace CUSGA.resources.interaction;

[GlobalClass]
public partial class TerrainCardData : BaseCardData
{
    [Export] public TerrainInteraction InteractionBehavior { get; set; }
}
