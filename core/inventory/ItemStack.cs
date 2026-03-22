using System;
using CUSGA.resources.item;
using Godot;

namespace CUSGA.core.inventory;

public partial class ItemStack : RefCounted
{
    public ItemData Item { get; private set; }
    public int Amount { get; private set; }

    public event Action<ItemStack> OnStackChanged;

    public bool IsEmpty => Item == null || Amount <= 0;
    public bool IsFull => !IsEmpty && Amount >= Item.MaxStackSize;
    public int AvailableSpace => IsEmpty ? 0 : Item.MaxStackSize - Amount;

    // 清空格子
    public void Clear()
    {
        Item = null;
        Amount = 0;
        OnStackChanged?.Invoke(this);
    }

    // 设置格子内容
    public void SetItem(ItemData item, int amount)
    {
        Item = item;
        Amount = amount;
        if (Amount <= 0) Clear();
        else OnStackChanged?.Invoke(this);
    }

    // 往格子里加东西，返回“溢出没放下的数量”
    public int Add(int amount)
    {
        int space = Item.MaxStackSize - Amount;
        int amountToAdd = Math.Min(space, amount);
        Amount += amountToAdd;
        OnStackChanged?.Invoke(this);

        return amount - amountToAdd; // 返回剩了多少没加进去
    }
}
