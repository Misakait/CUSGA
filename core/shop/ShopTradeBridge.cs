using System.Collections.Generic;
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
/// 本节点同时也是**价格与上架清单的唯一解析处**：GDScript 只管显示，不再自己判断
/// 「哪些是商品」「单价多少」，避免两侧各写一份规则后失去同步。
/// </para>
/// </remarks>
public partial class ShopTradeBridge : Node
{
    /// <summary>
    /// 商店商品目录。把物品的 <c>.tres</c> 拖进该资源的 <c>Goods</c> 数组即可上架。
    /// </summary>
    /// <remarks>
    /// 留空时退化为「所有自身配置了买价的物品全部上架」，与引入目录之前的行为一致。
    /// 使用通用 Resource 是迁移期的跨语言边界：旧 C# ShopCatalog 和新的 GDScript
    /// shop_catalog.gd 都通过稳定字段名提供同一份目录数据。
    /// </remarks>
    [Export]
    public Resource Catalog { get; set; }

    // 规则服务本身无状态，跨语言调用每次都复用同一实例即可。
    private readonly ShopService _service = new();

    /// <summary>
    /// 判断物品是否作为商品出售。
    /// </summary>
    /// <param name="item">待判断的物品数据。</param>
    /// <returns>解析出的买价为正数时为 <see langword="true"/>。</returns>
    public bool IsPurchasable(ItemData item) => ResolveUnitBuyPrice(item) > 0;

    /// <summary>
    /// 读取物品的单价买入价。
    /// </summary>
    /// <param name="item">待读取的物品数据。</param>
    /// <returns>买入价；物品为空或未上架且未自行定价时返回 0。</returns>
    /// <remarks>
    /// 优先取物品自身的 <see cref="ItemData.BuyPrice"/>；自身没有定价但被目录显式上架时，
    /// 回退到目录的兜底价，保证「拖进目录就能卖」。
    /// </remarks>
    public int GetBuyPrice(ItemData item) => ResolveUnitBuyPrice(item);

    /// <summary>
    /// 读取物品的单价卖出价。
    /// </summary>
    /// <param name="item">待读取的物品数据。</param>
    /// <returns>单价卖出价；物品不可出售时返回 0。</returns>
    /// <remarks>卖价未显式配置时按解析出的买价折半推导，与规则层的回退口径保持一致。</remarks>
    public int GetSellPrice(ItemData item) => ResolveUnitSellPrice(item);

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
    /// 构建商店最终上架清单。
    /// </summary>
    /// <param name="allItems">项目里全部物品，由调用方从 <c>ItemsControl</c> 取出后传入。</param>
    /// <returns>去重并排序后的商品列表。</returns>
    /// <remarks>
    /// 排序规则：<see cref="ShopCatalog.Goods"/> 里的物品**保持数组顺序**（拖拽顺序即货架顺序），
    /// 自动补入的物品追加在后并按 <c>CardId</c> 升序。
    /// 自动补入必须显式排序——<c>ItemsControl</c> 用 <c>DirAccess</c> 递归装入字典，顺序不是稳定契约。
    /// </remarks>
    public Godot.Collections.Array<ItemData> BuildStockList(Godot.Collections.Array<ItemData> allItems)
    {
        var result = new Godot.Collections.Array<ItemData>();
        var included = new HashSet<ItemData>();

        foreach (Resource listedResource in ReadResourceArray(Catalog, "Goods"))
        {
            if (listedResource is ItemData listed && included.Add(listed))
            {
                result.Add(listed);
            }
        }

        // 目录为空，或显式开启「自动上架一切已定价物品」时，补入其余商品。
        if (Catalog == null || ReadBool(Catalog, "AlsoIncludeEveryPricedItem", false))
        {
            var autoIncluded = new List<ItemData>();
            if (allItems != null)
            {
                foreach (ItemData candidate in allItems)
                {
                    if (candidate != null && candidate.BuyPrice > 0 && !included.Contains(candidate))
                    {
                        autoIncluded.Add(candidate);
                        included.Add(candidate);
                    }
                }
            }

            autoIncluded.Sort((left, right) =>
                string.CompareOrdinal(left.CardId.ToString(), right.CardId.ToString())
            );
            foreach (ItemData candidate in autoIncluded)
            {
                result.Add(candidate);
            }
        }

        return result;
    }

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
        && _service.CanBuy(playerWallet, shopInventory, item, ResolveUnitBuyPrice(item), quantity);

