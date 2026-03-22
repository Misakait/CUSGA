using Godot;
using System;
using System.Collections.Generic;
using CUSGA.core.constants;
using CUSGA.resources.item.equipment;
using CUSGA.entities.components;
using CUSGA.entities;

namespace CUSGA.entities.components;

public partial class EquipmentComponent : Node
{
    // 记录每个槽位当前装着什么装备
    private readonly Dictionary<EquipmentSlot, EquipmentData> _equippedItems = [];

    private AttributeComponent _attributeComponent;
    private TagComponent _tagComponent;

    // 游戏所有的套装
    [Export] public Godot.Collections.Array<EquipmentSetData> AllSetDatabase { get; set; } = [];

    // 当前激活的套装阶级
    private readonly List<SetBonusTier> _activeSetTiers = [];

    public override void _Ready()
    {
        _attributeComponent = GetParent().GetNode<AttributeComponent>("AttributeComponent");
        _tagComponent = GetParent().GetNode<TagComponent>("TagComponent");
    }

    public bool Equip(EquipmentData item, EquipmentSlot slot)
    {
        if (!item.ValidSlots.Contains(slot))
        {
            GD.PrintErr($"这件装备不能放在 {slot} 槽位！");
            return false;
        }

        // 如果槽位已经装备了其他物品，先脱下来
        if (_equippedItems.ContainsKey(slot))
        {
            Unequip(slot);
        }

        // 穿上装备
        _equippedItems[slot] = item;

        // 结算属性和标签
        ApplyItemEffects(item);

        // 检查套装效果
        CheckSetBonuses();

        return true;
    }

    public void Unequip(EquipmentSlot slot)
    {
        if (_equippedItems.TryGetValue(slot, out var item))
        {
            // 扣除属性和标签
            RemoveItemEffects(item);
            _equippedItems.Remove(slot);

            // 重新检查套装
            CheckSetBonuses();
        }
    }

    private void ApplyItemEffects(EquipmentData item)
    {
        // 加属性
        foreach (var bonus in item.AttributeBonuses)
        {
            _attributeComponent.GetAttribute(bonus.Key)?.AddBonus(bonus.Value);
        }
        // 加标签
        foreach (var tag in item.GrantedTags)
        {
            _tagComponent.AddTag(tag);
        }
    }

    private void RemoveItemEffects(EquipmentData item)
    {
        // 扣属性
        foreach (var bonus in item.AttributeBonuses)
        {
            _attributeComponent.GetAttribute(bonus.Key)?.RemoveBonus(bonus.Value);
        }
        // 删标签
        foreach (var tag in item.GrantedTags)
        {
            _tagComponent.RemoveTag(tag);
        }
    }

    private void CheckSetBonuses()
    {
        ClearActiveSetBonuses();

        // 统计当前各套装的件数
        Dictionary<EquipmentSet, int> setCounts = [];
        foreach (var item in _equippedItems.Values)
        {
            if (item.SetType == EquipmentSet.None) continue;
            setCounts.TryAdd(item.SetType, 0);
            setCounts[item.SetType]++;
        }

        // 激活新的套装效果
        foreach (var kvp in setCounts)
        {
            EquipmentSet currentSetType = kvp.Key;
            int currentPieceCount = kvp.Value;

            // 去数据库里找到这个套装的数据图纸
            EquipmentSetData setData = FindSetData(currentSetType);
            if (setData == null) continue;

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
            if (data.SetType == type) return data;
        }
        return null;
    }


    private void ApplyTierEffects(SetBonusTier tier)
    {
        foreach (var bonus in tier.AttributeBonuses)
            _attributeComponent.GetAttribute(bonus.Key)?.AddBonus(bonus.Value);

        foreach (var tag in tier.GrantedTags)
            _tagComponent.AddTag(tag);
    }

    private void RemoveTierEffects(SetBonusTier tier)
    {
        foreach (var bonus in tier.AttributeBonuses)
            _attributeComponent.GetAttribute(bonus.Key)?.RemoveBonus(bonus.Value);

        foreach (var tag in tier.GrantedTags)
            _tagComponent.RemoveTag(tag);
    }
}
