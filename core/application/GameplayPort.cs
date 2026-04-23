using System;
using Godot;
using CUSGA.core.inventory;
using CUSGA.entities;
using CUSGA.resources.interaction;
using CUSGA.resources.monsters;

namespace CUSGA.core.application;

public partial class GameplayPort : Node
{
    [Signal] public delegate void FarmingPanelRequestedEventHandler(TerrainInstance terrain);
    [Signal]
    public delegate void EncounterRequestedEventHandler(
        TerrainInstance terrain,
        MonsterData monster,
        string message
    );

    [Export]
    public NodePath PlayerPath { get; set; } = null!;

    private Player _player = null!;

    public override void _Ready()
    {
        if (PlayerPath.IsEmpty)
        {
            throw new InvalidOperationException("GameplayPort.PlayerPath 未设置。");
        }

        _player = GetNode<Player>(PlayerPath);
    }

    public Player Player => _player;

    public bool TryAddItemToInventory(ItemStack stack)
    {
        ArgumentNullException.ThrowIfNull(stack);
        return _player.TryAddItemToInventory(stack);
    }

    public void RequestOpenFarmingPanel(TerrainInstance terrain)
    {
        EmitSignal(SignalName.FarmingPanelRequested, terrain);
    }

    public void RequestEncounter(TerrainInstance terrain, MonsterData monster, string message)
    {
        EmitSignal(SignalName.EncounterRequested, terrain, monster, message ?? string.Empty);
    }
}
