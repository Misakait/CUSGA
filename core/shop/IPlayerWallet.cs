namespace CUSGA.core.shop;

/// <summary>
/// 描述商店交易所需的玩家货币能力。
/// </summary>
/// <remarks>
/// 之所以抽成接口而不是让 <see cref="ShopService"/> 直接依赖 <see cref="PlayerWallet"/> 节点：
/// 规则层必须能在没有场景树的控制台测试里运行，接口使它得以注入假钱包。
/// 这也是钱包必须用 C# 实现的原因——GDScript 类无法实现 C# 接口。
/// </remarks>
public interface IPlayerWallet
{
    /// <summary>
    /// 获取当前金币余额。
    /// </summary>
    /// <value>当前可用于交易的金币数量，恒为非负数。</value>
    int Gold { get; }

    /// <summary>
    /// 尝试扣除指定数量的金币。
    /// </summary>
    /// <param name="amount">需要扣除的金币数量，只有正数才有意义。</param>
    /// <returns>余额足够并完成扣除时为 <see langword="true"/>；否则为 <see langword="false"/> 且余额保持不变。</returns>
    bool TrySpend(int amount);

    /// <summary>
    /// 增加金币。
    /// </summary>
    /// <param name="amount">需要增加的金币数量；非正数会被忽略，避免被误用为减少余额。</param>
    void Add(int amount);
}
