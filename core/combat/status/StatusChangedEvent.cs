using Godot;

namespace CUSGA.core.combat.status;

/// <summary>
/// 描述一次状态变化，供界面与表现层在不读取状态内部可变集合的情况下更新展示。
/// </summary>
public sealed partial class StatusChangedEvent(StatusChangeContext context) : RefCounted
{
    /// <summary>
    /// 获取发生状态变化的实体。
    /// </summary>
    public Node Owner { get; } = context.Owner;

    /// <summary>
    /// 获取施加或刷新该状态的来源实体。
    /// </summary>
    public Node Source { get; } = context.Source;

    /// <summary>
    /// 获取发生变化的状态标识。
    /// </summary>
    public StringName StatusId { get; } = context.Status.Id;

    /// <summary>
    /// 获取状态变化原因的稳定整数值。
    /// </summary>
    public int ReasonId => (int)Reason;

    /// <summary>
    /// 获取状态变化原因。
    /// </summary>
    public StatusChangeReason Reason { get; } = context.Reason;

    /// <summary>
    /// 获取变化后的当前叠层数。
    /// </summary>
    public int CurrentStacks { get; } = context.Status.CurrentStacks;

    /// <summary>
    /// 获取按拥有者回合计算的剩余持续时间。
    /// </summary>
    public int OwnerTurnDuration { get; } = context.Status.OwnerTurnDuration;

    /// <summary>
    /// 获取按全局回合计算的剩余持续时间。
    /// </summary>
    public int GlobalTurnDuration { get; } = context.Status.GlobalTurnDuration;

    /// <summary>
    /// 获取按轮次计算的剩余持续时间。
    /// </summary>
    public int RoundDuration { get; } = context.Status.RoundDuration;

    /// <summary>
    /// 为 GDScript 表现层读取整数字段提供稳定的跨语言入口。
    /// </summary>
    /// <param name="propertyName">需要读取的字段名称。</param>
    /// <returns>对应的整数值；名称不受支持时返回 0。</returns>
    public int GetFeedbackInt(string propertyName)
    {
        return propertyName switch
        {
            nameof(ReasonId) => ReasonId,
            nameof(CurrentStacks) => CurrentStacks,
            nameof(OwnerTurnDuration) => OwnerTurnDuration,
            nameof(GlobalTurnDuration) => GlobalTurnDuration,
            nameof(RoundDuration) => RoundDuration,
            _ => 0
        };
    }

    /// <summary>
    /// 为 GDScript 表现层读取实体字段提供稳定的跨语言入口。
    /// </summary>
    /// <param name="propertyName">需要读取的节点字段名称。</param>
    /// <returns>对应节点；名称不受支持时返回 null。</returns>
    public Node GetFeedbackNode(string propertyName)
    {
        return propertyName switch
        {
            nameof(Owner) => Owner,
            nameof(Source) => Source,
            _ => null
        };
    }

    /// <summary>
    /// 为 GDScript 表现层读取字符串字段提供稳定的跨语言入口。
    /// </summary>
    /// <param name="propertyName">需要读取的字段名称。</param>
    /// <returns>对应字符串；名称不受支持时返回空字符串。</returns>
    public string GetFeedbackString(string propertyName)
    {
        return propertyName == nameof(StatusId) ? StatusId.ToString() : string.Empty;
    }
}