    /// <summary>
    /// 判断能否完成一次出售，不产生任何副作用。
    /// </summary>
    /// <param name="inventory">提供物品的仓库节点。</param>
    /// <param name="item">要出售的物品。</param>
    /// <param name="quantity">出售数量。</param>
    /// <returns>持有量足够且物品可定价时为 <see langword="true"/>。</returns>
    public bool CanSell(Node inventory, ItemData item, int quantity) =>
        inventory is IShopInventory shopInventory
        && _service.CanSell(shopInventory, item, ResolveUnitSellPrice(item), quantity);

    /// <summary>
    /// 执行一次购买并返回失败原因码。
    /// </summary>
    /// <param name="wallet">钱包节点。</param>
    /// <param name="inventory">接收商品的仓库节点。</param>
    /// <param name="item">要购买的商品。</param>
    /// <param name="quantity">购买数量。</param>
    /// <returns><see cref="ShopFailureReason"/> 的数值；0 表示成功。</returns>
    /// <remarks>节点无法转换成所需接口时返回 <see cref="ShopFailureReason.NotConfigured"/> 而不是抛异常。</remarks>
    public int TryBuyWithReason(Node wallet, Node inventory, ItemData item, int quantity)
    {
        IPlayerWallet playerWallet = wallet as IPlayerWallet;
        IShopInventory shopInventory = inventory as IShopInventory;
        if (playerWallet == null || shopInventory == null)
        {
            GD.PushError("ShopTradeBridge: 跨语言调用缺少钱包或仓库，无法执行购买。");
            return (int)ShopFailureReason.NotConfigured;
        }

        return _service.TryBuy(
            playerWallet,
            shopInventory,
            item,
            ResolveUnitBuyPrice(item),
            quantity,
            out ShopFailureReason failureReason
        )
            ? (int)ShopFailureReason.None
            : (int)failureReason;
    }

    /// <summary>
    /// 执行一次出售并返回失败原因码。
    /// </summary>
    /// <param name="wallet">钱包节点。</param>
    /// <param name="inventory">提供物品的仓库节点。</param>
    /// <param name="item">要出售的物品。</param>
    /// <param name="quantity">出售数量。</param>
    /// <returns><see cref="ShopFailureReason"/> 的数值；0 表示成功。</returns>
    /// <remarks>节点无法转换成所需接口时返回 <see cref="ShopFailureReason.NotConfigured"/> 而不是抛异常。</remarks>
    public int TrySellWithReason(Node wallet, Node inventory, ItemData item, int quantity)
    {
        IPlayerWallet playerWallet = wallet as IPlayerWallet;
        IShopInventory shopInventory = inventory as IShopInventory;
        if (playerWallet == null || shopInventory == null)
        {
            GD.PushError("ShopTradeBridge: 跨语言调用缺少钱包或仓库，无法执行出售。");
            return (int)ShopFailureReason.NotConfigured;
        }

        return _service.TrySell(
            playerWallet,
            shopInventory,
            item,
            ResolveUnitSellPrice(item),
            quantity,
            out ShopFailureReason failureReason
        )
            ? (int)ShopFailureReason.None
            : (int)failureReason;
    }

    /// <summary>
    /// 解析物品的实际单价买入价。
    /// </summary>
    /// <param name="item">待解析的物品数据。</param>
    /// <returns>买入价；无法定价时返回 0。</returns>
    /// <remarks>
    /// 兜底价**只对目录里显式列出的物品生效**。若对所有买价为 0 的物品都套用兜底价，
    /// 商店会把环境物之类的非商品也一并上架。
    /// </remarks>
    private int ResolveUnitBuyPrice(ItemData item)
    {
        if (item == null)
        {
            return 0;
        }

        if (item.BuyPrice > 0)
        {
            return item.BuyPrice;
        }

        if (
            Catalog != null
            && ReadInt(Catalog, "DefaultBuyPrice", 0) > 0
            && ContainsCatalogItem(Catalog, item)
        )
        {
            return ReadInt(Catalog, "DefaultBuyPrice", 0);
        }

        return 0;
    }

