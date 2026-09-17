using System;
using CUSGA.resources.item;
using Godot;

namespace CUSGA.core.shop;

/// <summary>
/// 提供商店买卖的纯规则计算。
/// </summary>
/// <remarks>
/// 本类不持有场景节点，也不保存交易状态，因此可以在没有场景树的控制台测试里直接构造。
/// 可恢复的失败一律用 <see cref="ShopFailureReason"/> 表达而不是抛异常，对齐 <c>CraftingService</c> 的既定风格。
/// 最重要的契约是「先校验后变更」：任何失败分支都不得留下部分变更——既不能扣了钱没给货，也不能给了货没扣钱。
/// </remarks>
public sealed class ShopService
{
    /// <summary>
    /// 判断指定物品是否作为商品出售。
    /// </summary>
    /// <param name="item">待判断的物品数据，允许为 <see langword="null"/>。</param>
    /// <returns>物品存在且配置了正数买入价时为 <see langword="true"/>。</returns>
    /// <remarks>
    /// 买价 <c>&lt;= 0</c> 就是「不出售」的语义，这与既有 <c>.tres</c> 反序列化出新字段时得到的默认值天然一致，
    /// 因此商店目录无需额外的黑名单就能排除地形物与测试物品。
    /// </remarks>
    public static bool IsPurchasable(ItemData item) => item != null && item.BuyPrice > 0;

    /// <summary>
    /// 解析物品的单价卖出价。
    /// </summary>
    /// <param name="item">待解析的物品数据，允许为 <see langword="null"/>。</param>
    /// <returns>单价卖出价；物品不可出售时返回 0。</returns>
    /// <remarks>
    /// 优先使用显式配置的 <see cref="ItemData.SellPrice"/>；没有配置时按买价折半推导。
    /// 这个回退让「可卖的默认全部配卖价」这一意图即使个别资源漏写卖价也依然成立。
    /// </remarks>
    public static int ResolveSellPrice(ItemData item)
    {
        if (item == null)
        {
            return 0;
        }

        if (item.SellPrice > 0)
        {
            return item.SellPrice;
        }

        // 买价为正说明它至少是一件定价商品，此时折半是安全的兜底卖价。
        return item.BuyPrice > 0 ? item.BuyPrice / 2 : 0;
    }

    /// <summary>
    /// 判断能否完成一次购买，不产生任何副作用。
    /// </summary>
    /// <param name="wallet">玩家钱包，不能为 <see langword="null"/>。</param>
    /// <param name="inventory">接收商品的仓库，不能为 <see langword="null"/>。</param>
    /// <param name="item">要购买的商品。</param>
    /// <param name="quantity">购买数量，默认为 1。</param>
    /// <returns>余额与仓库空间都满足时为 <see langword="true"/>。</returns>
    public bool CanBuy(IPlayerWallet wallet, IShopInventory inventory, ItemData item, int quantity = 1)
    {
        ArgumentNullException.ThrowIfNull(wallet);
        ArgumentNullException.ThrowIfNull(inventory);

        return ValidateBuy(wallet, inventory, item, quantity, out _, out _);
    }

    /// <summary>
    /// 判断能否完成一次出售，不产生任何副作用。
    /// </summary>
    /// <param name="inventory">提供物品的仓库，不能为 <see langword="null"/>。</param>
    /// <param name="item">要出售的物品。</param>
    /// <param name="quantity">出售数量，默认为 1。</param>
    /// <returns>仓库持有量足够且物品可定价时为 <see langword="true"/>。</returns>
    public bool CanSell(IShopInventory inventory, ItemData item, int quantity = 1)
    {
        ArgumentNullException.ThrowIfNull(inventory);

        return ValidateSell(inventory, item, quantity, out _, out _);
    }

