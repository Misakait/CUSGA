using Godot;
using System;
using System.Collections.Generic;
using CUSGA.core.constants;
using CUSGA.resources.item.equipment;
using CUSGA.entities.components;
using CUSGA.entities;
using CUSGA.core.inventory;
using CUSGA.resources.item.tool;

namespace CUSGA.entities.components;

public partial class EquipmentComponent : Node
{
    [Signal] public delegate void EquipmentChangedEventHandler();

    // 记录每个槽位当前装着什么装备
    private readonly Dictionary<EquipmentSlot, ItemStack> _equippedItems = [];

    private AttributeComponent _attributeComponent;
    private TagComponent _tagComponent;

    // 游戏所有的套装
    [Export] public Godot.Collections.Array<EquipmentSetData> AllSetDatabase { get; set; } = [];

    // 当前激活的套装阶级
    private readonly List<SetBonusTier> _activeSetTiers = [];

    [Export(PropertyHint.Range, "0,1,0.05")]
    public float TorchNightEncounterChanceMultiplier { get; set; } = 0.5f;

    public static StringName DragSourceSystem => TagConsts.SystemEquipment;

    public override void _Ready()
    {
        _attributeComponent = GetParent().GetNode<AttributeComponent>("AttributeComponent");
        _tagComponent = GetParent().GetNode<TagComponent>("TagComponent");
    }

    /// <summary>
    /// 将物品装备到指定槽位。
    /// </summary>
    /// <param name="stack">要装备的物品堆叠。</param>
    /// <param name="slot">目标装备槽。</param>
    /// <returns>装备成功时返回 true。</returns>
    public bool Equip(ItemStack stack, EquipmentSlot slot)
    {
        if (!CanEquipStack(stack, slot))
        {
            GD.PrintErr($"这件物品不能放在 {slot} 槽位！");
            return false;
        }

        // 如果槽位已经装备了其他物品，先脱下来
        if (_equippedItems.ContainsKey(slot))
        {
            Unequip(slot);
        }

        // 穿上装备
        _equippedItems[slot] = stack.Duplicate();

        // 结算属性和标签
        ApplyItemEffects(_equippedItems[slot]);

        // 检查套装效果
        CheckSetBonuses();
        EmitEquipmentChanged();

        return true;
    }

    public void Unequip(EquipmentSlot slot)
    {
        if (_equippedItems.TryGetValue(slot, out var stack))
        {
            // 扣除属性和标签
            RemoveItemEffects(stack);
            _equippedItems.Remove(slot);

            // 重新检查套装
            CheckSetBonuses();
            EmitEquipmentChanged();
        }
    }

    private void EmitEquipmentChanged()
    {
        EmitSignal(SignalName.EquipmentChanged);
    }

    public bool TryGetEquippedStack(EquipmentSlot slot, out ItemStack stack)
    {
        return _equippedItems.TryGetValue(slot, out stack);
    }

    /// <summary>
    /// 判断物品堆叠是否可以放入指定装备槽。
    /// </summary>
    /// <param name="stack">要检查的物品堆叠。</param>
    /// <param name="slot">目标装备槽。</param>
    /// <returns>物品能装备到目标槽时返回 true。</returns>
    public static bool CanEquipStack(ItemStack stack, EquipmentSlot slot)
    {
        if (stack == null || stack.IsEmpty)
        {
            return false;
        }

        if (stack.Item is EquipmentData equipData)
        {
            if (equipData.ValidSlots.Contains(slot))
            {
                return true;
            }

            // 有明确装备槽配置时，以资源配置为准，避免标签兜底绕过设计数据。
            if (equipData.ValidSlots.Count > 0)
            {
                return false;
            }
        }

        return CanEquipTaggedItem(stack, slot);
    }

    public bool CanEquipFromInventory(InventoryComponent sourceInventory, int fromIndex, EquipmentSlot slot)
    {
        if (sourceInventory == null || !sourceInventory.IsValidSlotIndex(fromIndex))
        {
            return false;
        }

        var sourceStack = sourceInventory.GetStackAt(fromIndex);
        if (!CanEquipStack(sourceStack, slot))
        {
            return false;
        }

        return !_equippedItems.TryGetValue(slot, out var equippedStack)
            || sourceInventory.CanStore(equippedStack.Item);
    }

