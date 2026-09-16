using System;

namespace CUSGA.core.constants;

/// <summary>
/// 集中定义局外行动值与长按输入反馈之间的换算规则。
/// </summary>
public static class WorldInteractionTiming
{
    /// <summary>
    /// 每一真实秒对应的游戏行动值点数。
    /// </summary>
    public const float GameTimePointsPerHoldSecond = 10.0f;

    /// <summary>
    /// 将一次局外交互实际消耗的行动值换算为所需的长按秒数。
    /// </summary>
    /// <param name="actionPointCost">本次交互将消耗的行动值；零或负数表示无需长按。</param>
    /// <returns>返回与行动值严格成正比且不小于零的真实秒数。</returns>
    public static float GetHoldDurationSeconds(int actionPointCost)
    {
        // 负数不代表可等待的行动，因此按零处理，避免错误配置造成反向 Tween。
        int normalizedActionPointCost = Math.Max(0, actionPointCost);
        return normalizedActionPointCost / GameTimePointsPerHoldSecond;
    }
}
