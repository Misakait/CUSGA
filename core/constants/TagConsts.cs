using Godot;

namespace CUSGA.core.constants;

public static class TagConsts
{
    public static readonly StringName SystemInventory = new("SystemInventory");
    public static readonly StringName SystemWarehouse = new("SystemWarehouse");
    public static readonly StringName SystemBattleDeck = new("SystemBattleDeck");
    public static readonly StringName SystemEquipment = new("SystemEquipment");
    public static readonly StringName WoodDamageUp = new("WoodDamageUp");
    public static readonly StringName HealAfterAction = new("HealAfterAction");
    // 魔法物品位使用显式分类标签，避免物品名称片段误判为可装备。
    public static readonly StringName MagicItem = new("MagicItem");

}
