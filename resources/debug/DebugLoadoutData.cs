using Godot;
using Godot.Collections;
using CUSGA.resources.stats;

namespace CUSGA.resources.debugging;

[GlobalClass]
public partial class DebugLoadoutData : Resource
{
    [Export] public StartingStats PlayerStartingStats { get; set; }
    [Export] public Array<DebugItemStackEntry> InventoryItems { get; set; } = [];
    [Export] public Array<DebugItemStackEntry> BattleDeckItems { get; set; } = [];
    [Export] public Array<DebugGeneratedEquipmentEntry> InventoryEquipment { get; set; } = [];
    [Export] public Array<DebugGeneratedEquipmentEntry> EquippedEquipment { get; set; } = [];
}
