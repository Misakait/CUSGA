using Godot;
using System;
using CUSGA.core.constants;
using CUSGA.core.inventory;
using CUSGA.entities;
using CUSGA.entities.components;
using CUSGA.resources.debugging;

namespace CUSGA.core.debugging;

public partial class DebugLoadoutSeeder : Node
{
    [Export] public bool Enabled { get; set; } = true;
    [Export] public bool DebugBuildOnly { get; set; } = true;
    [Export] public bool ApplyOnce { get; set; } = true;
    [Export] public bool ClearInventoryBeforeApply { get; set; } = true;
    [Export] public bool ClearBattleDeckBeforeApply { get; set; } = true;
    [Export] public bool ClearEquipmentBeforeApply { get; set; } = true;
    [Export] public NodePath PlayerPath { get; set; } = new("../Player");
    [Export] public DebugLoadoutData Loadout { get; set; }

    private bool _hasApplied;

    public override void _Ready()
    {
        if (!Enabled || (DebugBuildOnly && !OS.IsDebugBuild()))
        {
            return;
        }

        CallDeferred(nameof(ApplyLoadout));
    }

    public void ApplyLoadout()
    {
        if (ApplyOnce && _hasApplied)
        {
            return;
        }

        if (Loadout == null)
        {
            GD.PushWarning($"{nameof(DebugLoadoutSeeder)} has no loadout assigned.");
            return;
        }

        var player = GetNodeOrNull<Player>(PlayerPath);
        if (player == null)
        {
            GD.PushWarning($"{nameof(DebugLoadoutSeeder)} could not find Player.");
            return;
        }

        var inventory = player.GetNodeOrNull<InventoryComponent>("Components/InventoryComponent");
        var battleDeck = player.GetNodeOrNull<BattleDeckComponent>("Components/BattleDeckComponent");
        var equipment = player.GetNodeOrNull<EquipmentComponent>("Components/EquipmentComponent");
        var attributes = player.GetNodeOrNull<AttributeComponent>("Components/AttributeComponent");

        if (inventory == null)
        {
            GD.PushWarning($"{nameof(DebugLoadoutSeeder)} could not find InventoryComponent.");
            return;
        }

        if (Loadout.PlayerStartingStats != null && attributes.InitialData == null)
        {
            GD.Print("[Seeder] PlayerStartingStats", Loadout.PlayerStartingStats);
            attributes.InitializeWithData(Loadout.PlayerStartingStats);
        }

        if (ClearEquipmentBeforeApply && equipment != null)
        {
            ClearEquipment(equipment);
        }

        if (ClearInventoryBeforeApply)
        {
            ClearInventory(inventory);
        }

        if (ClearBattleDeckBeforeApply && battleDeck != null)
        {
            ClearInventory(battleDeck);
        }

        FillInventory(inventory, Loadout.InventoryItems);
        FillGeneratedEquipment(inventory, Loadout.InventoryEquipment);

        if (battleDeck != null)
        {
            FillInventory(battleDeck, Loadout.BattleDeckItems);
        }

        if (equipment != null)
        {
            EquipGeneratedEquipment(equipment, Loadout.EquippedEquipment);
        }

        _hasApplied = true;
    }

    private static void FillInventory(InventoryComponent inventory, Godot.Collections.Array<DebugItemStackEntry> entries)
    {
        foreach (var entry in entries)
        {
            if (entry == null)
            {
                continue;
            }

            AddStackToFirstAvailableSlot(inventory, entry.CreateStack());
        }
    }

    private static void FillGeneratedEquipment(
        InventoryComponent inventory,
        Godot.Collections.Array<DebugGeneratedEquipmentEntry> entries
    )
    {
        foreach (var entry in entries)
        {
            if (entry == null)
            {
                continue;
            }

            AddStackToFirstAvailableSlot(inventory, entry.CreateStack());
        }
    }

    private static void EquipGeneratedEquipment(
        EquipmentComponent equipment,
        Godot.Collections.Array<DebugGeneratedEquipmentEntry> entries
    )
    {
        foreach (var entry in entries)
        {
            if (entry == null)
            {
                continue;
            }

            equipment.Equip(entry.CreateStack(), entry.Slot);
        }
    }

    private static void AddStackToFirstAvailableSlot(InventoryComponent inventory, ItemStack stack)
    {
        if (stack == null || stack.IsEmpty)
        {
            return;
        }

        for (int i = 0; i < inventory.Capacity; i++)
        {
            if (!inventory.GetStackAt(i).IsEmpty)
            {
                continue;
            }

            if (inventory.TrySetStackAt(i, stack))
            {
                return;
            }
        }

        GD.PushWarning($"Debug loadout could not fit item '{stack.Item?.CardName}' into {inventory.Name}.");
    }

    private static void ClearInventory(InventoryComponent inventory)
    {
        for (int i = 0; i < inventory.Capacity; i++)
        {
            inventory.TryClearStackAt(i);
        }
    }

    private static void ClearEquipment(EquipmentComponent equipment)
    {
        foreach (EquipmentSlot slot in Enum.GetValues<EquipmentSlot>())
        {
            equipment.Unequip(slot);
        }
    }
}
