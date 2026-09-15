using Godot;
using CUSGA.core.constants;

namespace CUSGA.core.combat;

/// <summary>
/// 记录一次伤害结算过程中由防护或封顶机制削减的数值。
/// 该对象只在单个 <see cref="DamagePayload"/> 生命周期内使用，避免表现层反向参与伤害计算。
/// </summary>
public sealed class DamageResolutionTrace
{
    /// <summary>
    /// 获取本次伤害被护盾实际吸收的总量。
    /// </summary>
    public int ShieldAbsorbedDamage { get; private set; }

    /// <summary>
    /// 获取本次结算是否耗尽了参与吸收的护盾。
    /// </summary>
    public bool ShieldWasBroken { get; private set; }

    /// <summary>
    /// 获取本次伤害因单次伤害上限而被削减的总量。
    /// </summary>
    public int CappedDamage { get; private set; }

    /// <summary>
    /// 记录护盾吸收伤害后的结果。
    /// </summary>
    /// <param name="absorbedDamage">护盾本次实际吸收的伤害。</param>
    /// <param name="wasBroken">护盾是否在本次吸收后耗尽。</param>
    public void RecordShieldAbsorption(float absorbedDamage, bool wasBroken)
    {
        int normalizedAbsorption = Mathf.Max(0, Mathf.RoundToInt(absorbedDamage));
        if (normalizedAbsorption <= 0)
        {
            return;
        }

        ShieldAbsorbedDamage += normalizedAbsorption;
        ShieldWasBroken |= wasBroken;
    }

    /// <summary>
    /// 记录单次伤害上限削减的伤害量。
    /// </summary>
    /// <param name="reducedDamage">因为上限而未进入后续结算的伤害量。</param>
    public void RecordDamageCap(float reducedDamage)
    {
        CappedDamage += Mathf.Max(0, Mathf.RoundToInt(reducedDamage));
    }
}

/// <summary>
/// 描述一次已经完成的伤害结算，供表现层播放反馈而不改变权威玩法状态。
/// </summary>
public sealed partial class DamageResolutionResult : RefCounted
{
    /// <summary>
    /// 获取本次伤害的来源实体。
    /// </summary>
    public Node Source { get; }

    /// <summary>
    /// 获取本次伤害的目标实体。
    /// </summary>
    public Node Target { get; }

    /// <summary>
    /// 获取进入伤害接收组件前的基础伤害数值。
    /// </summary>
    public int RequestedDamage { get; }

    /// <summary>
    /// 获取护盾和单次伤害上限处理前的最终伤害候选值。
    /// </summary>
    public int PreGuardDamage { get; }

    /// <summary>
    /// 获取本次实际从目标生命中扣除的数值。
    /// </summary>
    public int ActualDamage { get; }

    /// <summary>
    /// 获取本次伤害采用的公式类型。
    /// </summary>
    public DamageType Type { get; }

    /// <summary>
    /// 获取本次伤害的五行属性。
    /// </summary>
    public ElementType Element { get; }

    /// <summary>
    /// 获取本次结算是否被闪避完全规避。
    /// </summary>
    public bool IsEvaded { get; }

    /// <summary>
    /// 获取本次结算是否触发暴击。
    /// </summary>
    public bool IsCritical { get; }

    /// <summary>
    /// 获取本次实际扣血是否使目标生命归零。
    /// </summary>
    public bool IsLethal { get; }

    /// <summary>
    /// 获取本次伤害被护盾吸收的总量。
    /// </summary>
    public int ShieldAbsorbedDamage { get; }

    /// <summary>
    /// 获取本次结算是否击破了参与吸收的护盾。
    /// </summary>
    public bool ShieldWasBroken { get; }

    /// <summary>
    /// 获取本次伤害是否触发单次伤害上限。
    /// </summary>
    public bool WasCapped { get; }

    /// <summary>
    /// 获取该段伤害在所属伤害效果内的从零开始索引。
    /// </summary>
    public int HitIndex { get; }

    /// <summary>
    /// 获取所属伤害效果本次实际执行的总段数。
    /// </summary>
    public int HitCount { get; }

