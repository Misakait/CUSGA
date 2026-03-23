using Godot;
using CUSGA.entities.components;
using CUSGA.core.constants;
namespace CUSGA.core.ui;

public partial class InventoryUI : Control
{
    // SlotUI的scene
    [Export] public PackedScene SlotPrefab { get; set; }

    private GridContainer _slotGrid;

    private InventoryComponent _playerInventory;

    private bool _isInitialized = false;
    private Node _globalEventBus;

    public override void _Ready()
    {
        _slotGrid = GetNode<GridContainer>("%SlotGrid");
        _globalEventBus = GetNode<Node>("/root/GlobalEventBus");
        _globalEventBus.Connect(GDSignals.OnInventoryToggled, Callable.From<InventoryComponent>(HandleInventoryToggleRequest));
    }

    private void HandleInventoryToggleRequest(InventoryComponent inventory)
    {
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
        _playerInventory = inventory;

        if (!_isInitialized)
        {
            GenerateSlots();
            _isInitialized = true;
        }

        Show();
    }

    public void Close()
    {
        Hide();
    }

    private void GenerateSlots()
    {
        for (int i = 0; i < _playerInventory.Capacity; i++)
        {
            var stackData = _playerInventory.Slots[i];

            SlotUI slotUI = SlotPrefab.Instantiate<SlotUI>();
            _slotGrid.AddChild(slotUI);
            slotUI.Init(i, stackData, _playerInventory);
        }
    }
    public override void _ExitTree()
    {
        if (IsConnected(GDSignals.OnInventoryToggled, Callable.From<InventoryComponent>(HandleInventoryToggleRequest)))
        {
            _globalEventBus.Disconnect(GDSignals.OnInventoryToggled, Callable.From<InventoryComponent>(HandleInventoryToggleRequest));
        }
    }
}