    public bool EquipFromInventory(InventoryComponent sourceInventory, int fromIndex, EquipmentSlot slot)
    {
        if (!CanEquipFromInventory(sourceInventory, fromIndex, slot))
        {
            return false;
        }

        var sourceStack = sourceInventory.GetStackAt(fromIndex);
        var newEquipment = sourceStack.Duplicate();
        ItemStack previousEquipment = null;

        if (_equippedItems.TryGetValue(slot, out var equippedStack))
        {
            previousEquipment = equippedStack.Duplicate();
            Unequip(slot);
        }

        if (previousEquipment != null)
        {
            sourceInventory.TrySetStackAt(fromIndex, previousEquipment);
        }
        else
        {
            sourceInventory.TryClearStackAt(fromIndex);
        }

        return Equip(newEquipment, slot);
    }

    /// <summary>
    /// 从背包指定槽位快速装备到最合适的装备槽。
    /// </summary>
    /// <param name="sourceInventory">提供装备物品的背包。</param>
    /// <param name="fromIndex">背包中的来源槽位。</param>
    /// <returns>成功装备或替换装备时返回 <see langword="true"/>。</returns>
    public bool EquipFromInventoryToBestSlot(InventoryComponent sourceInventory, int fromIndex)
    {
        if (sourceInventory == null || !sourceInventory.IsValidSlotIndex(fromIndex))
        {
            return false;
        }

        var sourceStack = sourceInventory.GetStackAt(fromIndex);
        if (sourceStack.IsEmpty)
        {
            return false;
        }

        EquipmentSlot? emptySlot = FindBestInventoryEquipmentSlot(sourceInventory, fromIndex, requireEmptySlot: true);
        if (emptySlot.HasValue)
        {
            return EquipFromInventory(sourceInventory, fromIndex, emptySlot.Value);
        }

        EquipmentSlot? replacementSlot = FindBestInventoryEquipmentSlot(sourceInventory, fromIndex, requireEmptySlot: false);
        return replacementSlot.HasValue && EquipFromInventory(sourceInventory, fromIndex, replacementSlot.Value);
    }

    public bool CanUnequipToInventory(EquipmentSlot slot, InventoryComponent targetInventory, int targetIndex)
    {
        if (!_equippedItems.TryGetValue(slot, out var equippedStack))
        {
            return false;
        }

        if (targetInventory == null
            || !targetInventory.IsValidSlotIndex(targetIndex)
            || !targetInventory.CanStore(equippedStack.Item))
        {
            return false;
        }

        var targetStack = targetInventory.GetStackAt(targetIndex);
        return targetStack.IsEmpty || CanEquipStack(targetStack, slot);
    }

    public bool UnequipToInventory(EquipmentSlot slot, InventoryComponent targetInventory, int targetIndex)
    {
        if (!CanUnequipToInventory(slot, targetInventory, targetIndex))
        {
            return false;
        }

        var equippedStack = _equippedItems[slot].Duplicate();
        var targetStack = targetInventory.GetStackAt(targetIndex);
        ItemStack replacementEquipment = targetStack.IsEmpty ? null : targetStack.Duplicate();

        Unequip(slot);
        targetInventory.TrySetStackAt(targetIndex, equippedStack);

        if (replacementEquipment != null)
        {
            Equip(replacementEquipment, slot);
        }

        return true;
    }

    public bool CanMoveEquipment(EquipmentSlot fromSlot, EquipmentSlot toSlot)
    {
        if (fromSlot == toSlot || !_equippedItems.TryGetValue(fromSlot, out var fromStack))
        {
            return false;
        }

        if (!CanEquipStack(fromStack, toSlot))
        {
            return false;
        }

        return !_equippedItems.TryGetValue(toSlot, out var toStack)
            || CanEquipStack(toStack, fromSlot);
    }

    public bool MoveEquipment(EquipmentSlot fromSlot, EquipmentSlot toSlot)
    {
        if (!CanMoveEquipment(fromSlot, toSlot))
        {
            return false;
        }

        var fromStack = _equippedItems[fromSlot].Duplicate();
        ItemStack toStack = null;
        if (_equippedItems.TryGetValue(toSlot, out var equippedToStack))
        {
            toStack = equippedToStack.Duplicate();
        }

        Unequip(fromSlot);
        if (toStack != null)
        {
            Unequip(toSlot);
            Equip(toStack, fromSlot);
        }
        Equip(fromStack, toSlot);

        return true;
    }

