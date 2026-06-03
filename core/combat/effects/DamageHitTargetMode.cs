namespace CUSGA.core.combat.effects;

/// <summary>
/// 定义多段伤害每一段应如何选择目标。
/// </summary>
public enum DamageHitTargetMode
{
    /// <summary>
    /// 每一段都使用技能上下文中已经解析好的目标。
    /// </summary>
    ContextTargets,

    /// <summary>
    /// 每一段都从技能开始时锁定的候选池中重新随机选择一个有效目标。
    /// </summary>
    RandomCandidatePerHit
}
