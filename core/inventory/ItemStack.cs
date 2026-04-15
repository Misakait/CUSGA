using System;
using CUSGA.core.attributes;
using CUSGA.resources.item;
using CUSGA.resources.item.equipment;
using Godot;
using Godot.Collections;

namespace CUSGA.core.inventory;

public partial class ItemStack : RefCounted
{
    public ItemData Item { get; private set; }
    public int Amount { get; private set; }

    public event Action<ItemStack> OnStackChanged;

    public bool IsEmpty => Item == null || Amount <= 0;
    public bool IsFull => !IsEmpty && Amount >= Item.ActualMaxStackSize;
    public int AvailableSpace => IsEmpty ? 0 : Item.ActualMaxStackSize - Amount;
    public Dictionary<AttributeType, int> RolledAttributes { get; private set; } = [];

    public void RollRandomStats()
    {
        RolledAttributes.Clear();

        // 只有这件物品是装备图纸时，才进行洗炼
        if (Item is EquipmentData equipData)
        {
            foreach (var kvp in equipData.AttributeBonuses)
            {
                AttributeType type = kvp.Key;
                Vector2I range = kvp.Value; // X 是 Min, Y 是 Max

                // 如果 Min 和 Max 一样，说明是固定属性
                if (Mathf.IsEqualApprox(range.X, range.Y))
                {
                    RolledAttributes[type] = range.X;
                }
                else
                {
                    RolledAttributes[type] = GD.RandRange(range.X, range.Y);
                }
            }
        }
    }

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
        // int space = Item.MaxStackSize - Amount;
        int amountToAdd = Math.Min(AvailableSpace, amount);
        Amount += amountToAdd;
        OnStackChanged?.Invoke(this);

        return amount - amountToAdd; // 返回剩了多少没加进去
    }

    public int GetBonus(AttributeType type)
    {
        if (RolledAttributes.TryGetValue(type, out int value))
        {
            return value;
        }
        return 0;
    }
}