    private EquipmentSlot? FindBestInventoryEquipmentSlot(
        InventoryComponent sourceInventory,
        int fromIndex,
        bool requireEmptySlot)
    {
        var sourceStack = sourceInventory.GetStackAt(fromIndex);
        foreach (EquipmentSlot slot in GetCandidateSlots(sourceStack))
        {
            bool isEmpty = !_equippedItems.ContainsKey(slot);
            if (isEmpty != requireEmptySlot)
            {
                continue;
            }

            if (CanEquipFromInventory(sourceInventory, fromIndex, slot))
            {
                return slot;
            }
        }

        return null;
    }

    private static IEnumerable<EquipmentSlot> GetCandidateSlots(ItemStack stack)
    {
        HashSet<EquipmentSlot> yieldedSlots = [];
        if (stack?.Item is EquipmentData { ValidSlots.Count: > 0 } equipmentData)
        {
            foreach (EquipmentSlot slot in equipmentData.ValidSlots)
            {
                if (yieldedSlots.Add(slot))
                {
                    yield return slot;
                }
            }

            yield break;
        }

        foreach (EquipmentSlot slot in Enum.GetValues<EquipmentSlot>())
        {
            if (CanEquipStack(stack, slot) && yieldedSlots.Add(slot))
            {
                yield return slot;
            }
        }
    }

    /// <summary>
    /// 获取夜晚遭遇概率乘数。
    /// </summary>
    /// <returns>装备有效火把时返回火把乘数；否则返回 1。</returns>
    public float GetNightEncounterChanceMultiplier()
    {
        if (!_equippedItems.TryGetValue(EquipmentSlot.Torch, out var stack)
            || !IsTorchStack(stack))
        {
            return 1.0f;
        }

        return Mathf.Clamp(TorchNightEncounterChanceMultiplier, 0.0f, 1.0f);
    }

    private void ApplyItemEffects(ItemStack stack)
    {
        // 加属性
        foreach (var bonus in stack.RolledAttributes)
        {
            _attributeComponent.AddPermanentBonus(bonus.Key, bonus.Value, source: this);
        }
        // 加标签
        if (stack.Item is EquipmentData equipData)
        {
            foreach (var tag in equipData.GrantedTags)
            {
                _tagComponent.AddTag(tag);
            }
        }
    }

    private void RemoveItemEffects(ItemStack stack)
    {
        // 扣属性
        foreach (var kvp in stack.RolledAttributes)
        {
            _attributeComponent.RemovePermanentBonus(kvp.Key, kvp.Value, source: this);
        }
        // 删标签
        if (stack.Item is EquipmentData equipData)
        {
            foreach (var tag in equipData.GrantedTags)
            {
                _tagComponent.RemoveTag(tag);
            }
        }
    }

    private void CheckSetBonuses()
    {
        ClearActiveSetBonuses();

        // 统计当前各套装的件数
        Dictionary<EquipmentSet, int> setCounts = [];
        foreach (var stack in _equippedItems.Values)
        {
            if (stack.Item is EquipmentData equipData && equipData.SetType != EquipmentSet.None)
            {
                setCounts.TryAdd(equipData.SetType, 0);
                setCounts[equipData.SetType]++;
            }
        }

        // 激活新的套装效果
        foreach (var kvp in setCounts)
        {
            EquipmentSet currentSetType = kvp.Key;
            int currentPieceCount = kvp.Value;

            // 去数据库里找到这个套装的数据图纸
            EquipmentSetData setData = FindSetData(currentSetType);
            if (setData == null)
            {
                continue;
            }

            // 遍历这个套装的所有阶级 (比如 2件套、4件套)
            foreach (var tier in setData.Tiers)
            {
                // 如果身上的件数达标了
                if (currentPieceCount >= tier.RequiredPieces)
                {
                    ApplyTierEffects(tier); // 赋予能力
                    _activeSetTiers.Add(tier); // 记录到缓存中，以便下次清理
                }
            }
        }
    }

    // 移除现在的套装效果
    private void ClearActiveSetBonuses()
    {
        foreach (var tier in _activeSetTiers)
        {
            RemoveTierEffects(tier);
        }
        // 清理完毕后，清空缓存列表
        _activeSetTiers.Clear();
    }

    private EquipmentSetData FindSetData(EquipmentSet type)
    {
        foreach (var data in AllSetDatabase)
        {
            if (data.SetType == type)
            {
                return data;
            }
        }
        return null;
    }


    private void ApplyTierEffects(SetBonusTier tier)
    {
        foreach (var bonus in tier.AttributeBonuses)
        {
            _attributeComponent.AddPermanentBonus(bonus.Key, bonus.Value, source: this);
        }

        foreach (var tag in tier.GrantedTags)
        {
            _tagComponent.AddTag(tag);
        }
    }

