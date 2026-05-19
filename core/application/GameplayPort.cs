using System;
using Godot;
using CUSGA.core.inventory;
using CUSGA.entities;
using CUSGA.resources.interaction;
using CUSGA.resources.monsters;
using CUSGA.entities.components;
using CUSGA.resources.item.card;
using Godot.Collections;

namespace CUSGA.core.application;

public partial class GameplayPort : Node
{
    [Signal] public delegate void InventoryToggleRequestedEventHandler(InventoryComponent inventory);
    [Signal] public delegate void CraftingToggleRequestedEventHandler(CraftingComponent crafting);
    [Signal] public delegate void FarmingPanelRequestedEventHandler(TerrainInstance terrain);
    [Signal] public delegate void WarehouseRequestedEventHandler(InventoryComponent playerInventory, InventoryComponent warehouseInventory);
    [Signal]
    public delegate void EncounterRequestedEventHandler(
        TerrainInstance terrain,
        Array<SkillCardData> battleDeck,
        Array<MonsterData> monsters,
        string message
    );

    [Export]
    public NodePath PlayerPath { get; set; } = null!;
    [Export] public NodePath PlayerInventoryPath { get; set; } = new("Components/InventoryComponent");
    [Export] public NodePath PlayerBattleDeckPath { get; set; } = new("Components/BattleDeckComponent");
    [Export] public NodePath PlayerHealthPath { get; set; } = new("Components/HealthComponent");
    [Export] public NodePath PlayerCraftingPath { get; set; } = new("Components/CraftingComponent");
    [Export] public NodePath GlobalWarehousePath { get; set; } = new("/root/GlobalWarehouse");

    private Player _player = null!;
    private InventoryComponent _playerInventory = null!;
    private HealthComponent _playerHealth = null!;
    private BattleDeckComponent _playerBattleDeck = null!;
    private CraftingComponent _playerCrafting = null!;
    private InventoryComponent _globalWarehouseInventory = null!;

    public HealthComponent PlayerHealth =>
           _playerHealth;
    public InventoryComponent PlayerInventory =>
            _playerInventory;
    public BattleDeckComponent PlayerBattleDeck =>
            _playerBattleDeck;
    public CraftingComponent PlayerCrafting =>
            _playerCrafting;
    public InventoryComponent GlobalWarehouseInventory =>
            _globalWarehouseInventory;

    public override void _Ready()
    {
        if (PlayerPath.IsEmpty)
        {
            throw new InvalidOperationException("GameplayPort.PlayerPath 未设置");
        }

        _player = GetNode<Player>(PlayerPath);
        _playerInventory = _player.GetNode<InventoryComponent>(PlayerInventoryPath);
        _playerBattleDeck = _player.GetNode<BattleDeckComponent>(PlayerBattleDeckPath);
        _playerHealth = _player.GetNode<HealthComponent>(PlayerHealthPath);
        _playerCrafting = _player.GetNode<CraftingComponent>(PlayerCraftingPath);
        _globalWarehouseInventory = GetNodeOrNull<InventoryComponent>(GlobalWarehousePath);
    }

    public Player Player => _player;

    public void RequestToggleInventory()
    {
        EmitSignal(SignalName.InventoryToggleRequested, PlayerInventory);
    }

    public void RequestToggleCrafting()
    {
        EmitSignal(SignalName.CraftingToggleRequested, PlayerCrafting);
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

    public void RequestOpenWarehouse()
    {
        if (GlobalWarehouseInventory == null)
        {
            GD.PushError("GameplayPort 未绑定全局仓库 InventoryComponent。");
            return;
        }

        EmitSignal(SignalName.WarehouseRequested, PlayerInventory, GlobalWarehouseInventory);
    }

    public void RequestEncounter(TerrainInstance terrain, MonsterData monster, string message)
    {
        Array<MonsterData> monsters = [];
        if (monster != null)
        {
            monsters.Add(monster);
        }

        RequestEncounter(terrain, monsters, message);
    }

    public void RequestEncounter(TerrainInstance terrain, Array<MonsterData> monsters, string message)
    {
        GD.Print($"RequestEncounter: terrain={terrain}, monsters={monsters}, message={message}");
        EmitSignal(
            SignalName.EncounterRequested,
            terrain,
            PlayerBattleDeck.GetSkillCards(),
            monsters ?? [],
            message ?? string.Empty
        );
    }
}
