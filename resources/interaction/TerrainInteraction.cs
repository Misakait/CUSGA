using Godot;
using CUSGA.entities;

namespace CUSGA.resources.interaction;

[GlobalClass]
public abstract partial class TerrainInteraction : Resource
{
	[Export] public int TimeCost { get; set; } = 20;

	public abstract void Execute(Node cardNode, Player player);
}