    private void RemoveTierEffects(SetBonusTier tier)
    {
        foreach (var bonus in tier.AttributeBonuses)
        {
            _attributeComponent.RemovePermanentBonus(bonus.Key, bonus.Value, source: this);
        }

        foreach (var tag in tier.GrantedTags)
        {
            _tagComponent.RemoveTag(tag);
        }
    }

    public int GetGatheringYieldBonus(StringName gatheringTag)
    {
        int bonus = 0;

        foreach (var stack in _equippedItems.Values)
        {
            if (stack.Item is ToolData tool && tool.TargetGatheringTag == gatheringTag)
            {
                bonus += tool.YieldGrowth;
            }
        }

        return bonus;
    }

    /// <summary>
    /// 获取指定装备槽里匹配采集标签的工具时间减免。
    /// </summary>
    /// <param name="gatheringTag">资源点要求匹配的采集标签。</param>
    /// <param name="slot">资源点指定读取的装备槽。</param>
    /// <returns>返回该槽位有效工具提供的游戏时间减免；没有匹配工具时返回 0。</returns>
    public int GetGatheringTimeReduction(StringName gatheringTag, EquipmentSlot slot)
    {
        if (gatheringTag == null || gatheringTag.IsEmpty)
        {
            return 0;
        }

        if (!_equippedItems.TryGetValue(slot, out var stack)
            || stack.Item is not ToolData tool
            || tool.TargetGatheringTag != gatheringTag)
        {
            return 0;
        }

        return Math.Max(0, tool.GatheringTimeReduction);
    }

    private static bool CanEquipTaggedItem(ItemStack stack, EquipmentSlot slot)
    {
        return slot switch
        {
            EquipmentSlot.Helmet => HasAnyIdentifier(stack, "Helmet"),
            EquipmentSlot.Chest => HasAnyIdentifier(stack, "Breastplate", "Chest"),
            EquipmentSlot.Legs => HasAnyIdentifier(stack, "Legguard", "Legs"),
            EquipmentSlot.Boots => HasAnyIdentifier(stack, "Shoes", "Boots"),
            EquipmentSlot.Weapon => HasAnyIdentifier(stack, "Sword", "Weapon", "Truncheon", "Hammer", "Shovel"),
            EquipmentSlot.Axe => HasAnyIdentifier(stack, "Axe"),
            EquipmentSlot.Pickaxe => HasAnyIdentifier(stack, "Pickaxe"),
            EquipmentSlot.FishingRod => HasAnyIdentifier(stack, "FishingRod"),
            EquipmentSlot.LeftHandguard => HasAnyIdentifier(stack, "Handguard_left", "LeftHandguard"),
            EquipmentSlot.RightHandguard => HasAnyIdentifier(stack, "Handguard_right", "RightHandguard"),
            EquipmentSlot.Torch => IsTorchStack(stack),
            EquipmentSlot.Pendant => HasAnyIdentifier(stack, "Necklace", "Pendant"),
            EquipmentSlot.Ring1 or EquipmentSlot.Ring2 => HasAnyIdentifier(stack, "Ring"),
            EquipmentSlot.Belt => HasAnyIdentifier(stack, "Belt"),
            EquipmentSlot.MagicItem => IsMagicItemStack(stack),
            _ => false
        };
    }

    private static bool IsTorchStack(ItemStack stack)
    {
        return HasAnyIdentifier(stack, "flametorch", "torch");
    }

    private static bool IsMagicItemStack(ItemStack stack)
    {
        return HasExactTag(stack, TagConsts.MagicItem);
    }

    private static bool HasAnyIdentifier(ItemStack stack, params string[] fragments)
    {
        if (stack?.Item == null)
        {
            return false;
        }

        if (ContainsAnyFragment(stack.Item.CardId, fragments))
        {
            return true;
        }

        foreach (var tag in stack.Item.ItemTags)
        {
            if (ContainsAnyFragment(tag, fragments))
            {
                return true;
            }
        }

        return false;
    }

    private static bool HasExactTag(ItemStack stack, StringName expectedTag)
    {
        if (stack?.Item == null || expectedTag == null || expectedTag.IsEmpty)
        {
            return false;
        }

        return stack.Item.ItemTags.Contains(expectedTag);
    }

    private static bool ContainsAnyFragment(StringName identifier, params string[] fragments)
    {
        if (identifier == null || identifier.IsEmpty)
        {
            return false;
        }

        string text = identifier.ToString();
        foreach (string fragment in fragments)
        {
            if (text.Contains(fragment, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }
}
