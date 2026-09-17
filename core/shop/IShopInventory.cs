using CUSGA.resources.item;

namespace CUSGA.core.shop;

/// <summary>
/// 描述商店交易所需的仓库能力。
/// </summary>
/// <remarks>
/// 抽成接口的理由与 <see cref="IPlayerWallet"/> 相同：让规则层不依赖具体的 <c>InventoryComponent</c> 节点。
/// <c>InventoryComponent</c> 已经具备下列全部方法的精确签名，因此它实现本接口时不需要新增任何成员，
/// 商店也不需要为「放入 / 取出 / 计数」再写一套平行的库存操作。
/// </remarks>
public interface IShopInventory
{
    /// <summary>
    /// 判断仓库能否再容纳指定数量的物品。
    /// </summary>
    /// <param name="item">待检查的物品数据。</param>
    /// <param name="amount">待容纳的数量。</param>
    /// <returns>现有堆叠与空槽位足以容纳时为 <see langword="true"/>。</returns>
    bool CanAddItem(ItemData item, int amount);

    /// <summary>
    /// 向仓库加入物品。
    /// </summary>
    /// <param name="item">待加入的物品数据。</param>
    /// <param name="amount">待加入的数量。</param>
    /// <returns>最终未能放入的数量；全部放入时返回 0。</returns>
    int AddItem(ItemData item, int amount);

    /// <summary>
    /// 从仓库移除指定数量的物品。
    /// </summary>
    /// <param name="item">待移除的物品数据。</param>
    /// <param name="amount">待移除的数量。</param>
    /// <returns>数量足够并完成移除时为 <see langword="true"/>；否则为 <see langword="false"/>。</returns>
    bool TryRemoveItem(ItemData item, int amount);

    /// <summary>
    /// 统计仓库中某种物品的总数量。
    /// </summary>
    /// <param name="item">待统计的物品数据。</param>
    /// <returns>该物品在所有槽位中的数量总和；不持有时返回 0。</returns>
    int ItemCnt(ItemData item);
}
