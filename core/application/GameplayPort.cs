using System;
using Godot;
using CUSGA.core.inventory;
using CUSGA.entities;
using CUSGA.resources.interaction;
using CUSGA.resources.monsters;
using CUSGA.entities.components;

namespace CUSGA.core.application;

public partial class GameplayPort : Node
{
    [Signal] public delegate void InventoryToggleRequestedEventHandler(InventoryComponent inventory);
    [Signal] public delegate void FarmingPanelRequestedEventHandler(TerrainInstance terrain);
    [Signal]
    public delegate void EncounterRequestedEventHandler(
        TerrainInstance terrain,
        MonsterData monster,
        string message
    );

    [Export]
    public NodePath PlayerPath { get; set; } = null!;
    [Export] public NodePath PlayerInventoryPath { get; set; } = new("Components/InventoryComponent");
    [Export] public NodePath PlayerHealthPath { get; set; } = new("Components/HealthComponent");

    private Player _player = null!;
    private HealthComponent _playerHealth = null!;

    public HealthComponent PlayerHealth =>
           _playerHealth;
    public InventoryComponent PlayerInventory =>
            _playerInventory;

    public override void _Ready()
    {
        if (PlayerPath.IsEmpty)
        {
            throw new InvalidOperationException("GameplayPort.PlayerPath 未设置。");
        }

        _player = GetNode<Player>(PlayerPath);
        _playerInventory = _player.GetNode<InventoryComponent>(PlayerInventoryPath);
        _playerHealth = _player.GetNode<HealthComponent>(PlayerHealthPath);
    }

    public Player Player => _player;
    private InventoryComponent _playerInventory = null!;

    public void RequestToggleInventory()
    {
        EmitSignal(SignalName.InventoryToggleRequested, PlayerInventory);
    }

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
