using Godot;
using CUSGA.core.inventory;
using CUSGA.core.ui.draggable;
using CUSGA.entities.components;
using CUSGA.core.constants;

namespace CUSGA.core.ui;

public partial class SlotUI : Panel
{
    private int _myIndex; // 该格子背包里的真实坐标
    private ItemStack _itemStackInThisSlot; // 当前渲染的数据引用
    private InventoryComponent _inventoryComponent; //  Player 身上的 InventoryComponent 引用

    // UI 局部刷新逻辑 (监听数据变动)
    public void Init(int index, ItemStack stack, InventoryComponent uiManager)
    {
        _myIndex = index;
        _itemStackInThisSlot = stack;
        _inventoryComponent = uiManager;
        // 如果内存里的格子数据变了，自动更新画面
        stack.OnStackChanged += UpdateVisuals;
        UpdateVisuals(stack); // 初始化画面
    }


    // 开始拖拽
    public override Variant _GetDragData(Vector2 atPosition)
    {
        // 如果这个格子没数据，或者物品是空的，不准拖拽
        if (_itemStackInThisSlot == null || _itemStackInThisSlot.IsEmpty) return default;

        // 生成数据快递包
        DraggableData dataPackage = new()
        {
            SourceSystem = TagConsts.SystemInventory,
            FromIndex = _myIndex,
            HeldStack = _itemStackInThisSlot
        };

        var preview = CreateDragPreview();
        SetDragPreview(preview);

        GetNode<TextureRect>("%ItemIcon").Modulate = new Color(1, 1, 1, 0.3f);
        return dataPackage;
    }
    private Control CreateDragPreview()
    {
        TextureRect previewIcon = new()
        {
            Texture = _itemStackInThisSlot.Item.Icon,
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
        if (data.Obj is DraggableData _dragData)
        {
            // (如果是装备栏格子，这里就要检查 item.ValidSlots 里是否包含装备栏类型)
            return true;
        }
        return false;
    }

    public override void _DropData(Vector2 atPosition, Variant data)
    {
        if (data.Obj is DraggableData dragData)
        {
            int from = dragData.FromIndex;
            int to = _myIndex;

            GD.Print($"[UI交互] 玩家要把格 {from} 的物品拖到格 {to}。");

            _inventoryComponent.MoveItem(from, to);
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
            icon.Texture = stack.Item.Icon;
            amountLabel.Text = stack.Amount > 1 ? stack.Amount.ToString() : "";
        }
        icon.Modulate = Colors.White;
    }
    public override void _Notification(int what)
    {
        if (what == NotificationDragEnd)
        {
            UpdateVisuals(_itemStackInThisSlot);
        }
    }
}
