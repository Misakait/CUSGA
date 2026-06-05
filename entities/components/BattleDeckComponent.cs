using Godot;
using Godot.Collections;
using CUSGA.core.constants;
using CUSGA.resources.item;
using CUSGA.resources.item.card;

namespace CUSGA.entities.components;

/// <summary>
/// 表示玩家进入战斗时携带的技能卡组背包。
/// </summary>
public partial class BattleDeckComponent : InventoryComponent
{
    public override StringName DragSourceSystem => TagConsts.SystemBattleDeck;

    /// <inheritdoc />
    protected override bool KeepsTrailingEmptySlot => true;

    protected override bool CanStoreItem(ItemData item)
    {
        return item is SkillCardData;
    }

    /// <summary>
    /// 判断出战卡组是否可以通过扩容继续容纳技能卡。
    /// </summary>
    /// <param name="item">需要继续容纳的物品。</param>
    /// <param name="amount">当前槽位无法容纳的剩余数量。</param>
    /// <returns>剩余物品都是技能卡时返回 <see langword="true"/>。</returns>
    protected override bool CanProvideAdditionalCapacity(ItemData item, int amount)
    {
        return amount > 0 && CanStoreItem(item);
    }

    /// <summary>
    /// 根据即将加入的技能卡数量提前扩容。
    /// </summary>
    /// <param name="item">准备加入出战卡组的物品。</param>
    /// <param name="amount">准备加入的数量。</param>
    protected override void PrepareCapacityForAdd(ItemData item, int amount)
    {
        if (item == null || amount <= 0 || item.ActualMaxStackSize <= 0 || !CanStoreItem(item))
        {
            return;
        }

        int remaining = CountRemainingAfterAvailableSlots(item, amount);
        int additionalSlots = (remaining + item.ActualMaxStackSize - 1) / item.ActualMaxStackSize;
        EnsureCapacityAtLeast(Capacity + additionalSlots);
    }

    /// <summary>
    /// 获取出战卡组中按数量展开后的技能卡列表。
    /// </summary>
    /// <returns>用于初始化战斗场景的技能卡数组。</returns>
    public Array<SkillCardData> GetSkillCards()
    {
        Array<SkillCardData> cards = [];

        foreach (var slot in Slots)
        {
            if (slot.IsEmpty || slot.Item is not SkillCardData skillCard)
            {
                continue;
            }

            for (int i = 0; i < slot.Amount; i++)
            {
                cards.Add(skillCard);
            }
        }

        return cards;
    }
}
