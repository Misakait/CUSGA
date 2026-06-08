using Godot;
using System;
using CUSGA.core.inventory;
using CUSGA.core.ui.draggable;
using CUSGA.entities.components;

namespace CUSGA.core.ui;

/// <summary>
/// 表示背包格子收到的快捷点击类型。
/// </summary>
public enum SlotShortcutKind
{
    /// <summary>
    /// Shift + 左键点击单个格子。
    /// </summary>
    ShiftClick,

    /// <summary>
    /// Alt + 左键点击单个格子。
    /// </summary>
    AltClick
}

public partial class SlotUI : PanelContainer
{
    private int _myIndex; // 该格子背包里的真实坐标
    private ItemStack _itemStackInThisSlot; // 当前渲染的数据引用
    private InventoryComponent _inventoryComponent; //  Player 身上的 InventoryComponent 引用
    private ItemTooltipPresenter _tooltipPresenter = ItemTooltipPresenter.Empty;
    private Action<SlotUI, SlotShortcutKind> _shortcutHandler;
    private bool _isPointerInside;

    /// <summary>
    /// 获取此 UI 格子当前绑定的背包槽位索引。
    /// </summary>
    /// <value>背包组件中的真实槽位索引。</value>
    public int SlotIndex => _myIndex;

    /// <summary>
    /// 获取此 UI 格子当前绑定的背包组件。
    /// </summary>
    /// <value>背包、出战卡组或其他继承自背包的组件。</value>
    public InventoryComponent Inventory => _inventoryComponent;

    /// <summary>
    /// 获取此 UI 格子当前渲染的物品堆叠。
    /// </summary>
    /// <value>当前槽位的物品堆叠引用。</value>
    public ItemStack CurrentStack => _itemStackInThisSlot;

    public override void _Ready()
    {
        Resized += OnResized;
        MouseEntered += OnMouseEntered;
        MouseExited += OnMouseExited;
    }
    private void OnResized()
    {
        if (!Mathf.IsEqualApprox(CustomMinimumSize.Y, Size.X))
        {
            CustomMinimumSize = new Vector2(CustomMinimumSize.X, Size.X);
        }
    }
    public void Bind(int index, ItemStack stack, InventoryComponent inventory)
    {
        if (_itemStackInThisSlot != null)
        {
            _itemStackInThisSlot.OnStackChanged -= UpdateVisuals;
        }

        _myIndex = index;
        _itemStackInThisSlot = stack;
        _inventoryComponent = inventory;

        if (_itemStackInThisSlot != null)
        {
            _itemStackInThisSlot.OnStackChanged += UpdateVisuals;
        }

        UpdateVisuals(_itemStackInThisSlot);
    }

    public void SetTooltipPresenter(ItemTooltipPresenter tooltipPresenter)
    {
        _tooltipPresenter = tooltipPresenter ?? ItemTooltipPresenter.Empty;
    }

    /// <summary>
    /// 设置此格子的快捷点击处理器。
    /// </summary>
    /// <param name="shortcutHandler">收到快捷点击时调用的处理器。</param>
    public void SetShortcutHandler(Action<SlotUI, SlotShortcutKind> shortcutHandler)
    {
        _shortcutHandler = shortcutHandler;
    }

    public override void _ExitTree()
    {
        MouseEntered -= OnMouseEntered;
        MouseExited -= OnMouseExited;

        if (_itemStackInThisSlot != null)
        {
            _itemStackInThisSlot.OnStackChanged -= UpdateVisuals;
        }

        _tooltipPresenter.Hide();
    }

    /// <inheritdoc />
    public override void _GuiInput(InputEvent @event)
    {
        if (@event is not InputEventMouseButton
            {
                Pressed: true,
                ButtonIndex: MouseButton.Left
            } mouseEvent)
        {
            return;
        }

        if (mouseEvent.AltPressed)
        {
            _shortcutHandler?.Invoke(this, SlotShortcutKind.AltClick);
            AcceptEvent();
            return;
        }

        if (mouseEvent.ShiftPressed)
        {
            _shortcutHandler?.Invoke(this, SlotShortcutKind.ShiftClick);
            AcceptEvent();
        }
    }

