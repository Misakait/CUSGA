using Godot;
using Godot.Collections;

namespace CUSGA.resources.debugging;

[GlobalClass]
public partial class DebugLoadoutData : Resource
{
    // 调试配置在迁移期间同时接受 C# 与 GDScript StartingStats 资源。
    [Export] public Resource PlayerStartingStats { get; set; }
    [Export] public Array<DebugItemStackEntry> InventoryItems { get; set; } = [];
    [Export] public Array<DebugItemStackEntry> BattleDeckItems { get; set; } = [];
    [Export] public Array<DebugGeneratedEquipmentEntry> InventoryEquipment { get; set; } = [];
    [Export] public Array<DebugGeneratedEquipmentEntry> EquippedEquipment { get; set; } = [];
}