    /// <summary>
    /// 尝试购买商品：扣除金币并把商品放入仓库。
    /// </summary>
    /// <param name="wallet">玩家钱包，不能为 <see langword="null"/>。</param>
    /// <param name="inventory">接收商品的仓库，不能为 <see langword="null"/>。</param>
    /// <param name="item">要购买的商品。</param>
    /// <param name="quantity">购买数量。</param>
    /// <param name="failureReason">失败原因；成功时为 <see cref="ShopFailureReason.None"/>。</param>
    /// <returns>交易完成时为 <see langword="true"/>；否则为 <see langword="false"/> 且金币与仓库都不变。</returns>
    public bool TryBuy(
        IPlayerWallet wallet,
        IShopInventory inventory,
        ItemData item,
        int quantity,
        out ShopFailureReason failureReason
    )
    {
        // 钱包或仓库为空属于调用方的装配缺陷，而不是可恢复的玩法失败，因此在这里显式抛出。
        ArgumentNullException.ThrowIfNull(wallet);
        ArgumentNullException.ThrowIfNull(inventory);

        if (!ValidateBuy(wallet, inventory, item, quantity, out int totalPrice, out failureReason))
        {
            return false;
        }

        // 走到这里说明余额与容量都已确认。扣款放在加货之前，是为了让「钱不够」成为唯一可能的失败，
        // 而它此刻已经被排除，所以下面的加货不会再产生「付了钱没拿到货」的中间态。
        if (!wallet.TrySpend(totalPrice))
        {
            failureReason = ShopFailureReason.NotEnoughGold;
            return false;
        }

        int remaining = inventory.AddItem(item, quantity);
        if (remaining > 0)
        {
            // 纵深防御：校验阶段的 CanAddItem 已经预检过容量，正常不可能走到这里。
            // 一旦走到，说明仓库的容量预检与实际写入不一致；此时钱已扣除但货没给全，
            // 必须把整笔钱退回，否则玩家会凭空损失金币。同时报错把契约破坏暴露出来。
            GD.PushError(
                "ShopService: 仓库容量预检与实际写入不一致，已退回本次购买的金币。物品："
                    + item.CardName
                    + "，未放入数量："
                    + remaining
            );
            wallet.Add(totalPrice);
            failureReason = ShopFailureReason.NotEnoughSpace;
            return false;
        }

        failureReason = ShopFailureReason.None;
        return true;
    }

    /// <summary>
    /// 尝试出售物品：从仓库移除物品并增加金币。
    /// </summary>
    /// <param name="wallet">玩家钱包，不能为 <see langword="null"/>。</param>
    /// <param name="inventory">提供物品的仓库，不能为 <see langword="null"/>。</param>
    /// <param name="item">要出售的物品。</param>
    /// <param name="quantity">出售数量。</param>
    /// <param name="failureReason">失败原因；成功时为 <see cref="ShopFailureReason.None"/>。</param>
    /// <returns>交易完成时为 <see langword="true"/>；否则为 <see langword="false"/> 且金币与仓库都不变。</returns>
    /// <remarks>
    /// 本方法不做部分出售：持有量不足时整笔失败，避免玩家在只想卖 3 个却只剩 2 个时被静默卖掉 2 个。
    /// </remarks>
    public bool TrySell(
        IPlayerWallet wallet,
        IShopInventory inventory,
        ItemData item,
        int quantity,
        out ShopFailureReason failureReason
    )
    {
        ArgumentNullException.ThrowIfNull(wallet);
        ArgumentNullException.ThrowIfNull(inventory);

        if (!ValidateSell(inventory, item, quantity, out int totalGold, out failureReason))
        {
            return false;
        }

        // 先移除再进账：移除失败时金币尚未增加，因此不存在「凭空多钱」的中间态。
        if (!inventory.TryRemoveItem(item, quantity))
        {
            failureReason = ShopFailureReason.MissingItem;
            return false;
        }

        wallet.Add(totalGold);
        failureReason = ShopFailureReason.None;
        return true;
    }

    /// <summary>
    /// 购买并直接返回失败原因码，供 GDScript 跨语言调用。
    /// </summary>
    /// <param name="wallet">玩家钱包。</param>
    /// <param name="inventory">接收商品的仓库。</param>
    /// <param name="item">要购买的商品。</param>
    /// <param name="quantity">购买数量。</param>
    /// <returns><see cref="ShopFailureReason"/> 的数值；0 表示成功。</returns>
    /// <remarks>
    /// GDScript 无法接收 C# 的 <c>out</c> 参数，所以这里提供返回原因码的等价入口。
    /// 本入口刻意不抛异常：跨语言调用一旦抛异常，GDScript 只会看到一次引擎报错而拿不到可映射的提示，
    /// 商店界面会在没有可见反馈的情况下卡住。装配缺陷改用 <see cref="ShopFailureReason.NotConfigured"/> 表达。
    /// </remarks>
    public int TryBuyWithReason(IPlayerWallet wallet, IShopInventory inventory, ItemData item, int quantity)
    {
        if (wallet == null || inventory == null)
        {
            GD.PushError("ShopService: 跨语言调用缺少钱包或仓库，无法执行购买。");
            return (int)ShopFailureReason.NotConfigured;
        }

        return TryBuy(wallet, inventory, item, quantity, out ShopFailureReason failureReason)
            ? (int)ShopFailureReason.None
            : (int)failureReason;
    }

