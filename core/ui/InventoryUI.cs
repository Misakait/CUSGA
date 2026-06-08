using Godot;
using CUSGA.entities.components;
using CUSGA.core.constants;
using System;
using System.Collections.Generic;
using CUSGA.core.application;
using CUSGA.resources.item.card;

namespace CUSGA.core.ui;

public partial class InventoryUI : Control
{
    // SlotUI的scene
    [Export] public PackedScene SlotPrefab { get; set; }
    [Export] public PackedScene EquipmentSlotPrefab { get; set; }
    [Export] public NodePath GameplayPortPath { get; set; }
    [Export] public NodePath TooltipPanelPath { get; set; } = new("../../TooltipPanel");

    private AttributeSummaryUI _attributeSummary = null!;
    private GridContainer _slotGrid = null!;
    private GridContainer _equipmentSlotGrid = null!;
    private GridContainer _deckSlotGrid = null!;
    private GameplayPort _gameplayPort = null!;
    private ItemTooltipPresenter _tooltipPresenter = ItemTooltipPresenter.Empty;

    private InventoryComponent _playerInventory = null!;
    private EquipmentComponent _equipment = null!;
    private BattleDeckComponent _battleDeck = null!;
    private bool _isInventoryInitialized = false;
    private bool _isEquipmentInitialized = false;
    private bool _isDeckInitialized = false;
    // private Node _globalEventBus;
    private readonly List<SlotUI> _slotViews = [];
    private readonly List<EquipmentSlotUI> _equipmentSlotViews = [];
    private readonly List<SlotUI> _deckSlotViews = [];

    public override void _Ready()
    {
        var closeButton = GetNode<Button>("%CloseButton");
        closeButton.Pressed += Close;
        _attributeSummary = GetNode<AttributeSummaryUI>("%AttributeSummaryUI");
        _slotGrid = GetNode<GridContainer>("%SlotGrid");
        _equipmentSlotGrid = GetNode<GridContainer>("%EquipmentSlotGrid");
        _deckSlotGrid = GetNode<GridContainer>("%DeckSlotGrid");
        _gameplayPort = GetNode<GameplayPort>(GameplayPortPath);
        _tooltipPresenter = new ItemTooltipPresenter(GetNodeOrNull<Node>(TooltipPanelPath));
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
        _attributeSummary.Bind(_gameplayPort.Player.Attributes);
        BindEquipment(_gameplayPort.Player.Equipment);
        BindBattleDeck(_gameplayPort.PlayerBattleDeck);
        if (_equipment == null || _battleDeck == null)
        {
            return;
        }

        if (!_isInventoryInitialized)
        {
            GenerateSlots(_slotGrid, _slotViews, _playerInventory);
            _isInventoryInitialized = true;
        }

        if (!_isEquipmentInitialized)
        {
            GenerateEquipmentSlots();
            _isEquipmentInitialized = true;
        }

        if (!_isDeckInitialized)
        {
            GenerateSlots(_deckSlotGrid, _deckSlotViews, _battleDeck);
            _isDeckInitialized = true;
        }

        RebindInventorySlots();
        RebindEquipmentSlots();
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

    private void BindEquipment(EquipmentComponent equipment)
    {
        if (equipment == null)
        {
            GD.PushError("InventoryUI 未找到 EquipmentComponent。");
            return;
        }

        if (_equipment == equipment)
        {
            return;
        }

        DisconnectEquipmentSignals();
        _equipment = equipment;
        _equipment.EquipmentChanged += OnEquipmentChanged;

        _isEquipmentInitialized = false;
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

    private void GenerateEquipmentSlots()
    {
        foreach (Node child in _equipmentSlotGrid.GetChildren())
        {
            child.QueueFree();
        }

        _equipmentSlotViews.Clear();

        foreach (EquipmentSlot slot in Enum.GetValues<EquipmentSlot>())
        {
            EquipmentSlotUI slotUI = EquipmentSlotPrefab.Instantiate<EquipmentSlotUI>();
            _equipmentSlotGrid.AddChild(slotUI);
            slotUI.SetTooltipPresenter(_tooltipPresenter);
            slotUI.Bind(_equipment, slot);
            _equipmentSlotViews.Add(slotUI);
        }
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
            slotUI.SetTooltipPresenter(_tooltipPresenter);
            slotUI.SetShortcutHandler(HandleSlotShortcut);
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

    private void RebindEquipmentSlots()
    {
        if (_equipmentSlotViews.Count != Enum.GetValues<EquipmentSlot>().Length)
        {
            GenerateEquipmentSlots();
            return;
        }

        int index = 0;
        foreach (EquipmentSlot slot in Enum.GetValues<EquipmentSlot>())
        {
            _equipmentSlotViews[index].Bind(_equipment, slot);
            index++;
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

    private void OnEquipmentChanged()
    {
        RebindEquipmentSlots();
    }

    private void OnBattleDeckChanged()
    {
        RebindDeckSlots();
    }

    private void HandleSlotShortcut(SlotUI slotUI, SlotShortcutKind shortcutKind)
    {
        if (slotUI == null || _playerInventory == null || _battleDeck == null || _equipment == null)
        {
            return;
        }

        InventoryComponent sourceInventory = slotUI.Inventory;
        if (sourceInventory == null)
        {
            return;
        }

        if (shortcutKind == SlotShortcutKind.AltClick)
        {
            HandleAltClickShortcut(slotUI, sourceInventory);
            return;
        }

        HandleShiftClickShortcut(slotUI, sourceInventory);
    }

    private void HandleAltClickShortcut(SlotUI slotUI, InventoryComponent sourceInventory)
    {
        if (sourceInventory == _battleDeck)
        {
            _battleDeck.MoveAllMatchingStacksTo(_playerInventory, item => item is SkillCardData);
            return;
        }

        if (sourceInventory == _playerInventory && slotUI.CurrentStack?.Item is SkillCardData)
        {
            _playerInventory.MoveAllMatchingStacksTo(_battleDeck, item => item is SkillCardData);
        }
    }

    private void HandleShiftClickShortcut(SlotUI slotUI, InventoryComponent sourceInventory)
    {
        if (slotUI.CurrentStack == null || slotUI.CurrentStack.IsEmpty)
        {
            return;
        }

        if (sourceInventory == _battleDeck && slotUI.CurrentStack.Item is SkillCardData)
        {
            _battleDeck.TryMoveStackToFirstAvailableSlot(_playerInventory, slotUI.SlotIndex);
            return;
        }

        if (sourceInventory != _playerInventory)
        {
            return;
        }

        if (slotUI.CurrentStack.Item is SkillCardData)
        {
            _playerInventory.TryMoveStackToFirstAvailableSlot(_battleDeck, slotUI.SlotIndex);
            return;
        }

        _equipment.EquipFromInventoryToBestSlot(_playerInventory, slotUI.SlotIndex);
    }

    private void DisconnectInventorySignals()
    {
        if (_playerInventory == null)
        {
            return;
        }

        _playerInventory.InventoryChanged -= OnInventoryChanged;
    }

    private void DisconnectEquipmentSignals()
    {
        if (_equipment == null)
        {
            return;
        }

        _equipment.EquipmentChanged -= OnEquipmentChanged;
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
        DisconnectEquipmentSignals();
        DisconnectBattleDeckSignals();
    }
}
