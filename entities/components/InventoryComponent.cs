using Godot;
using System;
using System.Collections.Generic;
using CUSGA.resources.item;
using CUSGA.core.inventory;
using CUSGA.core.crafting;
using System.Linq;
using CUSGA.core.constants;

namespace CUSGA.entities.components;

/// <summary>
/// 表示基于固定槽位存放 <see cref="ItemStack"/> 的通用背包组件。
/// </summary>
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

    /// <summary>
    /// 获取此背包是否需要在末尾保留一个空槽位。
    /// </summary>
    /// <value>需要为拖拽入口保留空槽时为 <see langword="true"/>。</value>
    protected virtual bool KeepsTrailingEmptySlot => false;

    protected virtual bool CanStoreItem(ItemData item)
    {
        return item != null;
    }

    /// <summary>
    /// 在加入物品前为特殊背包预留额外槽位。
    /// </summary>
    /// <param name="item">准备加入的物品数据。</param>
    /// <param name="amount">准备加入的物品数量。</param>
    protected virtual void PrepareCapacityForAdd(ItemData item, int amount)
    {
    }

    /// <summary>
    /// 判断当前槽位用尽后是否还能提供额外容量。
    /// </summary>
    /// <param name="item">需要继续容纳的物品数据。</param>
    /// <param name="amount">当前槽位无法容纳的剩余数量。</param>
    /// <returns>特殊背包能够扩容容纳剩余数量时返回 <see langword="true"/>。</returns>
    protected virtual bool CanProvideAdditionalCapacity(ItemData item, int amount)
    {
        return false;
    }

    /// <summary>
    /// 计算现有槽位容纳指定物品后仍剩余的数量。
    /// </summary>
    /// <param name="item">准备加入的物品数据。</param>
    /// <param name="amount">准备加入的物品数量。</param>
    /// <returns>当前槽位无法容纳的剩余数量。</returns>
    protected int CountRemainingAfterAvailableSlots(ItemData item, int amount)
    {
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
                return 0;
            }
        }

        return remaining;
    }

    /// <summary>
    /// 确保内部槽位数量至少达到指定容量。
    /// </summary>
    /// <param name="minimumCapacity">调用方需要的最小槽位数量。</param>
    protected void EnsureCapacityAtLeast(int minimumCapacity)
    {
        if (minimumCapacity <= Capacity)
        {
            return;
        }

        int oldCapacity = Capacity;
        System.Array.Resize(ref _slots, minimumCapacity);
        for (int i = oldCapacity; i < minimumCapacity; i++)
        {
            _slots[i] = new ItemStack();
        }

        Capacity = minimumCapacity;
    }

    private void EnsureTrailingEmptySlot()
    {
        foreach (var slot in _slots)
        {
            if (slot.IsEmpty)
            {
                return;
            }
        }

        // 出战卡组需要一个可投放空槽，否则 UI 没有位置接收下一张拖入的牌。
        EnsureCapacityAtLeast(Capacity + 1);
    }

    private void NotifyInventoryChanged()
    {
        if (KeepsTrailingEmptySlot)
        {
            EnsureTrailingEmptySlot();
        }

        EmitInventoryChanged();
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
        NotifyInventoryChanged();
        return true;
    }

    public bool TryClearStackAt(int index)
    {
        if (!IsValidSlotIndex(index))
        {
            return false;
        }

        _slots[index].Clear();
        NotifyInventoryChanged();
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

        NotifyInventoryChanged();
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
        NotifyInventoryChanged();
    }

    public int AddItem(ItemData item, int amount)
    {
        if (item == null || amount <= 0 || item.ActualMaxStackSize <= 0 || !CanStoreItem(item))
        {
            return amount;
        }

        int remaining = amount;
        bool changed = false;

        PrepareCapacityForAdd(item, amount);

        // 找已经有这个物品，且还没满的格子塞进去
        foreach (var slot in _slots)
        {
            if (!slot.IsEmpty && slot.Item == item && !slot.IsFull)
            {
                remaining = slot.Add(remaining);
                changed = true;
                if (remaining <= 0)
                {
                    NotifyInventoryChanged();
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
                    NotifyInventoryChanged();
                    return 0;
                }
            }
        }

        if (changed)
        {
            NotifyInventoryChanged();
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

        int remaining = CountRemainingAfterAvailableSlots(item, amount);
        return remaining <= 0 || CanProvideAdditionalCapacity(item, remaining);
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
            NotifyInventoryChanged();
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

        NotifyInventoryChanged();
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

    /// <summary>
    /// 将指定槽位的物品移动到目标背包第一个不会替换不同物品的可用槽。
    /// </summary>
    /// <param name="targetInventory">接收物品的目标背包。</param>
    /// <param name="fromIndex">来源背包中的槽位索引。</param>
    /// <returns>成功移动或合并至少一部分物品时返回 <see langword="true"/>。</returns>
    public bool TryMoveStackToFirstAvailableSlot(InventoryComponent targetInventory, int fromIndex)
    {
        return TryMoveStackToFirstAvailableSlot(targetInventory, fromIndex, notifyInventories: true);
    }

    private bool TryMoveStackToFirstAvailableSlot(
        InventoryComponent targetInventory,
        int fromIndex,
        bool notifyInventories)
    {
        if (targetInventory == null || targetInventory == this || !IsValidSlotIndex(fromIndex))
        {
            return false;
        }

        var sourceSlot = _slots[fromIndex];
        if (sourceSlot.IsEmpty)
        {
            return false;
        }

        // 先让目标背包执行自己的扩容规则，出战卡组才能在快捷加入时保留拖拽入口空槽。
        targetInventory.PrepareCapacityForAdd(sourceSlot.Item, sourceSlot.Amount);

        for (int toIndex = 0; toIndex < targetInventory.Capacity; toIndex++)
        {
            if (!targetInventory.CanReceiveWithoutReplacingDifferentItem(this, fromIndex, toIndex))
            {
                continue;
            }

            int beforeAmount = sourceSlot.Amount;
            targetInventory.MoveItemFrom(this, fromIndex, toIndex, notifyInventories);
            return sourceSlot.IsEmpty || sourceSlot.Amount < beforeAmount;
        }

        return false;
    }

    /// <summary>
    /// 将所有符合条件的物品堆叠移动到目标背包的可用槽位。
    /// </summary>
    /// <param name="targetInventory">接收物品的目标背包。</param>
    /// <param name="predicate">用于判断物品是否应被移动的条件。</param>
    /// <returns>成功移动的物品数量。</returns>
    public int MoveAllMatchingStacksTo(InventoryComponent targetInventory, Func<ItemData, bool> predicate)
    {
        ArgumentNullException.ThrowIfNull(predicate);

        if (targetInventory == null || targetInventory == this)
        {
            return 0;
        }

        // 先完整执行外部筛选条件，避免后续条件抛异常时留下已移动但尚未发送全局通知的半成品批次。
        List<int> matchingIndices = [];
        for (int fromIndex = 0; fromIndex < Capacity; fromIndex++)
        {
            var sourceSlot = _slots[fromIndex];
            if (sourceSlot.IsEmpty || !predicate(sourceSlot.Item))
            {
                continue;
            }

            matchingIndices.Add(fromIndex);
        }

        int movedAmount = 0;
        foreach (int fromIndex in matchingIndices)
        {
            var sourceSlot = _slots[fromIndex];
            int beforeAmount = sourceSlot.Amount;
            if (TryMoveStackToFirstAvailableSlot(targetInventory, fromIndex, notifyInventories: false))
            {
                int remainingAmount = sourceSlot.IsEmpty ? 0 : sourceSlot.Amount;
                movedAmount += beforeAmount - remainingAmount;
            }
        }

        if (movedAmount > 0)
        {
            // ItemStack 已逐槽通知可见 UI；全局信号延迟到批次结束，避免每个堆叠触发整表刷新。
            NotifyInventoryChanged();
            targetInventory.NotifyInventoryChanged();
        }

        return movedAmount;
    }

    private bool CanReceiveWithoutReplacingDifferentItem(InventoryComponent sourceInventory, int fromIndex, int toIndex)
    {
        if (!CanReceiveItemFrom(sourceInventory, fromIndex, toIndex))
        {
            return false;
        }

        var sourceSlot = sourceInventory._slots[fromIndex];
        var targetSlot = _slots[toIndex];
        return targetSlot.IsEmpty || (targetSlot.Item == sourceSlot.Item && !targetSlot.IsFull);
    }

    /// <summary>
    /// 将来源背包的指定物品堆叠移动或合并到当前背包的目标槽位。
    /// </summary>
    /// <param name="sourceInventory">提供物品堆叠的来源背包。</param>
    /// <param name="fromIndex">来源背包中的槽位索引。</param>
    /// <param name="toIndex">当前背包中的目标槽位索引。</param>
    public void MoveItemFrom(InventoryComponent sourceInventory, int fromIndex, int toIndex)
    {
        MoveItemFrom(sourceInventory, fromIndex, toIndex, notifyInventories: true);
    }

    private void MoveItemFrom(
        InventoryComponent sourceInventory,
        int fromIndex,
        int toIndex,
        bool notifyInventories)
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

        if (notifyInventories)
        {
            sourceInventory.NotifyInventoryChanged();
            NotifyInventoryChanged();
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

        var tempStack = targetSlot.Duplicate();

        targetSlot.CopyFrom(sourceSlot);
        sourceSlot.CopyFrom(tempStack);
    }
}
