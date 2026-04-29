using Godot;
using CUSGA.entities.components;
using CUSGA.core.constants;
using System.Collections.Generic;
using CUSGA.resources.item;
namespace CUSGA.core.ui;

public partial class InventoryUI : Control
{
    // SlotUI的scene
    [Export] public PackedScene SlotPrefab { get; set; }

    private GridContainer _slotGrid;

    private InventoryComponent _playerInventory;
    private Callable _inventoryToggledCallable;
    private bool _isInitialized = false;
    private Node _globalEventBus;
    private readonly List<SlotUI> _slotViews = [];

    public override void _Ready()
    {
        var closeButton = GetNode<Button>("%CloseButton");
        closeButton.Pressed += Close;
        _inventoryToggledCallable = Callable.From<InventoryComponent>(HandleInventoryToggleRequest);
        _slotGrid = GetNode<GridContainer>("%SlotGrid");
        _globalEventBus = GetNode<Node>("/root/GlobalEventBus");
        if (!_globalEventBus.IsConnected(GDSignals.OnInventoryToggled, _inventoryToggledCallable))
        {
            _globalEventBus.Connect(GDSignals.OnInventoryToggled, _inventoryToggledCallable);
        }
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
        if (_playerInventory != inventory)
        {
            DisconnectInventorySignals();
            GD.Print("InventoryUI bind InventoryComponent");
            _playerInventory = inventory;
            _playerInventory.InventoryChanged += OnInventoryChanged;

            _isInitialized = false;
        }

        if (!_isInitialized)
        {
            GenerateSlots();
            _isInitialized = true;
        }
        RebindAllSlots();
        Show();
    }

    public void Close()
    {
        Hide();
    }
    private void GenerateSlots()
    {
        foreach (Node child in _slotGrid.GetChildren())
        {
            child.QueueFree();
        }

        _slotViews.Clear();

        for (int i = 0; i < _playerInventory.Capacity; i++)
        {
            SlotUI slotUI = SlotPrefab.Instantiate<SlotUI>();
            _slotGrid.AddChild(slotUI);
            _slotViews.Add(slotUI);
        }
    }

    private void RebindAllSlots()
    {
        if (_slotViews.Count != _playerInventory.Capacity)
        {
            GenerateSlots();
        }

        for (int i = 0; i < _slotViews.Count; i++)
        {
            _slotViews[i].Bind(i, _playerInventory.Slots[i], _playerInventory);
        }
    }
    private void OnInventoryChanged()
    {
        // 排序后 _slots[i] 引用整体变了，所以必须重新 Bind
        RebindAllSlots();
    }
    private void DisconnectInventorySignals()
    {
        if (_playerInventory == null)
        {
            return;
        }

        _playerInventory.InventoryChanged -= OnInventoryChanged;
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
        if (_globalEventBus != null &&
                   _globalEventBus.IsConnected(GDSignals.OnInventoryToggled, _inventoryToggledCallable))
        {
            _globalEventBus.Disconnect(GDSignals.OnInventoryToggled, _inventoryToggledCallable);
        }
        DisconnectInventorySignals();
    }
}