    /// <summary>
    /// 解析物品的实际单价卖出价。
    /// </summary>
    /// <param name="item">待解析的物品数据。</param>
    /// <returns>卖出价；不可出售时返回 0。</returns>
    private int ResolveUnitSellPrice(ItemData item)
    {
        if (item == null)
        {
            return 0;
        }

        if (item.SellPrice > 0)
        {
            return item.SellPrice;
        }

        // 与 ShopService.ResolveSellPrice 同为「买价折半向下取整」，只是买价改用目录解析后的值。
        int resolvedBuyPrice = ResolveUnitBuyPrice(item);
        return resolvedBuyPrice > 0 ? resolvedBuyPrice / 2 : 0;
    }

    /// <summary>
    /// 从目录 Resource 读取商品数组，并过滤掉非 Resource 元素。
    /// </summary>
    /// <param name="catalog">旧 C# 或新 GDScript 商品目录。</param>
    /// <param name="propertyName">目录数组字段名。</param>
    /// <returns>可供桥接器继续处理的 Resource 数组。</returns>
    private static Godot.Collections.Array<Resource> ReadResourceArray(Resource catalog, string propertyName)
    {
        var resources = new Godot.Collections.Array<Resource>();
        if (catalog == null)
        {
            return resources;
        }

        Variant rawValue = catalog.Get(propertyName);
        if (rawValue.VariantType != Variant.Type.Array)
        {
            return resources;
        }

        foreach (Variant value in rawValue.AsGodotArray())
        {
            if (value.AsGodotObject() is Resource resource)
            {
                resources.Add(resource);
            }
        }

        return resources;
    }

    /// <summary>
    /// 从目录 Resource 读取布尔字段，并在旧资源缺失字段时使用默认值。
    /// </summary>
    /// <param name="catalog">旧 C# 或新 GDScript 商品目录。</param>
    /// <param name="propertyName">布尔字段名。</param>
    /// <param name="fallback">字段缺失或类型不匹配时的默认值。</param>
    /// <returns>解析后的布尔值。</returns>
    private static bool ReadBool(Resource catalog, string propertyName, bool fallback)
    {
        if (catalog == null)
        {
            return fallback;
        }

        Variant value = catalog.Get(propertyName);
        return value.VariantType == Variant.Type.Bool ? value.AsBool() : fallback;
    }

    /// <summary>
    /// 从目录 Resource 读取整数价格，并在旧资源缺失字段时使用默认值。
    /// </summary>
    /// <param name="catalog">旧 C# 或新 GDScript 商品目录。</param>
    /// <param name="propertyName">整数价格字段名。</param>
    /// <param name="fallback">字段缺失或类型不匹配时的默认值。</param>
    /// <returns>解析后的整数值。</returns>
    private static int ReadInt(Resource catalog, string propertyName, int fallback)
    {
        if (catalog == null)
        {
            return fallback;
        }

        Variant value = catalog.Get(propertyName);
        return value.VariantType == Variant.Type.Int ? value.AsInt32() : fallback;
    }

    /// <summary>
    /// 判断目录是否显式包含指定物品。
    /// </summary>
    /// <param name="catalog">旧 C# 或新 GDScript 商品目录。</param>
    /// <param name="item">待判断的物品。</param>
    /// <returns>目录中存在同一物品资源实例时为 true。</returns>
    private static bool ContainsCatalogItem(Resource catalog, ItemData item)
    {
        if (item == null)
        {
            return false;
        }

        foreach (Resource listedResource in ReadResourceArray(catalog, "Goods"))
        {
            if (listedResource == item)
            {
                return true;
            }
        }

        return false;
    }
}
