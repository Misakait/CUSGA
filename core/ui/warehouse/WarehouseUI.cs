using Godot;
using System.Collections.Generic;
using CUSGA.core.application;
using CUSGA.entities.components;

namespace CUSGA.core.ui.warehouse;

public partial class WarehouseUI : Control
{
    [Export] public PackedScene SlotPrefab { get; set; }
    [Export] public NodePath GameplayPortPath { get; set; }
    [Export] public NodePath TooltipPanelPath { get; set; } = new("../../TooltipPanel");

    private GameplayPort _gameplayPort = null!;
    private GridContainer _playerSlotGrid = null!;
    private GridContainer _warehouseSlotGrid = null!;
    private ItemTooltipPresenter _tooltipPresenter = ItemTooltipPresenter.Empty;
    private InventoryComponent _playerInventory = null!;
    private InventoryComponent _warehouseInventory = null!;
    private readonly List<SlotUI> _playerSlotViews = [];
    private readonly List<SlotUI> _warehouseSlotViews = [];

    public override void _Ready()
    {
        _playerSlotGrid = GetNode<GridContainer>("%PlayerSlotGrid");
        _warehouseSlotGrid = GetNode<GridContainer>("%WarehouseSlotGrid");
        var closeButton = GetNode<Button>("%CloseButton");
        closeButton.Pressed += Close;
        StyleBoxFlat normalStyle = new()
        {
            BgColor = new Color(0.25f, 0.25f, 0.25f, 1.0f)
        };
        normalStyle.SetCornerRadiusAll(4);
        StyleBoxFlat hoverStyle = new()
        {
            BgColor = new Color(0.35f, 0.35f, 0.35f, 1.0f)
        };
        hoverStyle.SetCornerRadiusAll(4);


        closeButton.AddThemeStyleboxOverride("normal", normalStyle);
        closeButton.AddThemeStyleboxOverride("hover", hoverStyle);

        _gameplayPort = GetNode<GameplayPort>(GameplayPortPath);
        _tooltipPresenter = new ItemTooltipPresenter(GetNodeOrNull<Node>(TooltipPanelPath));
        _gameplayPort.WarehouseRequested += HandleWarehouseRequested;

        Hide();
    }

    private void HandleWarehouseRequested(InventoryComponent playerInventory, InventoryComponent warehouseInventory)
    {
        if (playerInventory == null || warehouseInventory == null)
        {
            GD.PushError("WarehouseUI 收到空 InventoryComponent。");
            return;
        }

        Open(playerInventory, warehouseInventory);
    }

    public void Open(InventoryComponent playerInventory, InventoryComponent warehouseInventory)
    {
        BindInventories(playerInventory, warehouseInventory);
        RebindPlayerSlots();
        RebindWarehouseSlots();
        Show();
    }

    public void Close()
    {
        _tooltipPresenter.Hide();
        Hide();
    }

    private void BindInventories(InventoryComponent playerInventory, InventoryComponent warehouseInventory)
    {
        if (_playerInventory != playerInventory)
        {
            DisconnectPlayerInventorySignal();
            _playerInventory = playerInventory;
            _playerInventory.InventoryChanged += OnPlayerInventoryChanged;
            _playerSlotViews.Clear();
        }

        if (_warehouseInventory != warehouseInventory)
        {
            DisconnectWarehouseInventorySignal();
            _warehouseInventory = warehouseInventory;
            _warehouseInventory.InventoryChanged += OnWarehouseInventoryChanged;
            _warehouseSlotViews.Clear();
        }
    }

    private void RebindPlayerSlots()
    {
        RebindSlots(_playerSlotGrid, _playerSlotViews, _playerInventory);
    }

    private void RebindWarehouseSlots()
    {
        RebindSlots(_warehouseSlotGrid, _warehouseSlotViews, _warehouseInventory);
    }

    private void RebindSlots(GridContainer slotGrid, List<SlotUI> slotViews, InventoryComponent inventory)
    {
        if (inventory == null)
        {
            return;
        }

        if (slotViews.Count != inventory.Capacity)
        {
            GenerateSlots(slotGrid, slotViews, inventory.Capacity);
        }

        for (int i = 0; i < slotViews.Count; i++)
        {
            slotViews[i].Bind(i, inventory.Slots[i], inventory);
        }
    }

    private void GenerateSlots(GridContainer slotGrid, List<SlotUI> slotViews, int capacity)
    {
        foreach (Node child in slotGrid.GetChildren())
        {
            child.QueueFree();
        }

        slotViews.Clear();
        for (int i = 0; i < capacity; i++)
        {
            SlotUI slotUI = SlotPrefab.Instantiate<SlotUI>();
            slotGrid.AddChild(slotUI);
            slotUI.SetTooltipPresenter(_tooltipPresenter);
            slotViews.Add(slotUI);
        }
    }

    private void OnPlayerInventoryChanged()
    {
        RebindPlayerSlots();
    }

    private void OnWarehouseInventoryChanged()
    {
        RebindWarehouseSlots();
    }

    private void DisconnectPlayerInventorySignal()
    {
        if (_playerInventory != null)
        {
            _playerInventory.InventoryChanged -= OnPlayerInventoryChanged;
        }
    }

    private void DisconnectWarehouseInventorySignal()
    {
        if (_warehouseInventory != null)
        {
            _warehouseInventory.InventoryChanged -= OnWarehouseInventoryChanged;
        }
    }

    public override void _ExitTree()
    {
        if (_gameplayPort != null)
        {
            _gameplayPort.WarehouseRequested -= HandleWarehouseRequested;
        }

        DisconnectPlayerInventorySignal();
        DisconnectWarehouseInventorySignal();
        _tooltipPresenter.Hide();
    }
}