    // 开始拖拽
    public override Variant _GetDragData(Vector2 atPosition)
    {
        // 如果这个格子没数据，或者物品是空的，不准拖拽
        if (_itemStackInThisSlot == null || _itemStackInThisSlot.IsEmpty)
        {
            return default;
        }

        // 生成数据快递包
        DraggableData dataPackage = new()
        {
            SourceSystem = _inventoryComponent.DragSourceSystem,
            FromIndex = _myIndex,
            SourceInventory = _inventoryComponent,
            HeldStack = _itemStackInThisSlot
        };

        var preview = CreateDragPreview();
        SetDragPreview(preview);

        GetNode<TextureRect>("%ItemIcon").Modulate = new Color(1, 1, 1, 0.3f);
        _tooltipPresenter.Hide();
        return dataPackage;
    }
    private Control CreateDragPreview()
    {
        TextureRect previewIcon = new()
        {
            Texture = _itemStackInThisSlot.Item.CardIcon,
            ExpandMode = TextureRect.ExpandModeEnum.IgnoreSize,
            CustomMinimumSize = new Vector2(64, 64),
            Modulate = new Color(1, 1, 1, 0.8f)
        };

        // 创建一个空的 Control 作为父节点，把图标往左上角偏移一半
        // 这样玩家鼠标拖拽时，鼠标指针刚好在图标的正中心
        Control previewWrapper = new();
        previewIcon.Position = -previewIcon.CustomMinimumSize / 2;
        previewWrapper.AddChild(previewIcon);

        return previewWrapper;
    }

    public override bool _CanDropData(Vector2 atPosition, Variant data)
    {
        if (data.Obj is DraggableData dragData)
        {
            if (_inventoryComponent == null)
            {
                return false;
            }

            if (dragData.SourceInventory != null)
            {
                return _inventoryComponent.CanReceiveItemFrom(dragData.SourceInventory, dragData.FromIndex, _myIndex);
            }

            if (dragData.SourceEquipment != null)
            {
                return dragData.SourceEquipment.CanUnequipToInventory(
                    dragData.FromEquipmentSlot,
                    _inventoryComponent,
                    _myIndex
                );
            }
        }
        return false;
    }

    public override void _DropData(Vector2 atPosition, Variant data)
    {
        if (data.Obj is DraggableData dragData)
        {
            if (dragData.SourceInventory != null)
            {
                int from = dragData.FromIndex;
                int to = _myIndex;

                GD.Print($"[UI交互] 玩家要把{dragData.SourceInventory.DragSourceSystem}背包格 {from} 的物品拖到{_inventoryComponent.DragSourceSystem}格 {to}。");

                _inventoryComponent.MoveItemFrom(dragData.SourceInventory, from, to);
                return;
            }

            if (dragData.SourceEquipment != null)
            {
                GD.Print($"[UI交互] 玩家要把装备槽 {dragData.FromEquipmentSlot} 的装备拖到{_inventoryComponent.DragSourceSystem}格 {_myIndex}。");
                dragData.SourceEquipment.UnequipToInventory(
                    dragData.FromEquipmentSlot,
                    _inventoryComponent,
                    _myIndex
                );
            }
        }
    }
    private void UpdateVisuals(ItemStack stack)
    {
        var icon = GetNode<TextureRect>("%ItemIcon");
        var amountLabel = GetNode<Label>("%AmountLabel");

        if (stack == null || stack.IsEmpty)
        {
            icon.Texture = null;
            amountLabel.Text = "";
        }
        else
        {
            icon.Texture = stack.Item.CardIcon;
            amountLabel.Text = stack.Amount > 1 ? stack.Amount.ToString() : "";
        }
        icon.Modulate = Colors.White;

        if (_isPointerInside)
        {
            _tooltipPresenter.Show(stack);
        }
    }

    private void OnMouseEntered()
    {
        _isPointerInside = true;
        _tooltipPresenter.Show(_itemStackInThisSlot);
    }

    private void OnMouseExited()
    {
        _isPointerInside = false;
        _tooltipPresenter.Hide();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationDragEnd)
        {
            UpdateVisuals(_itemStackInThisSlot);
        }
    }
}