    /// <summary>
    /// 获取目标在技能目标选择中的角色枚举整数，用于表现层区分主目标和次目标。
    /// </summary>
    public int TargetRoleId { get; }

    /// <summary>
    /// 使用已经完成的伤害数据创建不可变结算结果。
    /// </summary>
    /// <param name="payload">本次伤害的输入载荷与表现元数据。</param>
    /// <param name="preGuardDamage">护盾和伤害上限处理前的最终伤害候选值。</param>
    /// <param name="actualDamage">目标生命实际减少的数值。</param>
    /// <param name="isEvaded">本次伤害是否被闪避。</param>
    /// <param name="isCritical">本次伤害是否暴击。</param>
    /// <param name="isLethal">本次伤害是否使目标生命归零。</param>
    public DamageResolutionResult(
        DamagePayload payload,
        int preGuardDamage,
        int actualDamage,
        bool isEvaded,
        bool isCritical,
        bool isLethal)
    {
        Source = payload?.Source;
        Target = payload?.Target;
        RequestedDamage = payload?.Damage ?? 0;
        PreGuardDamage = Mathf.Max(0, preGuardDamage);
        ActualDamage = Mathf.Max(0, actualDamage);
        Type = payload?.Type ?? DamageType.Physical;
        Element = payload?.Element ?? ElementType.None;
        IsEvaded = isEvaded;
        IsCritical = isCritical;
        IsLethal = isLethal;
        ShieldAbsorbedDamage = payload?.ResolutionTrace.ShieldAbsorbedDamage ?? 0;
        ShieldWasBroken = payload?.ResolutionTrace.ShieldWasBroken ?? false;
        WasCapped = (payload?.ResolutionTrace.CappedDamage ?? 0) > 0;
        HitIndex = Mathf.Max(0, payload?.HitIndex ?? 0);
        HitCount = Mathf.Max(1, payload?.HitCount ?? 1);
        TargetRoleId = payload?.TargetRoleId ?? 0;
    }

    /// <summary>
    /// 为 GDScript 表现层读取整数字段提供稳定的跨语言入口。
    /// 不直接暴露可写数据，避免 UI 或特效脚本参与权威战斗结算。
    /// </summary>
    /// <param name="propertyName">需要读取的字段名称。</param>
    /// <returns>对应的整数值；名称不受支持时返回 0。</returns>
    public int GetFeedbackInt(string propertyName)
    {
        return propertyName switch
        {
            nameof(RequestedDamage) => RequestedDamage,
            nameof(PreGuardDamage) => PreGuardDamage,
            nameof(ActualDamage) => ActualDamage,
            nameof(ShieldAbsorbedDamage) => ShieldAbsorbedDamage,
            nameof(HitIndex) => HitIndex,
            nameof(HitCount) => HitCount,
            nameof(TargetRoleId) => TargetRoleId,
            _ => 0
        };
    }

    /// <summary>
    /// 为 GDScript 表现层读取布尔字段提供稳定的跨语言入口。
    /// </summary>
    /// <param name="propertyName">需要读取的字段名称。</param>
    /// <returns>对应的布尔值；名称不受支持时返回 false。</returns>
    public bool GetFeedbackBool(string propertyName)
    {
        return propertyName switch
        {
            nameof(IsEvaded) => IsEvaded,
            nameof(IsCritical) => IsCritical,
            nameof(IsLethal) => IsLethal,
            nameof(ShieldWasBroken) => ShieldWasBroken,
            nameof(WasCapped) => WasCapped,
            _ => false
        };
    }

    /// <summary>
    /// 为 GDScript 表现层读取来源或目标节点提供稳定的跨语言入口。
    /// </summary>
    /// <param name="propertyName">需要读取的节点字段名称。</param>
    /// <returns>对应节点；名称不受支持时返回 null。</returns>
    public Node GetFeedbackNode(string propertyName)
    {
        return propertyName switch
        {
            nameof(Source) => Source,
            nameof(Target) => Target,
            _ => null
        };
    }
}
