using Godot;
using Godot.Collections;
using CUSGA.core.inventory;
using CUSGA.resources.item;

namespace CUSGA.resources.loot;

/// <summary>
/// 保存掉落条目并在运行时将其转换为库存物品堆。
/// </summary>
[GlobalClass]
public partial class LootTable : Resource
{
    // 使用通用 Resource 数组承接 GDScript 掉落条目，同时保留旧 C# LootDrop 兼容输入。
    [Export] public Array<Resource> Drops { get; set; } = [];

    /// <summary>
    /// 按掉落表配置随机生成物品堆。
    /// </summary>
    /// <param name="yieldGrowth">由采集或遭遇规则提供的额外掉落数量。</param>
    /// <returns>通过旧库存 ItemStack 协议创建的掉落物品堆。</returns>
    public Array<ItemStack> RollLoot(int yieldGrowth)
    {
        Array<ItemStack> generatedLoot = [];

        foreach (Resource drop in Drops)
        {
            ItemData item = ReadItem(drop);
            if (item == null) continue;
            float roll = GD.Randf() * 100f;

            if (roll <= ReadFloat(drop, "DropChance", 100f))
            {
                int baseAmount = GD.RandRange(
                    ReadInt(drop, "MinAmount", 1),
                    ReadInt(drop, "MaxAmount", 1)
                );
                int finalAmount = baseAmount + yieldGrowth;

                if (finalAmount > 0)
                {
                    ItemStack stack = new();
                    stack.SetItem(item, finalAmount);
                    generatedLoot.Add(stack);
                }
            }
        }

        return generatedLoot;
    }

    /// <summary>
    /// 读取 C# 或 GDScript 掉落条目的物品资源。
    /// </summary>
    /// <param name="drop">待读取的掉落条目。</param>
    /// <returns>条目配置的 ItemData；字段缺失或类型不符时返回 null。</returns>
    private static ItemData ReadItem(Resource drop)
    {
        if (drop is LootDrop legacyDrop)
        {
            return legacyDrop.Item;
        }

        return drop?.Get("Item").AsGodotObject() as ItemData;
    }

    /// <summary>
    /// 读取掉落条目的浮点字段并在迁移资源缺失时回退到默认值。
    /// </summary>
    /// <param name="drop">待读取的掉落条目。</param>
    /// <param name="propertyName">字段名。</param>
    /// <param name="fallback">字段不存在或类型不匹配时的默认值。</param>
    /// <returns>转换后的浮点值。</returns>
    private static float ReadFloat(Resource drop, string propertyName, float fallback)
    {
        Variant value = drop?.Get(propertyName) ?? Variant.From(fallback);
        return value.VariantType switch
        {
            Variant.Type.Float => value.AsSingle(),
            Variant.Type.Int => value.AsInt32(),
            _ => fallback
        };
    }

    /// <summary>
    /// 读取掉落条目的整数数量字段并在迁移资源缺失时回退到默认值。
    /// </summary>
    /// <param name="drop">待读取的掉落条目。</param>
    /// <param name="propertyName">字段名。</param>
    /// <param name="fallback">字段不存在或类型不匹配时的默认值。</param>
    /// <returns>转换后的整数值。</returns>
    private static int ReadInt(Resource drop, string propertyName, int fallback)
    {
        Variant value = drop?.Get(propertyName) ?? Variant.From(fallback);
        return value.VariantType switch
        {
            Variant.Type.Int => value.AsInt32(),
            Variant.Type.Float => (int)value.AsSingle(),
            _ => fallback
        };
    }
}
