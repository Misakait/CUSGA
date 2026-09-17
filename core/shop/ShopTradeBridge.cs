using CUSGA.resources.item;
using Godot;

namespace CUSGA.core.shop;

/// <summary>
/// 把 <see cref="ShopService"/> 的规则暴露给 GDScript 的桥接节点。
/// </summary>
/// <remarks>
/// 之所以需要这个节点：Godot 只能从 GDScript 访问派生自 <c>GodotObject</c> 的 C# 类型，
/// 而 <see cref="ShopService"/> 按 <c>CraftingService</c> 的范式刻意写成不依赖 Godot 的普通类，
/// 因此 GDScript 不能直接 <c>ShopService.new()</c>。
/// <para>
/// 另一个必须经过节点的原因：Godot 的 C# 方法绑定只支持 <c>GodotObject</c> 派生或 Variant 兼容的参数类型，
/// 接口类型（<see cref="IPlayerWallet"/> / <see cref="IShopInventory"/>）无法直接作为跨语言参数。
/// 本类因此用 <see cref="Node"/> 接收参数，再在内部转换成接口。
/// </para>
/// <para>
/// 商店场景把本节点作为子节点挂载；GDScript 只负责表现，规则判断与状态变更全部委托到这里。
/// </para>
/// </remarks>
public partial class ShopTradeBridge : Node
{
    // 规则服务本身无状态，跨语言调用每次都复用同一实例即可。
    private readonly ShopService _service = new();

    /// <summary>
    /// 判断物品是否作为商品出售。
    /// </summary>
    /// <param name="item">待判断的物品数据。</param>
    /// <returns>物品存在且配置了正数买入价时为 <see langword="true"/>。</returns>
    public bool IsPurchasable(ItemData item) => ShopService.IsPurchasable(item);

    /// <summary>
    /// 读取物品的买入价。
    /// </summary>
    /// <param name="item">待读取的物品数据。</param>
    /// <returns>买入价；物品为空时返回 0。</returns>
    public int GetBuyPrice(ItemData item) => item?.BuyPrice ?? 0;

    /// <summary>
    /// 读取物品的单价卖出价。
    /// </summary>
    /// <param name="item">待读取的物品数据。</param>
    /// <returns>单价卖出价；物品不可出售时返回 0。</returns>
    /// <remarks>卖价未显式配置时由 <see cref="ShopService.ResolveSellPrice"/> 按买价折半推导。</remarks>
    public int GetSellPrice(ItemData item) => ShopService.ResolveSellPrice(item);

    /// <summary>
    /// 读取钱包余额。
    /// </summary>
    /// <param name="wallet">钱包节点，应当挂载实现了 <see cref="IPlayerWallet"/> 的脚本。</param>
    /// <returns>当前金币；节点为空或未实现钱包接口时返回 0。</returns>
    /// <remarks>
    /// 走桥接读余额而不是让 GDScript 反射 C# 属性，是为了把跨语言类型假设集中在一个文件里。
    /// </remarks>
    public int GetGold(Node wallet) => (wallet as IPlayerWallet)?.Gold ?? 0;

    /// <summary>
    /// 读取仓库中某种物品的总数量。
    /// </summary>
    /// <param name="inventory">仓库节点，应当挂载实现了 <see cref="IShopInventory"/> 的脚本。</param>
    /// <param name="item">待统计的物品数据。</param>
    /// <returns>该物品的总数量；节点或物品为空时返回 0。</returns>
    public int GetItemCount(Node inventory, ItemData item) =>
        inventory is IShopInventory shopInventory && item != null ? shopInventory.ItemCnt(item) : 0;

    /// <summary>
    /// 判断能否完成一次购买，不产生任何副作用。
    /// </summary>
    /// <param name="wallet">钱包节点。</param>
    /// <param name="inventory">接收商品的仓库节点。</param>
    /// <param name="item">要购买的商品。</param>
    /// <param name="quantity">购买数量。</param>
    /// <returns>余额与仓库空间都满足时为 <see langword="true"/>。</returns>
    public bool CanBuy(Node wallet, Node inventory, ItemData item, int quantity) =>
        wallet is IPlayerWallet playerWallet
        && inventory is IShopInventory shopInventory
        && _service.CanBuy(playerWallet, shopInventory, item, quantity);

    /// <summary>
    /// 判断能否完成一次出售，不产生任何副作用。
    /// </summary>
    /// <param name="inventory">提供物品的仓库节点。</param>
    /// <param name="item">要出售的物品。</param>
    /// <param name="quantity">出售数量。</param>
    /// <returns>持有量足够且物品可定价时为 <see langword="true"/>。</returns>
    public bool CanSell(Node inventory, ItemData item, int quantity) =>
        inventory is IShopInventory shopInventory && _service.CanSell(shopInventory, item, quantity);

    /// <summary>
    /// 执行一次购买并返回失败原因码。
    /// </summary>
    /// <param name="wallet">钱包节点。</param>
    /// <param name="inventory">接收商品的仓库节点。</param>
    /// <param name="item">要购买的商品。</param>
    /// <param name="quantity">购买数量。</param>
    /// <returns><see cref="ShopFailureReason"/> 的数值；0 表示成功。</returns>
    /// <remarks>节点无法转换成所需接口时返回 <see cref="ShopFailureReason.NotConfigured"/> 而不是抛异常。</remarks>
    public int TryBuyWithReason(Node wallet, Node inventory, ItemData item, int quantity) =>
        _service.TryBuyWithReason(
            wallet as IPlayerWallet,
            inventory as IShopInventory,
            item,
            quantity
        );

    /// <summary>
    /// 执行一次出售并返回失败原因码。
    /// </summary>
    /// <param name="wallet">钱包节点。</param>
    /// <param name="inventory">提供物品的仓库节点。</param>
    /// <param name="item">要出售的物品。</param>
    /// <param name="quantity">出售数量。</param>
    /// <returns><see cref="ShopFailureReason"/> 的数值；0 表示成功。</returns>
    /// <remarks>节点无法转换成所需接口时返回 <see cref="ShopFailureReason.NotConfigured"/> 而不是抛异常。</remarks>
    public int TrySellWithReason(Node wallet, Node inventory, ItemData item, int quantity) =>
        _service.TrySellWithReason(
            wallet as IPlayerWallet,
            inventory as IShopInventory,
            item,
            quantity
        );
}
