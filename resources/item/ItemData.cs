using Godot;
using Godot.Collections;

namespace CUSGA.resources.item;

[GlobalClass]
public partial class ItemData : BaseCardData
{
    [Export] public int MaxStackSize { get; set; } = 99;

    // 物品标签
    [Export] public Array<StringName> ItemTags { get; set; } = [];

    /// <summary>
    /// 商店买入价。小于等于 0 表示该物品不作为商品出售。
    /// </summary>
    /// <remarks>
    /// 默认值 0 同时承担「不出售」的语义，因此既有 <c>.tres</c> 反序列化出这个新字段时天然落在安全的一侧，
    /// 不需要任何数据迁移，也不会让地形物之类的非商品意外上架。
    /// </remarks>
    [Export] public int BuyPrice { get; set; } = 0;

    /// <summary>
    /// 商店卖出价。小于等于 0 时由 <c>ShopService.ResolveSellPrice</c> 按买价折半推导。
    /// </summary>
    /// <remarks>
    /// 允许为 0 是为了让「只配买价」的物品依然可卖，避免必须为 88 个商品各写两遍价格。
    /// </remarks>
    [Export] public int SellPrice { get; set; } = 0;

    public virtual int ActualMaxStackSize => MaxStackSize;
}
