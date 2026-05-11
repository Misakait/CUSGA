using Godot;
using CUSGA.entities.components;
using System.Collections.Generic;
using CUSGA.core.application;

namespace CUSGA.core.ui;

public partial class InventoryUI : Control
{
    // SlotUI的scene
    [Export] public PackedScene SlotPrefab { get; set; }
    [Export] public NodePath GameplayPortPath { get; set; }

    private GridContainer _slotGrid = null!;
    private GridContainer _deckSlotGrid = null!;
    private GameplayPort _gameplayPort = null!;

    private InventoryComponent _playerInventory = null!;
    private BattleDeckComponent _battleDeck = null!;
    private bool _isInventoryInitialized = false;
    private bool _isDeckInitialized = false;
    // private Node _globalEventBus;
    private readonly List<SlotUI> _slotViews = [];
    private readonly List<SlotUI> _deckSlotViews = [];

    public override void _Ready()
    {
        var closeButton = GetNode<Button>("%CloseButton");
        closeButton.Pressed += Close;
        _slotGrid = GetNode<GridContainer>("%SlotGrid");
        _deckSlotGrid = GetNode<GridContainer>("%DeckSlotGrid");
        _gameplayPort = GetNode<GameplayPort>(GameplayPortPath);
        _gameplayPort.InventoryToggleRequested += HandleInventoryToggleRequest;
        // _globalEventBus = GetNode<Node>("/root/GlobalEventBus");
        // if (!_globalEventBus.IsConnected(GDSignals.OnInventoryToggled, _inventoryToggledCallable))
        // {
        //     _globalEventBus.Connect(GDSignals.OnInventoryToggled, _inventoryToggledCallable);
        // }
        Hide();
    }

    private void HandleInventoryToggleRequest(InventoryComponent inventory)
    {
        if (inventory == null)
        {
            GD.PushError("InventoryUI 收到空 InventoryComponent。");
            return;
        }
        if (Visible)
        {
            Close();
        }
        else
        {
            Open(inventory);
        }
    }

    public void Open(InventoryComponent inventory)
    {
        if (inventory == null)
        {
            GD.PushError("InventoryUI.Open 收到空 InventoryComponent");
            return;
        }

        BindPlayerInventory(inventory);
        BindBattleDeck(_gameplayPort.PlayerBattleDeck);
        if (_battleDeck == null)
        {
            return;
        }

        if (!_isInventoryInitialized)
        {
            GenerateSlots(_slotGrid, _slotViews, _playerInventory);
            _isInventoryInitialized = true;
        }

        if (!_isDeckInitialized)
        {
            GenerateSlots(_deckSlotGrid, _deckSlotViews, _battleDeck);
            _isDeckInitialized = true;
        }

        RebindInventorySlots();
        RebindDeckSlots();
        Show();
    }

    public void Close()
    {
        Hide();
    }
    private void BindPlayerInventory(InventoryComponent inventory)
    {
        if (_playerInventory == inventory)
        {
            return;
        }

        DisconnectInventorySignals();
        GD.Print("InventoryUI bind InventoryComponent");
        _playerInventory = inventory;
        _playerInventory.InventoryChanged += OnInventoryChanged;

        _isInventoryInitialized = false;
    }

    private void BindBattleDeck(BattleDeckComponent battleDeck)
    {
        if (battleDeck == null)
        {
            GD.PushError("InventoryUI 未找到 BattleDeckComponent。");
            return;
        }

        if (_battleDeck == battleDeck)
        {
            return;
        }

        DisconnectBattleDeckSignals();
        _battleDeck = battleDeck;
        _battleDeck.InventoryChanged += OnBattleDeckChanged;

        _isDeckInitialized = false;
    }

    private void GenerateSlots(GridContainer slotGrid, List<SlotUI> slotViews, InventoryComponent inventory)
    {
        foreach (Node child in slotGrid.GetChildren())
        {
            child.QueueFree();
        }

        slotViews.Clear();

        for (int i = 0; i < inventory.Capacity; i++)
        {
            SlotUI slotUI = SlotPrefab.Instantiate<SlotUI>();
            slotGrid.AddChild(slotUI);
            slotViews.Add(slotUI);
        }
    }

    private void RebindInventorySlots()
    {
        if (_slotViews.Count != _playerInventory.Capacity)
        {
            GenerateSlots(_slotGrid, _slotViews, _playerInventory);
        }

        for (int i = 0; i < _slotViews.Count; i++)
        {
            _slotViews[i].Bind(i, _playerInventory.Slots[i], _playerInventory);
        }
    }

    private void RebindDeckSlots()
    {
        if (_deckSlotViews.Count != _battleDeck.Capacity)
        {
            GenerateSlots(_deckSlotGrid, _deckSlotViews, _battleDeck);
        }

        for (int i = 0; i < _deckSlotViews.Count; i++)
        {
            _deckSlotViews[i].Bind(i, _battleDeck.Slots[i], _battleDeck);
        }
    }

    private void OnInventoryChanged()
    {
        // 排序后 _slots[i] 引用整体变了，所以必须重新 Bind
        RebindInventorySlots();
    }

    private void OnBattleDeckChanged()
    {
        RebindDeckSlots();
    }

    private void DisconnectInventorySignals()
    {
        if (_playerInventory == null)
        {
            return;
        }

        _playerInventory.InventoryChanged -= OnInventoryChanged;
    }

    private void DisconnectBattleDeckSignals()
    {
        if (_battleDeck == null)
        {
            return;
        }

        _battleDeck.InventoryChanged -= OnBattleDeckChanged;
    }

    // private void GenerateSlots()
    // {
    //     for (int i = 0; i < _playerInventory.Capacity; i++)
    //     {
    //         var stackData = _playerInventory.Slots[i];

    //         SlotUI slotUI = SlotPrefab.Instantiate<SlotUI>();
    //         _slotGrid.AddChild(slotUI);
    //         slotUI.Bind(i, stackData, _playerInventory);
    //     }
    // }
    public override void _ExitTree()
    {
        _gameplayPort.InventoryToggleRequested -= HandleInventoryToggleRequest;
        DisconnectInventorySignals();
        DisconnectBattleDeckSignals();
    }
}
