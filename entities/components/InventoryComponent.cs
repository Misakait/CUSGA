using Godot;
using System;
using System.Collections.Generic;
using CUSGA.resources.item;
using CUSGA.core.inventory;
using CUSGA.core.crafting;
using System.Linq;
using CUSGA.core.constants;

namespace CUSGA.entities.components;

public partial class InventoryComponent : Node, ICraftingInventory
{
    [Export] public int Capacity { get; private set; } = 27; // 背包格子数
    [Signal] public delegate void InventoryChangedEventHandler();

    private ItemStack[] _slots = null!;

    public virtual StringName DragSourceSystem => TagConsts.SystemInventory;

    public override void _Ready()
    {
        // 初始化所有的空箱子
        _slots = new ItemStack[Capacity];
        for (int i = 0; i < Capacity; i++)
        {
            _slots[i] = new ItemStack();
        }
    }

    private void EmitInventoryChanged()
    {
        EmitSignal(SignalName.InventoryChanged);
    }
    // 提供给 UI 遍历用的只读接口
    public IReadOnlyList<ItemStack> Slots => _slots;

    protected virtual bool CanStoreItem(ItemData item)
    {
        return item != null;
    }

    public bool IsValidSlotIndex(int index)
    {
        return index >= 0 && index < Capacity;
    }

    public bool CanStore(ItemData item)
    {
        return CanStoreItem(item);
    }

    public ItemStack GetStackAt(int index)
    {
        if (!IsValidSlotIndex(index))
        {
            throw new ArgumentOutOfRangeException(nameof(index));
        }

        return _slots[index];
    }

    public bool TrySetStackAt(int index, ItemStack stack)
    {
        if (!IsValidSlotIndex(index))
        {
            return false;
        }

        if (stack != null && !stack.IsEmpty && !CanStoreItem(stack.Item))
        {
            return false;
        }

        _slots[index].CopyFrom(stack);
        EmitInventoryChanged();
        return true;
    }

    public bool TryClearStackAt(int index)
    {
        if (!IsValidSlotIndex(index))
        {
            return false;
        }

        _slots[index].Clear();
        EmitInventoryChanged();
        return true;
    }

    public bool CopySlotsFrom(InventoryComponent source)
    {
        if (source == null)
        {
            return false;
        }

        int copyCount = Math.Min(Capacity, source.Capacity);
        for (int i = 0; i < copyCount; i++)
        {
            _slots[i].CopyFrom(source.GetStackAt(i));
        }

        for (int i = copyCount; i < Capacity; i++)
        {
            _slots[i].Clear();
        }

        EmitInventoryChanged();
        return true;
    }

    // 按照 Item.CardName 对 _slots 排序，忽略 null
    public void SortByCardName()
    {
        _slots = _slots
            .Where(stack => stack.Item != null) // 过滤掉 null
            .OrderBy(stack => stack.Item.CardName) // 先按名字排序
            .ThenByDescending(stack => stack.Amount) // 再按数量排序（降序，大的在前）
            .Concat(_slots.Where(stack => stack.Item == null)) // null 放最后
            .ToArray();
        EmitInventoryChanged();
    }

    public int AddItem(ItemData item, int amount)
    {
        if (item == null || amount <= 0 || item.ActualMaxStackSize <= 0 || !CanStoreItem(item))
        {
            return amount;
        }

        int remaining = amount;
        bool changed = false;

        // 找已经有这个物品，且还没满的格子塞进去
        foreach (var slot in _slots)
        {
            if (!slot.IsEmpty && slot.Item == item && !slot.IsFull)
            {
                remaining = slot.Add(remaining);
                changed = true;
                if (remaining <= 0)
                {
                    EmitInventoryChanged();
                    return 0; // 全部塞完了
                }
            }
        }

        // 如果还有剩余，找完全空的格子放新堆叠
        foreach (var slot in _slots)
        {
            if (slot.IsEmpty)
            {
                int amountToAdd = Math.Min(remaining, item.ActualMaxStackSize);
                slot.SetItem(item, amountToAdd);
                remaining -= amountToAdd;
                changed = true;

                if (remaining <= 0)
                {
                    EmitInventoryChanged();
                    return 0;
                }
            }
        }

        if (changed)
        {
            EmitInventoryChanged();
        }

        // 返回最终没放下的数量
        return remaining;
    }

