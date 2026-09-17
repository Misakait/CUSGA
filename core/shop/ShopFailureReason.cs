namespace CUSGA.core.shop;

/// <summary>
/// 描述商店交易失败的具体原因，供表现层映射为玩家可见的提示文案。
/// </summary>
/// <remarks>
/// 每个成员都显式指定数值：GDScript 侧以具名常量镜像这份枚举
/// （见 <c>scripts/shop/shop_control.gd</c>），显式数值让两侧的对应关系可被测试断言。
/// 因此已有成员的数值不允许重排或删除，只能追加新成员。
/// </remarks>
public enum ShopFailureReason
{
    /// <summary>交易成功，没有失败。</summary>
    None = 0,

    /// <summary>物品为空，或该物品没有配置有效价格，不能作为交易对象。</summary>
    InvalidItem = 1,

    /// <summary>交易数量不是正数，或总价溢出整数范围。</summary>
    InvalidQuantity = 2,

    /// <summary>玩家金币不足以支付本次购买。</summary>
    NotEnoughGold = 3,

    /// <summary>仓库没有足够空间容纳本次购买的商品。</summary>
    NotEnoughSpace = 4,

    /// <summary>仓库中该物品的数量不足以完成本次出售。</summary>
    MissingItem = 5,

    /// <summary>商店依赖没有接好（例如缺少钱包或仓库节点），当前无法交易。</summary>
    NotConfigured = 6,
}
