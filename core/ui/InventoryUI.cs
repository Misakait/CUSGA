using Godot;
using CUSGA.entities.components;
namespace CUSGA.core.ui;

public partial class InventoryUI : Control
{
    // SlotUI的scene
    [Export] public PackedScene SlotPrefab { get; set; }

    private GridContainer _slotGrid;

    private InventoryComponent _playerInventory;

    private bool _isInitialized = false;

    public override void _Ready()
    {
        _slotGrid = GetNode<GridContainer>("%SlotGrid");
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
}
