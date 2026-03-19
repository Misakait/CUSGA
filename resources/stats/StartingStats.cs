using Godot;
namespace CUSGA.resources.stats;

[GlobalClass]
public partial class StartingStats : Resource
{
	[Export] public float BasePhysAtk { get; set; } = 10f;
	[Export] public float PhysAtkGrowth { get; set; } = 2.5f;
	[Export] public float BasePhysDef { get; set; } = 5f;
	[Export] public float PhysDefGrowth { get; set; } = 1f;
	[Export] public float BaseMagPower { get; set; } = 10f;
	[Export] public float MagPowerGrowth { get; set; } = 3f;
	[Export] public float BaseMagResist { get; set; } = 5f;
	[Export] public float MagResistGrowth { get; set; } = 1f;
	[Export] public float BaseSpeed { get; set; } = 100f;
	[Export] public float SpeedGrowth { get; set; } = 5f;

}
