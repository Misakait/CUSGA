using Godot;

namespace CUSGA.core.combat.status;

[GlobalClass]
public abstract partial class StatusEffectData : Resource
{
    /// <summary>
    /// 状态的唯一标识，用于叠加、刷新、移除和存档定位。
    /// </summary>
    [Export] public StringName Id { get; set; }

    /// <summary>
    /// 状态在 UI 中显示的名称。为空时 UI 会回退显示 <see cref="Id"/>。
    /// </summary>
    [Export] public string DisplayName { get; set; } = string.Empty;

    /// <summary>
    /// 状态在悬停提示框中显示的描述文本，用于解释效果、持续时间或其它玩家需要理解的信息。
    /// </summary>
    [Export(PropertyHint.MultilineText)] public string Description { get; set; } = string.Empty;

    /// <summary>
    /// 状态在 Buff 栏中显示的图标。未配置时 UI 会使用兜底图标，避免状态不可见。
    /// </summary>
    [Export] public Texture2D Icon { get; set; }

    [Export] public int MaxStacks { get; set; } = 1;
    [Export] public StackPolicy Policy { get; set; } = StackPolicy.ResetDuration;

    [Export] public DurationExpirePolicy ExpirePolicy { get; set; } = DurationExpirePolicy.FirstExpired;

    /// <summary>
    /// 持续时间在对应行动/轮次的开始还是结束扣减。
    /// 默认回合/轮次开始扣减。
    /// </summary>
    [Export] public DurationTickTiming DurationTickTiming { get; set; } = DurationTickTiming.Start;

    /// <summary>
    /// 同一 hook phase 内的默认执行优先级。
    /// 数值越小越早执行。
    /// </summary>
    [Export] public int DefaultHookPriority { get; set; } = 0;

    // 持续该单位自己的 N 次行动
    [Export] public int InitOwnerTurnDuration { get; set; } = 0;

    // 持续全场 N 次行动，不管是谁行动
    [Export] public int InitGlobalTurnDuration { get; set; } = 0;

    // 所有存活单位都至少行动过一次，算一轮
    [Export] public int InitRoundDuration { get; set; } = 0;

    public bool HasFiniteDuration =>
        InitOwnerTurnDuration > 0 ||
        InitGlobalTurnDuration > 0 ||
        InitRoundDuration > 0;

    public abstract StatusEffectInstance CreateInstance(Node source, Node owner);
}