    /// <summary>
    /// 出售并直接返回失败原因码，供 GDScript 跨语言调用。
    /// </summary>
    /// <param name="wallet">玩家钱包。</param>
    /// <param name="inventory">提供物品的仓库。</param>
    /// <param name="item">要出售的物品。</param>
    /// <param name="quantity">出售数量。</param>
    /// <returns><see cref="ShopFailureReason"/> 的数值；0 表示成功。</returns>
    /// <remarks>返回原因码而非抛异常的理由与 <see cref="TryBuyWithReason"/> 相同。</remarks>
    public int TrySellWithReason(IPlayerWallet wallet, IShopInventory inventory, ItemData item, int quantity)
    {
        if (wallet == null || inventory == null)
        {
            GD.PushError("ShopService: 跨语言调用缺少钱包或仓库，无法执行出售。");
            return (int)ShopFailureReason.NotConfigured;
        }

        return TrySell(wallet, inventory, item, quantity, out ShopFailureReason failureReason)
            ? (int)ShopFailureReason.None
            : (int)failureReason;
    }

    /// <summary>
    /// 校验一次购买的全部前置条件，并算出总价。
    /// </summary>
    /// <param name="wallet">玩家钱包。</param>
    /// <param name="inventory">接收商品的仓库。</param>
    /// <param name="item">要购买的商品。</param>
    /// <param name="quantity">购买数量。</param>
    /// <param name="totalPrice">校验通过时的应付总价；失败时为 0。</param>
    /// <param name="failureReason">校验失败的原因；通过时为 <see cref="ShopFailureReason.None"/>。</param>
    /// <returns>全部前置条件满足时为 <see langword="true"/>。</returns>
    /// <remarks>
    /// 购买与容量校验集中在这里，保证 <see cref="CanBuy"/> 与 <see cref="TryBuy"/> 对「能不能买」的判断永远一致，
    /// 不会出现界面显示可买、实际点击却失败的分裂。
    /// </remarks>
    private static bool ValidateBuy(
        IPlayerWallet wallet,
        IShopInventory inventory,
        ItemData item,
        int quantity,
        out int totalPrice,
        out ShopFailureReason failureReason
    )
    {
        totalPrice = 0;
        failureReason = ShopFailureReason.None;

        if (!IsPurchasable(item))
        {
            failureReason = ShopFailureReason.InvalidItem;
            return false;
        }

        if (quantity <= 0)
        {
            failureReason = ShopFailureReason.InvalidQuantity;
            return false;
        }

        // 用 long 计算总价：单件价格与数量都可能很大，先按 64 位判断再收窄，避免整数溢出算出负数总价。
        long total = (long)item.BuyPrice * quantity;
        if (total > int.MaxValue)
        {
            failureReason = ShopFailureReason.InvalidQuantity;
            return false;
        }

        if (wallet.Gold < total)
        {
            failureReason = ShopFailureReason.NotEnoughGold;
            return false;
        }

        if (!inventory.CanAddItem(item, quantity))
        {
            failureReason = ShopFailureReason.NotEnoughSpace;
            return false;
        }

        totalPrice = (int)total;
        return true;
    }

    /// <summary>
    /// 校验一次出售的全部前置条件，并算出总收益。
    /// </summary>
    /// <param name="inventory">提供物品的仓库。</param>
    /// <param name="item">要出售的物品。</param>
    /// <param name="quantity">出售数量。</param>
    /// <param name="totalGold">校验通过时的应得总收益；失败时为 0。</param>
    /// <param name="failureReason">校验失败的原因；通过时为 <see cref="ShopFailureReason.None"/>。</param>
    /// <returns>全部前置条件满足时为 <see langword="true"/>。</returns>
    private static bool ValidateSell(
        IShopInventory inventory,
        ItemData item,
        int quantity,
        out int totalGold,
        out ShopFailureReason failureReason
    )
    {
        totalGold = 0;
        failureReason = ShopFailureReason.None;

        int unitPrice = ResolveSellPrice(item);
        if (unitPrice <= 0)
        {
            failureReason = ShopFailureReason.InvalidItem;
            return false;
        }

        if (quantity <= 0)
        {
            failureReason = ShopFailureReason.InvalidQuantity;
            return false;
        }

        // 与购买同理：先按 64 位判断溢出，避免收益回绕成负数。
        long total = (long)unitPrice * quantity;
        if (total > int.MaxValue)
        {
            failureReason = ShopFailureReason.InvalidQuantity;
            return false;
        }

        // 持有量不足时整笔失败而不是按可用量部分出售，避免玩家被静默卖掉少于预期的数量。
        if (inventory.ItemCnt(item) < quantity)
        {
            failureReason = ShopFailureReason.MissingItem;
            return false;
        }

        totalGold = (int)total;
        return true;
    }
}
