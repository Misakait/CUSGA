using Godot;
using CUSGA.core.constants;
using CUSGA.core.inventory;
using CUSGA.core.ui.draggable;
using CUSGA.entities.components;

namespace CUSGA.core.ui;

public partial class EquipmentSlotUI : PanelContainer
{
    private EquipmentSlot _slot;
    private EquipmentComponent _equipment = null!;
    private ItemStack _stack;
    private TextureRect _icon = null!;
    private Label _amountLabel = null!;
    private Label _slotLabel = null!;
    private bool _isReady = false;

    public override void _Ready()
    {
        _icon = GetNode<TextureRect>("%ItemIcon");
        _amountLabel = GetNode<Label>("%AmountLabel");
        _slotLabel = GetNode<Label>("%SlotLabel");
        _isReady = true;
        RefreshView();
    }

    public void Bind(EquipmentComponent equipment, EquipmentSlot slot)
    {
        if (_stack != null)
        {
            _stack.OnStackChanged -= UpdateVisuals;
        }

        _equipment = equipment;
        _slot = slot;
        _stack = null;

        if (_equipment != null && _equipment.TryGetEquippedStack(_slot, out var equippedStack))
        {
            _stack = equippedStack;
            _stack.OnStackChanged += UpdateVisuals;
        }

        RefreshView();
    }

    public override void _ExitTree()
    {
        if (_stack != null)
        {
            _stack.OnStackChanged -= UpdateVisuals;
        }
    }

    public override Variant _GetDragData(Vector2 atPosition)
    {
        if (_equipment == null || _stack == null || _stack.IsEmpty)
        {
            return default;
        }

        DraggableData dataPackage = new()
        {
            SourceSystem = EquipmentComponent.DragSourceSystem,
            SourceEquipment = _equipment,
            FromEquipmentSlot = _slot,
            HeldStack = _stack
        };

        SetDragPreview(CreateDragPreview());
        _icon.Modulate = new Color(1, 1, 1, 0.3f);
        return dataPackage;
    }

    public override bool _CanDropData(Vector2 atPosition, Variant data)
    {
        if (_equipment == null || data.Obj is not DraggableData dragData)
        {
            return false;
        }

        if (dragData.SourceInventory != null)
        {
            return _equipment.CanEquipFromInventory(dragData.SourceInventory, dragData.FromIndex, _slot);
        }

        if (dragData.SourceEquipment != null)
        {
            return dragData.SourceEquipment == _equipment
                && _equipment.CanMoveEquipment(dragData.FromEquipmentSlot, _slot);
        }

        return false;
    }

    public override void _DropData(Vector2 atPosition, Variant data)
    {
        if (_equipment == null || data.Obj is not DraggableData dragData)
        {
            return;
        }

        if (dragData.SourceInventory != null)
        {
            _equipment.EquipFromInventory(dragData.SourceInventory, dragData.FromIndex, _slot);
            return;
        }

        if (dragData.SourceEquipment == _equipment)
        {
            _equipment.MoveEquipment(dragData.FromEquipmentSlot, _slot);
        }
    }

    public override void _Notification(int what)
    {
        if (what == NotificationDragEnd)
        {
            UpdateVisuals(_stack);
        }
    }

    private Control CreateDragPreview()
    {
        TextureRect previewIcon = new()
        {
            Texture = _stack.Item.CardIcon,
            ExpandMode = TextureRect.ExpandModeEnum.IgnoreSize,
            CustomMinimumSize = new Vector2(64, 64),
            Modulate = new Color(1, 1, 1, 0.8f)
        };

        Control previewWrapper = new();
        previewIcon.Position = -previewIcon.CustomMinimumSize / 2;
        previewWrapper.AddChild(previewIcon);

        return previewWrapper;
    }

    private void UpdateVisuals(ItemStack stack)
    {
        if (!_isReady)
        {
            return;
        }

        if (stack == null || stack.IsEmpty)
        {
            _icon.Texture = null;
            _amountLabel.Text = "";
        }
        else
        {
            _icon.Texture = stack.Item.CardIcon;
            _amountLabel.Text = stack.Amount > 1 ? stack.Amount.ToString() : "";
        }
        _icon.Modulate = Colors.White;
    }

    private void RefreshView()
    {
        if (!_isReady)
        {
            return;
        }

        _slotLabel.Text = GetSlotLabel(_slot);
        UpdateVisuals(_stack);
    }

    private static string GetSlotLabel(EquipmentSlot slot)
    {
        return slot switch
        {
            EquipmentSlot.Helmet => "头盔",
            EquipmentSlot.Chest => "胸甲",
            EquipmentSlot.Legs => "护腿",
            EquipmentSlot.Boots => "靴子",
            EquipmentSlot.Weapon => "武器",
            EquipmentSlot.Axe => "斧头",
            EquipmentSlot.Pickaxe => "镐子",
            EquipmentSlot.FishingRod => "鱼竿",
            _ => slot.ToString()
        };
    }
}