    public bool CanAddItem(ItemData item, int amount)
    {
        if (item == null || amount <= 0 || item.ActualMaxStackSize <= 0 || !CanStoreItem(item))
        {
            return false;
        }

        int remaining = amount;
        foreach (var slot in _slots)
        {
            if (slot.IsEmpty)
            {
                remaining -= item.ActualMaxStackSize;
            }
            else if (slot.Item == item && !slot.IsFull)
            {
                remaining -= slot.AvailableSpace;
            }

            if (remaining <= 0)
            {
                return true;
            }
        }

        return false;
    }

    // 查特定物品够不够
    public bool HasItem(ItemData item, int requiredAmount)
    {
        return item != null
            && requiredAmount > 0
            && CountWhere(candidate => candidate == item) >= requiredAmount;
    }

    public int CountWhere(Func<ItemData, bool> predicate)
    {
        ArgumentNullException.ThrowIfNull(predicate);

        int total = 0;
        foreach (var slot in _slots)
        {
            if (!slot.IsEmpty && predicate(slot.Item))
            {
                total += slot.Amount;
            }
        }

        return total;
    }

    // 查特定物品数量
    public int ItemCnt(ItemData item)
    {
        return item == null ? 0 : CountWhere(candidate => candidate == item);
    }

    // 清除特定格子的物品
    public void ClearItem(int index)
    {
        _slots[index].Clear();
    }

    // 将物品替换进特定格子
    public int ReplaceItem(int index, ItemData item, int amount)
    {
        if (item != null && !CanStoreItem(item))
        {
            return amount;
        }

        ClearItem(index);
        if (item == null || amount <= 0)
        {
            return amount;
        }

        int remaining = amount;
        int amountToAdd = Math.Min(remaining, item.ActualMaxStackSize);
        _slots[index].SetItem(item, amountToAdd);
        remaining -= amountToAdd;

        //返回溢出物品数量
        return remaining;
    }


    // 模糊合成:查某个标签的物品够不够
    public int GetTotalAmountByTag(StringName tag)
    {
        if (tag == null || tag.IsEmpty)
        {
            return 0;
        }

        return CountWhere(item => item.ItemTags.Contains(tag));
    }

    public bool TryRemoveItem(ItemData item, int amountToRemove)
    {
        if (item == null || amountToRemove <= 0)
        {
            return false;
        }

        return TryRemoveItems(new Dictionary<ItemData, int>
        {
            [item] = amountToRemove
        });
    }

    public bool TryRemoveItems(IReadOnlyDictionary<ItemData, int> itemsToRemove)
    {
        if (itemsToRemove == null || itemsToRemove.Count == 0)
        {
            return false;
        }

        foreach (var itemToRemove in itemsToRemove)
        {
            if (itemToRemove.Key == null || itemToRemove.Value <= 0 || !HasItem(itemToRemove.Key, itemToRemove.Value))
            {
                return false;
            }
        }

        bool changed = false;
        foreach (var itemToRemove in itemsToRemove)
        {
            RemoveItemWithoutSignal(itemToRemove.Key, itemToRemove.Value, ref changed);
        }

        if (changed)
        {
            EmitInventoryChanged();
        }

        return true;
    }

    private void RemoveItemWithoutSignal(ItemData item, int amountToRemove, ref bool changed)
    {
        if (item == null || amountToRemove <= 0)
        {
            return;
        }

        int remainingToRemove = amountToRemove;

        // 从后往前扣
        for (int i = _slots.Length - 1; i >= 0; i--)
        {
            var slot = _slots[i];
            if (!slot.IsEmpty && slot.Item == item)
            {
                if (slot.Amount >= remainingToRemove)
                {
                    slot.SetItem(slot.Item, slot.Amount - remainingToRemove);
                    changed = true;
                    return;
                }
                else
                {
                    remainingToRemove -= slot.Amount;
                    slot.Clear();
                    changed = true;
                }
            }
        }
    }

