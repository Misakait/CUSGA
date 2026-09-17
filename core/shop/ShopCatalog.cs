using CUSGA.resources.item;
using Godot;

namespace CUSGA.core.shop;

/// <summary>
/// 描述商店上架哪些商品、以及未定价商品的兜底价。
/// </summary>
/// <remarks>
/// 这是一个纯配置资源：把物品的 <c>.tres</c> 拖进 <see cref="Goods"/> 数组即可上架，
/// 不需要逐个去改物品自身的买价。之所以做成独立资源而不是写在场景节点上，
/// 是为了将来做第二个商人时可以直接复用同一套上架逻辑而不必复制整个场景。
/// </remarks>
[GlobalClass]
public partial class ShopCatalog : Resource
{
    /// <summary>
    /// 显式上架的商品清单。把物品的 <c>.tres</c> 拖进这个数组即可出现在商店里。
    /// </summary>
    /// <remarks>
    /// 这里的物品优先使用自身的 <see cref="ItemData.BuyPrice"/>；
    /// 自身没有定价时回退到 <see cref="DefaultBuyPrice"/>，保证「拖进来就能卖」。
    /// </remarks>
    [Export]
    public Godot.Collections.Array<ItemData> Goods { get; set; } = [];

    /// <summary>
    /// 是否在 <see cref="Goods"/> 之外，额外自动上架所有自身配置了正数买价的物品。
    /// </summary>
    /// <remarks>
    /// 默认开启以保持既有行为：88 个在 <c>.tres</c> 里配好买价的商品会照旧全部上架。
    /// 想做成「只卖我手动指定的那些」就把它关掉。
    /// </remarks>
    [Export]
    public bool AlsoIncludeEveryPricedItem { get; set; } = true;

    /// <summary>
    /// 未自行定价的商品的兜底买价。
    /// </summary>
    /// <remarks>
    /// 只对出现在 <see cref="Goods"/> 里的物品生效。没有这个兜底，
    /// 拖进来的新物品会因为买价为 0 而无法交易，与「拖进来就上架」的预期不符。
    /// </remarks>
    [Export(PropertyHint.Range, "0,999999,1,or_greater")]
    public int DefaultBuyPrice { get; set; } = 100;

    /// <summary>
    /// 判断某个物品是否被本目录显式上架。
    /// </summary>
    /// <param name="item">待判断的物品。</param>
    /// <returns>物品非空且出现在 <see cref="Goods"/> 中时为 <see langword="true"/>。</returns>
    public bool ContainsExplicitly(ItemData item)
    {
        if (item == null)
        {
            return false;
        }

        foreach (ItemData listed in Goods)
        {
            if (listed == item)
            {
                return true;
            }
        }

        return false;
    }
}
