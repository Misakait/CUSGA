namespace CUSGA.core.progression;

/// <summary>
/// 玩家数据（金币、升级等级）的持久化策略。
/// </summary>
/// <remarks>
/// 集中一处是为了让「开发期每次启动都从初始值开始」这件事只有一个开关。
/// 金币在 <c>PlayerWallet</c>、等级在 <c>PlayerProgression</c>，分属两个类；
/// 若各自维护一份开关，发布时极易只改一处，出现「金币存了、等级没存」的错位。
/// </remarks>
public static class PlayerDataPolicy
{
    /// <summary>
    /// 是否把金币与升级等级持久化到本地设置文件。
    /// </summary>
    /// <remarks>
    /// 开发期为 <see langword="false"/>：每次启动都从初始值（金币 1200、仓库 27 格、带入栏 5 个）开始，
    /// 反复验证成长曲线时不必手动清存档。正式发布时改成 <see langword="true"/> 即可恢复持久化，
    /// 两边的读写代码都无需改动。
    /// <para>
    /// 关闭时启动会顺带清掉设置文件里遗留的玩家键，避免将来打开开关时把开发期的旧数据当成存档读回来。
    /// 战斗操作模式等其它偏好不受影响。
    /// </para>
    /// </remarks>
    public const bool PersistAcrossRuns = false;
}
