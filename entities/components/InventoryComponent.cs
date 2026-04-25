using Godot;
using System;
using System.Collections.Generic;
using CUSGA.resources.item;
using CUSGA.core.inventory;

namespace CUSGA.entities.components;

public partial class InventoryComponent : Node
{
    [Export] public int Capacity { get; private set; } = 27; // 背包格子数

    private ItemStack[] _slots = null!;

    public override void _Ready()
    {
        // 初始化所有的空箱子
        _slots = new ItemStack[Capacity];
        for (int i = 0; i < Capacity; i++)
        {
            _slots[i] = new ItemStack();
        }
    }

    // 提供给 UI 遍历用的只读接口
    public IReadOnlyList<ItemStack> Slots => _slots;

    public int AddItem(ItemData item, int amount)
    {
        if (item == null || amount <= 0)
        {
            return amount;
        }

        int remaining = amount;

        // 找已经有这个物品，且还没满的格子塞进去
        foreach (var slot in _slots)
        {
            if (!slot.IsEmpty && slot.Item == item && !slot.IsFull)
            {
                remaining = slot.Add(remaining);
                if (remaining <= 0)
                {
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

                if (remaining <= 0)
                {
                    return 0;
                }
            }
        }

        // 返回最终没放下的数量
        return remaining;
    }

    // 查特定物品够不够
    public bool HasItem(ItemData item, int requiredAmount)
    {
        int total = 0;
        foreach (var slot in _slots)
        {
            if (!slot.IsEmpty && slot.Item == item)
            {
                total += slot.Amount;
            }
        }
        return total >= requiredAmount;
    }

    // 查特定物品数量
    public int ItemCnt(ItemData item)
    {
        int total = 0;
        foreach (var slot in _slots)
        {
            if (!slot.IsEmpty && slot.Item == item)
            {
                total += slot.Amount;
            }
        }
        return total;
    }

    // 清除特定格子的物品
    public void ClearItem(int index)
    {
        _slots[index].Clear();
    }

    // 将物品替换进特定格子
    public int ReplaceItem(int index, ItemData item, int amount)
    {
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

        int total = 0;
        foreach (var slot in _slots)
        {
            if (!slot.IsEmpty && slot.Item.ItemTags.Contains(tag))
            {
                total += slot.Amount;
            }
        }
        return total;
    }

    public void RemoveItem(ItemData item, int amountToRemove)
    {
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
                    return;
                }
                else
                {
                    remainingToRemove -= slot.Amount;
                    slot.Clear();
                }
            }
        }
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
            var tempItem = targetSlot.Item;
            var tempAmount = targetSlot.Amount;

            targetSlot.SetItem(sourceSlot.Item, sourceSlot.Amount);
            sourceSlot.SetItem(tempItem, tempAmount);
        }
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

        var tempItem = targetSlot.Item;
        var tempAmount = targetSlot.Amount;

        targetSlot.SetItem(sourceSlot.Item, sourceSlot.Amount);
        sourceSlot.SetItem(tempItem, tempAmount);
    }
}