    public void RemoveItem(ItemData item, int amountToRemove)
    {
        TryRemoveItem(item, amountToRemove);
    }
    // 将一个格子里的物品，移动/交换到另一个格子
    public void MoveItem(int fromIndex, int toIndex)
    {
        // 越界保护和原地不动保护
        if (fromIndex == toIndex)
        {
            return;
        }

        if (fromIndex < 0 || fromIndex >= Capacity || toIndex < 0 || toIndex >= Capacity)
        {
            return;
        }

        var sourceSlot = _slots[fromIndex];
        var targetSlot = _slots[toIndex];

        if (sourceSlot.IsEmpty)
        {
            return; // 来源是空的
        }

        // 若目标格子装的是同一种物品,尝试合并
        if (!targetSlot.IsEmpty && targetSlot.Item == sourceSlot.Item)
        {
            // 把源格子的数量往目标格子塞
            int remaining = targetSlot.Add(sourceSlot.Amount);

            if (remaining <= 0)
            {
                sourceSlot.Clear(); // 完美合并，源格子清空
            }
            else
            {
                sourceSlot.SetItem(sourceSlot.Item, remaining); // 目标格子满了，源格子留下剩下的
            }
        }
        // 若目标格子是空的，或者装的是不同的物品，互换
        else
        {
            var tempStack = targetSlot.Duplicate();

            targetSlot.CopyFrom(sourceSlot);
            sourceSlot.CopyFrom(tempStack);
        }

        EmitInventoryChanged();
    }

    public bool CanReceiveItemFrom(InventoryComponent sourceInventory, int fromIndex, int toIndex)
    {
        if (sourceInventory == null)
        {
            return false;
        }

        if (!sourceInventory.IsValidSlotIndex(fromIndex) || !IsValidSlotIndex(toIndex))
        {
            return false;
        }

        if (sourceInventory == this && fromIndex == toIndex)
        {
            return false;
        }

        var sourceSlot = sourceInventory._slots[fromIndex];
        if (sourceSlot.IsEmpty || !CanStoreItem(sourceSlot.Item))
        {
            return false;
        }

        var targetSlot = _slots[toIndex];

        if (sourceInventory == this || targetSlot.IsEmpty || targetSlot.Item == sourceSlot.Item)
        {
            return true;
        }

        return sourceInventory.CanStoreItem(targetSlot.Item);
    }

    public void MoveItemFrom(InventoryComponent sourceInventory, int fromIndex, int toIndex)
    {
        if (!CanReceiveItemFrom(sourceInventory, fromIndex, toIndex))
        {
            return;
        }

        if (sourceInventory == this)
        {
            MoveItem(fromIndex, toIndex);
            return;
        }

        var sourceSlot = sourceInventory._slots[fromIndex];
        var targetSlot = _slots[toIndex];

        if (!targetSlot.IsEmpty && targetSlot.Item == sourceSlot.Item)
        {
            int remaining = targetSlot.Add(sourceSlot.Amount);

            if (remaining <= 0)
            {
                sourceSlot.Clear();
            }
            else
            {
                sourceSlot.SetItem(sourceSlot.Item, remaining);
            }
        }
        else
        {
            var tempStack = targetSlot.Duplicate();

            targetSlot.CopyFrom(sourceSlot);
            sourceSlot.CopyFrom(tempStack);
        }

        sourceInventory.EmitInventoryChanged();
        EmitInventoryChanged();
    }

    //尝试合并，之后进行交换
    public void MEItem(int fromIndex, int toIndex)
    {
        // 越界保护和原地不动保护
        if (fromIndex == toIndex)
        {
            return;
        }

        if (fromIndex < 0 || fromIndex >= Capacity || toIndex < 0 || toIndex >= Capacity)
        {
            return;
        }

        var sourceSlot = _slots[fromIndex];
        var targetSlot = _slots[toIndex];

        // 若目标格子装的是同一种物品,尝试合并
        if (!targetSlot.IsEmpty && targetSlot.Item == sourceSlot.Item)
        {
            // 把源格子的数量往目标格子塞
            int remaining = targetSlot.Add(sourceSlot.Amount);

            if (remaining <= 0)
            {
                sourceSlot.Clear(); // 完美合并，源格子清空
            }
            else
            {
                sourceSlot.SetItem(sourceSlot.Item, remaining); // 目标格子满了，源格子留下剩下的
            }
        }

        var tempStack = targetSlot.Duplicate();

        targetSlot.CopyFrom(sourceSlot);
        sourceSlot.CopyFrom(tempStack);
    }
}
