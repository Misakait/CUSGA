using Godot;

namespace CUSGA.core.constants;

public static class GDSignals
{
    public static readonly StringName OnInventoryToggled = new("on_inventory_toggled");
    public static readonly StringName OnPlayerAcquiredTalent = new("on_player_acquired_talent");
    public static readonly StringName OnStatusChanged = new("on_status_changed");
    public static readonly StringName OnEntityDropped = new("on_entity_dropped");
}
